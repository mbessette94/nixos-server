{ config, pkgs, vars, ... }:
let
  # SSD -- radicale (CalDAV/CardDAV) only; small, stays put.
  dataDirectory = "${vars.appDataDir}/applications/opencloud";
  # HDD -- opencloud itself (WebDAV file storage + its /etc config). Bulk data,
  # less latency-sensitive than calendar/contacts, so it lives on the big pool
  # instead of the SSD. OpenCloud has no built-in storage tiering (single global
  # backend), so this split is done at the container/volume level instead.
  davDataDirectory = "${vars.hddPool}/applications/opencloud";

  # See service.opencloud.csp.yaml for what this is and why. Kept as a plain
  # YAML file (rather than inlined as a Nix string) so it stays indentation-safe
  # and diffable; @DOMAIN@ is the only templated bit.
  cspFile = pkgs.writeText "opencloud-csp.yaml"
    (builtins.replaceStrings [ "@DOMAIN@" ] [ vars.domain ] (builtins.readFile ./service.opencloud.csp.yaml));

  # CalDAV/CardDAV (Radicale) integration -- see the radicale container and
  # its comments below. Neither of these needs templating (no domain, no
  # secret -- the backend address is just the podman container name).
  radicaleConfigFile = pkgs.writeText "radicale-config" (builtins.readFile ./service.opencloud.radicale.conf);
  radicaleProxyFile = pkgs.writeText "opencloud-proxy.yaml" (builtins.readFile ./service.opencloud.proxy.yaml);
in
{
  # OpenCloud (open-source continuation of ownCloud Infinite Scale): files/drive
  # replacement for Nextcloud, at drive.${vars.domain}. Reverse-proxied by Traefik
  # (public-net, labels) same as portainer/ntfy -- Traefik terminates TLS, so
  # OpenCloud's own TLS is disabled and it just serves plain HTTP on 9200.
  #
  # OIDC: OC_EXCLUDE_RUN_SERVICES=idp defers auth entirely to pocket-id. The
  # client secret lives in secret.opencloud.oidc-client-secret.age (agenix),
  # loaded as WEB_OIDC_CLIENT_SECRET via environmentFiles below. Client was
  # registered in pocket-id for https://drive.${vars.domain} with
  # token endpoint auth method client_secret_basic (what OpenCloud expects) and
  # redirect URI https://drive.${vars.domain}/oidc-callback.html -- if login
  # fails with a redirect_uri mismatch, check the proxy's logs for the exact
  # URI it requested and update the pocket-id client to match.
  age.secrets."opencloud.oidc-client-secret".file = ./secret.opencloud.oidc-client-secret.age;

  virtualisation.oci-containers.containers.opencloud = {
    image = "opencloudeu/opencloud-rolling:latest";
    autoStart = true;

    # public-net for Traefik, private-net to reach the radicale container
    # below by name (radicale itself is private-net only -- never
    # Traefik-visible, see its comment).
    extraOptions = [ "--network=public-net" "--network=private-net" ];

    volumes = [
      "${davDataDirectory}/config:/etc/opencloud"
      "${davDataDirectory}/data:/var/lib/opencloud"
    ];

    environmentFiles = [
      config.age.secrets."opencloud.oidc-client-secret".path
    ];

    environment = {
      OC_URL = "https://drive.${vars.domain}";
      PROXY_HTTP_ADDR = "0.0.0.0:9200";
      PROXY_TLS = "false";
      PROXY_FORCE_STRICT_TRANSPORT_SECURITY = "true";
      PROXY_CSP_CONFIG_FILE_LOCATION = "/etc/opencloud/csp.yaml";

      # --- OIDC (pocket-id) ---
      OC_EXCLUDE_RUN_SERVICES = "idp";
      OC_OIDC_ISSUER = "https://id.${vars.domain}";
      PROXY_OIDC_ACCESS_TOKEN_VERIFY_METHOD = "jwt";
      PROXY_OIDC_REWRITE_WELLKNOWN = "true";
      PROXY_USER_OIDC_CLAIM = "preferred_username";
      PROXY_USER_CS3_CLAIM = "username";
      PROXY_AUTOPROVISION_ACCOUNTS = "true";
      WEB_OIDC_CLIENT_ID = "96b309bc-d531-4bca-af04-7e4522c6283f";
      # WEB_OIDC_CLIENT_SECRET comes from environmentFiles above.
    };

    labels = {
      "traefik.enable" = "true";
      "traefik.http.routers.opencloud.rule" = "Host(`drive.${vars.domain}`)";
      "traefik.http.routers.opencloud.entrypoints" = "websecure";
      "traefik.http.routers.opencloud.tls.certresolver" = "myresolver";
      "traefik.http.routers.opencloud.middlewares" = "internal-secure@file";
      "traefik.http.services.opencloud.loadbalancer.server.port" = "9200";
    };
  };

  # Radicale: CalDAV/CardDAV server, proxied by OpenCloud's own proxy service
  # (see service.opencloud.proxy.yaml's additional_policies) so users get a
  # Personal Calendar/Address Book out of the box. Radicale does zero
  # authentication itself -- it fully trusts an X-Remote-User header the
  # proxy sets after its own auth already succeeded (see
  # service.opencloud.radicale.conf's [auth] section) -- so it MUST stay off
  # public-net and get no Traefik labels/published ports. private-net only;
  # opencloud reaches it by container name (http://radicale:5232) since it's
  # attached to private-net too.
  virtualisation.oci-containers.containers.radicale = {
    image = "opencloudeu/radicale:latest";
    autoStart = true;
    user = "1000:1000";

    extraOptions = [ "--network=private-net" ];

    volumes = [
      "${dataDirectory}/radicale-config:/etc/radicale/config"
      "${dataDirectory}/radicale-data:/var/lib/radicale"
    ];
  };

  systemd.services.podman-opencloud = {
    after = [ "podman-networks.service" ];
    requires = [ "podman-networks.service" ];
  };

  # Owner is captain (host UID 1000), NOT root: the opencloud-rolling image
  # runs its process as a fixed non-root UID 1000 ("opencloud-user") with no
  # userns remapping, and captain happens to be host UID 1000 too -- so
  # owning these dirs as captain gives the container's UID direct read/write
  # access. (root ownership, the pattern used elsewhere in this repo, only
  # works for images that run as root -- ntfy and portainer both do; this one
  # doesn't, which is what caused the "permission denied" crash loop.)
  systemd.tmpfiles.rules = [
    "d ${davDataDirectory}/config 0770 captain captain - -"
    "d ${davDataDirectory}/data 0770 captain captain - -"
    "d ${dataDirectory}/radicale-data 0770 captain captain - -"
    # 'C' only copies if the target is missing -- won't clobber a manual edit
    # on subsequent rebuilds.
    "C ${davDataDirectory}/config/csp.yaml 0644 captain captain - ${cspFile}"
    "C ${davDataDirectory}/config/proxy.yaml 0644 captain captain - ${radicaleProxyFile}"
    "C ${dataDirectory}/radicale-config 0644 captain captain - ${radicaleConfigFile}"
  ];
}
