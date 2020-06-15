# WARNING!!! THIS IS BROKEN! DO NOT USE!

{ lib, pkgs, config, ... }:
let
  cfg = config.services.cardano-graphql;
  sources = import ../sources.nix;
  hasuraConfigFile = __toFile "config.yaml" (__toJSON {
    version = 2;
    endpoint = "${cfg.hasuraProtocol}://${cfg.hasuraIp}:${toString cfg.enginePort}";
    metadata_directory = "metadata";
    actions = {
      kind = "synchronous";
      handler_webhook_baseurl = "http://localhost:${toString cfg.port}";
    };
  });
in {
  options = {
    services.cardano-graphql = {
      enable = lib.mkEnableOption "cardano-explorer graphql service";

      dbUser = lib.mkOption {
        type = lib.types.str;
        default = "cexplorer";
      };

      db = lib.mkOption {
        type = lib.types.str;
        default = "cexplorer";
      };

      enginePort = lib.mkOption {
        type = lib.types.int;
        default = 9999;
      };

      port = lib.mkOption {
        type = lib.types.int;
        default = 3100;
      };

      hasuraIp = lib.mkOption {
        type = lib.types.str;
        default = "127.0.0.1";
      };

      hasuraProtocol = lib.mkOption {
        type = lib.types.str;
        default = "http";
      };

      enablePrometheus = lib.mkOption {
        type = lib.types.bool;
        default = true;
      };

      enableTracing = lib.mkEnableOption "tracing";
      enableCache = lib.mkEnableOption "cache";

      queryDepthLimit = lib.mkOption {
        type = lib.types.nullOr lib.types.int;
        default = null;
      };

      allowedOrigins = lib.mkOption {
        type = lib.types.nullOr (lib.types.separatedString " ");
        default = null;
      };
      allowIntrospection = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Allows introspection queries";
      };
      whitelistPath = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        description = "Source directory or file to generate whitelist from";
      };
      projectPath = lib.mkOption {
        type = lib.types.path;
        default = ../../hasura/project;
        description = "Source directory for project";
      };
    };
  };
  config = let
    # TODO: there has to be a better way to handle boolean env vars in nodejs???
    boolToNodeJSEnv = bool: if bool then "true" else "false";
    frontend = (import ../../.).cardano-graphql;
    persistgraphql = (import ../../.).persistgraphql;
    hasura-cli = (import ../../.).hasura-cli;
    cli-ext = (import ../../.).cli-ext;
    hasuraBaseUri = "${cfg.hasuraProtocol}://${cfg.hasuraIp}:${toString cfg.enginePort}";
    pluginLibPath = pkgs.lib.makeLibraryPath [
      pkgs.stdenv.cc.cc.lib
    ];
    installHasuraCLI = ''
      hasura plugins install cli-ext
      orig_size=$(stat --printf=%s ~/.hasura/plugins/bin/hasura-cli_ext)
      patchelf --set-interpreter ${pkgs.stdenv.glibc.out}/lib/ld-linux-x86-64.so.2 \
               --set-rpath "${pluginLibPath}" \
               ~/.hasura/plugins/bin/hasura-cli_ext
          new_size=$(stat --printf=%s ~/.hasura/plugins/bin/hasura-cli_ext)
    ###### zeit-pkg fixing starts here.
    # we're replacing plaintext js code that looks like
    # PAYLOAD_POSITION = '1234                  ' | 0
    # [...]
    # PRELUDE_POSITION = '1234                  ' | 0
    # ^-----20-chars-----^^------22-chars------^
    # ^-- grep points here
    #
    # var_* are as described above
    # shift_by seems to be safe so long as all patchelf adjustments occur
    # before any locations pointed to by hardcoded offsets
    var_skip=20
    var_select=22
    shift_by=$(expr $new_size - $orig_size)
    function fix_offset {
      # $1 = name of variable to adjust
      location=$(grep -obUam1 "$1" ~/.hasura/plugins/bin/hasura-cli_ext | cut -d: -f1)
      location=$(expr $location + $var_skip)
      value=$(dd if=~/.hasura/plugins/bin/hasura-cli_ext iflag=count_bytes,skip_bytes skip=$location \
                 bs=1 count=$var_select status=none)
      value=$(expr $shift_by + $value)
      echo -n $value | dd of=~/.hasura/plugins/bin/hasura-cli_ext bs=1 seek=$location conv=notrunc
    }
    fix_offset PAYLOAD_POSITION
    fix_offset PRELUDE_POSITION
    '';
  in lib.mkIf cfg.enable {
    systemd.services.cardano-graphql = {
      wantedBy = [ "multi-user.target" ];
      requires = [ "graphql-engine.service" ];
      environment = {
        HASURA_URI = hasuraBaseUri;
        PROMETHEUS_METRICS = boolToNodeJSEnv cfg.enablePrometheus;
        TRACING = boolToNodeJSEnv (cfg.enableTracing || cfg.enablePrometheus);
        ALLOW_INTROSPECTION = boolToNodeJSEnv cfg.allowIntrospection;
        CACHE_ENABLED = boolToNodeJSEnv cfg.enableCache;
        API_PORT = toString cfg.port;
      } //
      (lib.optionalAttrs (cfg.allowedOrigins != null) { ALLOWED_ORIGINS = cfg.allowedOrigins; }) //
      (lib.optionalAttrs (cfg.queryDepthLimit != null) { QUERY_DEPTH_LIMIT = toString cfg.queryDepthLimit; }) //
      (lib.optionalAttrs (cfg.whitelistPath != null) { WHITELIST_PATH = cfg.whitelistPath; });
      path = with pkgs; [ netcat curl postgresql jq frontend hasura-cli glibc.bin patchelf ];
      preStart = ''
        set -exuo pipefail
        for x in {1..10}; do
          nc -z ${cfg.hasuraIp} ${toString cfg.enginePort} && break
          echo loop $x: waiting for graphql-engine 2 sec...
          sleep 2
        done
        rm -rf project
        cp -a ${cfg.projectPath} project
        cp ${hasuraConfigFile} project/config.yaml
        rm -rf ~/.hasura/plugins
        ${installHasuraCLI}
        hasura --project project migrate apply --down all
        hasura --project project migrate apply --up all
        hasura --project project metadata clear
        hasura --project project metadata apply
      '';
      script = ''
        exec cardano-graphql
      '';
    };
  };
}
