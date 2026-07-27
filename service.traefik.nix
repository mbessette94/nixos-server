{ config, pkgs, lib, ... }:
{
  # Enable the Traefik service
  services.traefik = {
    enable = true;

    environmentFiles = [
      config.age.secrets."secret.traefik.cloudflare-api-token".path
    ];

    # Traefik static configuration mapped directly from your YAML
    staticConfigOptions = {
      api = {
        dashboard = true;
      };

      ping = {};

      providers = {
        docker = {
          exposedByDefault = false;
        };
        file = {
          directory = "${config.users.users.captain.home}/.config/traefik/dynamic";
          watch = true;
        };
      };

      entryPoints = {
        web = {
          address = ":80";
          http = {
            redirections = {
              entryPoint = {
                to = "websecure";
                scheme = "https";
              };
            };
          };
        };

        websecure = {
          address = ":443";
          transport = {
            respondingTimeouts = {
              readTimeout = "0s";
              writeTimeout = "0s";
              idleTimeout = "180s";
            };
          };
          http = {
            tls = {
              certResolver = "myresolver";
              domains = [
                {
                  main = "thiccdata.io";
                  sans = [ "*.thiccdata.io" ];
                }
                {
                  main = "proxy.thiccdata.io";
                  sans = [ "*.proxy.thiccdata.io" ];
                }
              ];
            };
          };
        };
      };

      certificatesResolvers = {
        myresolver = {
          acme = {
            storage = "${config.services.traefik.dataDir}/acme.json";
            email = "blade30912@gmail.com";
            dnsChallenge = {
              provider = "cloudflare";
              resolvers = [
                "1.1.1.1:53"
                "8.8.8.8:53"
              ];
            };
          };
        };
      };
    };
  };

  # Open standard web ports in the firewall
  networking.firewall.allowedTCPPorts = [ 80 443 ];
}