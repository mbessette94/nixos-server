{ config, vars, ... }:
{
  services.traefik = {
    enable = true;

    environmentFiles = [
      config.age.secrets."secret.traefik.cloudflare-api-token".path
    ];

    # --- Dynamic config: routes for non-container backends --------------------
    # Written directly here (served via the file provider the NixOS module wires
    # up from dynamicConfigOptions). Replaces the old router.*.yml fragments.
    # Container backends are still auto-discovered via the docker provider below.
    dynamicConfigOptions.http = {
      routers = {
        # Traefik dashboard (internal API — no backend service).
        traefik = {
          rule = "Host(`traefik.${vars.domain}`)";
          entryPoints = [ "websecure" ];
          service = "api@internal";
          middlewares = [ "internal-secure@file" ];
          tls.certResolver = "myresolver";
        };

        # LAN backends (hosts managed outside this repo).
        dns = {
          rule = "Host(`dns.${vars.domain}`)";
          entryPoints = [ "websecure" ];
          service = "technitium";
          middlewares = [ "internal-secure@file" ];
          tls.certResolver = "myresolver";
        };
        gateway = {
          rule = "Host(`gateway.${vars.domain}`)";
          entryPoints = [ "websecure" ];
          service = "unifi";
          middlewares = [ "internal-secure@file" ];
          tls.certResolver = "myresolver";
        };
        home = {
          rule = "Host(`home.${vars.domain}`)";
          entryPoints = [ "websecure" ];
          service = "homeassistant";
          middlewares = [ "internal-secure@file" ];
          tls.certResolver = "myresolver";
        };

        # Host services on loopback.
        manage = {
          rule = "Host(`manage.${vars.domain}`)";
          entryPoints = [ "websecure" ];
          service = "cockpit";
          middlewares = [ "internal-secure@file" ];
          tls.certResolver = "myresolver";
        };
        id = {
          rule = "Host(`id.${vars.domain}`)";
          entryPoints = [ "websecure" ];
          service = "pocket-id";
          middlewares = [ "internal-secure@file" ];
          tls.certResolver = "myresolver";
        };

        # neko/vbrowser: two routers (websocket + UI) sharing one backend
        # service. Both carry the internal-secure allowlist.
        neko-ui = {
          rule = "Host(`vbrowser.${vars.domain}`)";
          entryPoints = [ "websecure" ];
          service = "neko";
          middlewares = [ "internal-secure@file" ];
          priority = 10;
          tls.certResolver = "myresolver";
        };
        neko-ws = {
          rule = "Host(`vbrowser.${vars.domain}`) && HeaderRegexp(`Upgrade`, `(?i)websocket`)";
          entryPoints = [ "websecure" ];
          service = "neko";
          middlewares = [ "internal-secure@file" ];
          priority = 100;
          tls.certResolver = "myresolver";
        };
      };

      services = {
        technitium.loadBalancer.servers = [ { url = "http://${vars.hosts.dns}:5380"; } ];
        homeassistant.loadBalancer.servers = [ { url = "http://${vars.hosts.homeAssistant}:8123"; } ];
        cockpit.loadBalancer.servers = [ { url = "http://127.0.0.1:${toString vars.ports.cockpit}"; } ];
        pocket-id.loadBalancer.servers = [ { url = "http://127.0.0.1:${toString vars.ports.pocket-id}"; } ];

        # UniFi UDM serves a self-signed cert -> skip backend TLS verification.
        unifi.loadBalancer = {
          servers = [ { url = "https://${vars.hosts.gateway}"; } ];
          serversTransport = "insecureTransport";
        };
        neko.loadBalancer = {
          servers = [ { url = "http://${vars.hosts.neko}:8080"; } ];
          responseForwarding.flushInterval = "100ms";
        };
      };

      serversTransports.insecureTransport.insecureSkipVerify = true;

      # Shared middlewares (ported from the old router.middlewares.yml).
      middlewares = {
        fragment-internal-whitelist.ipAllowList.sourceRange = [
          "127.0.0.1/32" # Localhost
          "192.168.1.0/24" # Main LAN
          "192.168.2.0/24" # Secondary/VLAN
          "192.168.3.45/32" # Specific static device
          "192.168.3.1/32"
          "192.168.20.0/24" # VPN
        ];
        fragment-secure-headers.headers = {
          sslRedirect = true;
          stsSeconds = 63072000;
          stsIncludeSubdomains = true;
          stsPreload = true;
          forceSTSHeader = true;
          frameDeny = true;
          contentTypeNosniff = true;
          browserXssFilter = true;
          referrerPolicy = "same-origin";
        };
        fragment-compression.compress = { };
        base-secure.chain.middlewares = [
          "fragment-compression"
          "fragment-secure-headers"
        ];
        internal-secure.chain.middlewares = [
          "base-secure"
          "fragment-internal-whitelist"
        ];
      };
    };

    # Traefik static configuration
    staticConfigOptions = {
      api = {
        dashboard = true;
      };

      ping = { };

      providers = {
        docker = {
          endpoint = "tcp://127.0.0.1:2375";
          network = "web";
          exposedByDefault = false;
          watch = true;
        };
      };

      entryPoints = {
        web = {
          address = ":${toString vars.ports.traefik-http}";
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
          address = ":${toString vars.ports.traefik-https}";
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
