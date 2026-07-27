{ config, pkgs, lib, vars, ... }:
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
        # Static routes for non-container backends (LAN hosts like unifi,
        # homeassistant, technitium) — router.*.yml symlinked into captain's
        # home by home.captain.nix.
        file = {
          directory = "${config.users.users.captain.home}/.config/traefik/dynamic";
          watch = true;
        };

        # Auto-discover containers on the `web` network by their Traefik labels.
        # Reaches the podman API through the read-only socket-proxy, never the
        # raw socket. exposedByDefault = false -> a container is only routed if
        # it sets `traefik.enable=true`.
        docker = {
          endpoint = "tcp://127.0.0.1:2375";
          network = "web";
          exposedByDefault = false;
          watch = true;
        };
      };

      entryPoints = {
        web = {
          address = ":${vars.ports.traefik-http}";
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
          address = ":${vars.ports.traefik-https}";
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
            email = vars.acmeEmail;
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

  # Traefik's docker provider talks to the socket-proxy; make sure it's up first.
  systemd.services.traefik = {
    after = [ "podman-socket-proxy.service" ];
    wants = [ "podman-socket-proxy.service" ];
  };
}
