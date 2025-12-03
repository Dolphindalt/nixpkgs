{
  config,
  lib,
  pkgs,
  ...
}:

with lib;

let
  cfg = config.services.lila;

  # Generate application.conf from NixOS options
  applicationConf = pkgs.writeText "lila-application.conf" ''
    include "${cfg.package}/share/lila/conf.examples/base.conf"

    http.port = ${toString cfg.port}

    mongodb {
      uri = "${cfg.database.mongodb.uri}"
    }

    redis {
      uri = "${cfg.database.redis.uri}"
    }

    net {
      domain = "${cfg.domain}"
      socket.domains = ${builtins.toJSON cfg.socketDomains}
      asset.domain = "${cfg.assetDomain}"
      asset.base_url = "${cfg.assetBaseUrl}"
      base_url = "${cfg.baseUrl}"
      email = "${cfg.email}"
      crawlable = ${if cfg.crawlable then "true" else "false"}
      ratelimit = ${if cfg.ratelimit then "true" else "false"}
    }

    ${optionalString (cfg.secrets.bpassSecretFile != null) ''
      user.password.bpass.secret = "''${BPASS_SECRET}"
    ''}
    ${optionalString (cfg.secrets.bpassSecretFile == null) ''
      user.password.bpass.secret = "dev_secret_not_for_production"
    ''}

    ${cfg.extraConfig}
  '';

  loggerConf = pkgs.writeText "lila-logger.xml" cfg.logging.config;
