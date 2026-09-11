{
  lib,
  config,
  ...
}: let
  inherit
    (lib)
    mkEnableOption
    mkOption
    mkIf
    types
    genAttrs
    concatStringsSep
    optional
    optionals
    length
    unique
    flatten
    filterAttrs
    mapAttrsToList
    attrNames
    any
    hasInfix
    hasPrefix
    ;
  cfg = config.services.localProxy;

  serviceOpts = types.submodule ({name, ...}: {
    options = {
      upstream = mkOption {
        type = types.str;
        default = "127.0.0.1";
        description = "Upstream host to proxy to.";
      };

      port = mkOption {
        type = types.port;
        description = "Upstream port to proxy to.";
      };

      paths = mkOption {
        type = types.listOf types.str;
        default = ["/${name}"];
        description = ''
          Paths this service owns. `"/"` claims the root catch-all; every other
          path is proxied as a prefix glob (`<path>*`).
        '';
      };

      streaming = mkOption {
        type = types.bool;
        default = false;
        description = "Disable response buffering (`flush_interval -1`), for SSE/websocket upstreams.";
      };

      responseHeaderTimeout = mkOption {
        type = types.nullOr types.str;
        default = null;
        example = "300s";
        description = "How long to wait for the upstream's response headers before failing the request.";
      };
    };
  });

  # `handle` rather than a bare `reverse_proxy <matcher>`: Caddy sorts `handle`
  # blocks by matcher specificity and evaluates the matcher-less one last, so a
  # root service can never swallow another's paths and emission order is free.
  #
  # Host header is deliberately NOT rewritten (Caddy's default: preserved).
  # houston's own Host allowlist is what gates access, and it 403s any request
  # whose Origin disagrees with Host, so a proxy that rewrote Host would break it.
  mkHandle = svc: path: let
    # Prefix glob (path* not path/*), so a bare /v1 is proxied along with
    # /v1/...; naspi's reverse-proxy.nix hit this with /radarr vs /radarr/.
    matcher =
      if path == "/"
      then ""
      else " ${path}*";

    proxyLines =
      optional svc.streaming "flush_interval -1"
      ++ optionals (svc.responseHeaderTimeout != null) [
        "transport http {"
        "  response_header_timeout ${svc.responseHeaderTimeout}"
        "}"
      ];

    reverseProxy =
      if proxyLines == []
      then "reverse_proxy ${svc.upstream}:${toString svc.port}"
      else ''
        reverse_proxy ${svc.upstream}:${toString svc.port} {
            ${concatStringsSep "\n    " proxyLines}
          }'';
  in ''
    handle${matcher} {
      ${reverseProxy}
    }
  '';

  vhostKey = concatStringsSep " " (map (h: "http://${h}") cfg.hostNames);

  rootClaimants = filterAttrs (_: svc: builtins.elem "/" svc.paths) cfg.services;
  allPaths = flatten (mapAttrsToList (_: svc: svc.paths) cfg.services);
in {
  options.services.localProxy = {
    enable = mkEnableOption "Caddy reverse proxy for local services, addressed by path prefix";

    hostNames = mkOption {
      type = types.listOf types.str;
      default = [config.hostname "localhost"];
      description = "Names/addresses the vhost answers to (without the `http://` prefix, which the module adds).";
    };

    lanInterfaces = mkOption {
      type = types.listOf types.str;
      default = [];
      example = ["enp97s0"];
      description = ''
        Interfaces to open TCP 80 on. Every registered service becomes reachable,
        unauthenticated, to whatever network segment the named interface is on —
        empty means tailnet-only reach, since `tailscale0` is already trusted.
      '';
    };

    services = mkOption {
      type = types.attrsOf serviceOpts;
      default = {};
      description = "Services to reverse-proxy, keyed by name.";
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = length (attrNames rootClaimants) <= 1;
        message = "services.localProxy: more than one service claims \"/\": ${concatStringsSep ", " (attrNames rootClaimants)}";
      }
      {
        assertion = length allPaths == length (unique allPaths);
        message = "services.localProxy: a path is claimed by more than one service.";
      }
      {
        # A bad hostName (empty list, an already-scheme-prefixed entry, or one
        # with a space) produces a site address that silently never matches,
        # rather than an eval or runtime error.
        assertion = cfg.hostNames != [] && !(any (h: hasInfix " " h || hasPrefix "http://" h) cfg.hostNames);
        message = "services.localProxy: hostNames must be non-empty, space-free, and without a scheme prefix (the module adds `http://`).";
      }
    ];

    services.caddy = {
      enable = true;

      virtualHosts.${vhostKey} = {
        # The vhost key above is space-separated http:// addresses; nixpkgs'
        # default log filename derives from that key, which would mangle into
        # an ~89-char name.
        logFormat = "output file ${config.services.caddy.logDir}/access-local-proxy.log";
        extraConfig = concatStringsSep "\n" (flatten (mapAttrsToList (_: svc: map (mkHandle svc) svc.paths) cfg.services));
      };
    };

    # Deliberately not networking.firewall.allowedTCPPorts: that opens every
    # interface, including whatever untrusted network a host roams onto.
    networking.firewall.interfaces = genAttrs cfg.lanInterfaces (_: {
      allowedTCPPorts = [80];
    });
  };
}