in
{
  options.services.lila = {
    enable = mkEnableOption "Lila (Lichess) chess server";

    package = mkPackageOption pkgs "lila" { };

    user = mkOption {
      type = types.str;
      default = "lila";
      description = "User account under which lila runs";
    };

    group = mkOption {
      type = types.str;
      default = "lila";
      description = "Group under which lila runs";
    };

    port = mkOption {
      type = types.port;
      default = 9663;
      description = "HTTP port for lila";
    };

    domain = mkOption {
      type = types.str;
      example = "chess.example.com";
      description = "Domain name for the lila instance";
    };

    baseUrl = mkOption {
      type = types.str;
      default = "http://${cfg.domain}:${toString cfg.port}";
      defaultText = literalExpression ''"http://''${config.services.lila.domain}:''${toString config.services.lila.port}"'';
      description = "Base URL for the lila instance";
    };

    assetDomain = mkOption {
      type = types.str;
      default = cfg.domain;
      defaultText = literalExpression "config.services.lila.domain";
      description = "Domain for static assets (can be a CDN)";
    };

    assetBaseUrl = mkOption {
      type = types.str;
      default = cfg.baseUrl;
      defaultText = literalExpression "config.services.lila.baseUrl";
      description = "Base URL for static assets";
    };

    email = mkOption {
      type = types.str;
      default = "";
      example = "noreply@chess.example.com";
      description = "Email address for outgoing mail";
    };

    crawlable = mkOption {
      type = types.bool;
      default = false;
      description = "Whether to allow search engine crawling";
    };

    ratelimit = mkOption {
      type = types.bool;
      default = true;
      description = "Whether to enable rate limiting";
    };

    socketDomains = mkOption {
      type = types.listOf types.str;
      default = [ "localhost:9664" ];
      example = [ "ws.chess.example.com" ];
      description = ''
        WebSocket server domains (requires lila-ws).
        See https://github.com/lichess-org/lila-ws
      '';
    };

    database = {
      mongodb = {
        uri = mkOption {
          type = types.str;
          default = "mongodb://127.0.0.1:27017?appName=lila";
          description = "MongoDB connection URI";
        };

        createLocally = mkOption {
          type = types.bool;
          default = true;
          description = "Whether to create a local MongoDB instance";
        };

        package = mkPackageOption pkgs "mongodb" {
          example = "mongodb-ce";
        };
      };

      redis = {
        uri = mkOption {
          type = types.str;
          default = "redis://127.0.0.1";
          description = "Redis connection URI";
        };

        createLocally = mkOption {
          type = types.bool;
          default = true;
          description = "Whether to create a local Redis instance";
        };
      };
    };

    secrets = {
      bpassSecretFile = mkOption {
        type = types.nullOr types.path;
        default = null;
        example = "/run/secrets/lila-bpass";
        description = ''
          File containing the bpass secret for password encryption.
          If null, a default insecure value will be used (NOT recommended for production).
        '';
      };
    };

    javaOptions = mkOption {
      type = types.listOf types.str;
      default = [
        "-Xmx4G"
        "-Xss4M"
        "-XX:MaxMetaspaceSize=1G"
      ];
      example = [
        "-Xmx8G"
        "-Xss8M"
      ];
      description = "JVM options for the lila process";
    };

    extraConfig = mkOption {
      type = types.lines;
      default = "";
      example = ''
        search {
          enabled = true
          endpoint = "http://localhost:9673"
        }

        mailer {
          primary {
            mock = false
            host = "smtp.example.com"
            port = 587
            tls = true
          }
        }
      '';
      description = "Extra configuration to append to application.conf (HOCON format)";
    };

    logging = {
      config = mkOption {
        type = types.lines;
        default = ''
          <configuration>
            <appender name="STDOUT" class="ch.qos.logback.core.ConsoleAppender">
              <encoder>
                <pattern>%d{HH:mm:ss.SSS} [%thread] %-5level %logger{36} - %msg%n</pattern>
              </encoder>
            </appender>
            <root level="INFO">
              <appender-ref ref="STDOUT" />
            </root>
          </configuration>
        '';
        description = "Logging configuration (Logback XML format)";
      };
    };

    openFirewall = mkOption {
      type = types.bool;
      default = false;
      description = "Whether to open the firewall for the lila port";
    };
  };

  config = mkIf cfg.enable {
    # Assertions for required options
    assertions = [
      {
        assertion = cfg.domain != "";
        message = "services.lila.domain must be set";
      }
    ];

    # Create user and group
    users.users.${cfg.user} = mkIf (cfg.user == "lila") {
      isSystemUser = true;
      group = cfg.group;
      description = "Lila (Lichess) chess server user";
      home = "/var/lib/lila";
      createHome = true;
    };

    users.groups.${cfg.group} = mkIf (cfg.group == "lila") { };

    # Set up MongoDB if requested
    services.mongodb = mkIf cfg.database.mongodb.createLocally {
      enable = true;
      package = cfg.database.mongodb.package;
    };

    # Set up Redis if requested
    services.redis.servers.lila = mkIf cfg.database.redis.createLocally {
      enable = true;
      port = 6379;
    };

    # Open firewall if requested
    networking.firewall.allowedTCPPorts = mkIf cfg.openFirewall [ cfg.port ];

    # Systemd service
    systemd.services.lila = {
      description = "Lila (Lichess) chess server";
      after = [
        "network.target"
      ]
      ++ optional cfg.database.mongodb.createLocally "mongodb.service"
      ++ optional cfg.database.redis.createLocally "redis-lila.service";
      wantedBy = [ "multi-user.target" ];

      environment = {
        JAVA_HOME = "${pkgs.jdk21}";
      };

      script = ''
        # Load secrets
        ${optionalString (cfg.secrets.bpassSecretFile != null) ''
          export BPASS_SECRET=$(cat ${cfg.secrets.bpassSecretFile})
        ''}

        # Start lila
        exec ${cfg.package}/bin/lila \
          ${concatMapStringsSep " " (opt: "-J${opt}") cfg.javaOptions} \
          -Dconfig.file=${applicationConf} \
          -Dlogger.file=${loggerConf} \
          -Dhttp.port=${toString cfg.port}
      '';

      serviceConfig = {
        User = cfg.user;
        Group = cfg.group;
        WorkingDirectory = "/var/lib/lila";
        StateDirectory = "lila";
        StateDirectoryMode = "0750";
        RuntimeDirectory = "lila";
        RuntimeDirectoryMode = "0750";

        # Security hardening
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        ReadWritePaths = [ "/var/lib/lila" ];
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
        RestrictAddressFamilies = [
          "AF_UNIX"
          "AF_INET"
          "AF_INET6"
        ];
        RestrictNamespaces = true;
        LockPersonality = true;
        RestrictRealtime = true;
        RestrictSUIDSGID = true;
        PrivateDevices = true;

        # Resource limits (adjust as needed)
        MemoryMax = "8G";

        # Restart on failure
        Restart = "on-failure";
        RestartSec = "10s";
      };
    };
  };

  meta = {
    maintainers = with maintainers; [ dolphindalt ];
  };
}
