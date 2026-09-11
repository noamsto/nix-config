{
  lib,
  pkgs,
  config,
  ...
}: let
  inherit
    (lib)
    mkEnableOption
    mkOption
    mkIf
    types
    literalExpression
    genAttrs
    concatStringsSep
    optional
    optionals
    escapeXML
    length
    unique
    flatten
    filter
    head
    elem
    filterAttrs
    mapAttrsToList
    attrNames
    attrValues
    any
    all
    subtractLists
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

      stripPrefix = mkOption {
        type = types.listOf types.str;
        default = [];
        example = ["/houston"];
        description = ''
          Which of `paths` are proxied with the prefix removed, so the upstream
          sees `/` rather than the prefix (Caddy's `handle_path`).

          Pair a stripped path with a `"/"` claim for an app that answers only
          at its own root and asks for its assets by absolute URL: the stripped
          path is the door in, and the root catch-all serves everything the app
          requests once it has loaded.
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

      landing = {
        advertise = mkOption {
          type = types.bool;
          default = true;
          description = ''
            Give this service a button on the landing page. Turn it off for an
            upstream with no page of its own to open.
          '';
        };

        title = mkOption {
          type = types.str;
          default = name;
          defaultText = literalExpression "the attribute name";
          description = "Name on the button.";
        };

        description = mkOption {
          type = types.str;
          default = "";
          description = "One line under the name, saying what the service does.";
        };

        icon = mkOption {
          type = types.str;
          default = "";
          example = "🚀";
          description = "Emoji on the button. Left out entirely when empty.";
        };

        url = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = ''
            Where the button points. Defaults to the first of `paths` that is
            not `"/"`, falling back to `"/"`.
          '';
        };
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

    directive =
      if elem path svc.stripPrefix
      then "handle_path"
      else "handle";

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
    ${directive}${matcher} {
      ${reverseProxy}
    }
  '';

  vhostKey = concatStringsSep " " (map (h: "http://${h}") cfg.hostNames);

  rootClaimants = filterAttrs (_: svc: elem "/" svc.paths) cfg.services;
  allPaths = flatten (mapAttrsToList (_: svc: svc.paths) cfg.services);

  linkOf = svc: let
    nonRoot = filter (p: p != "/") svc.paths;
  in
    if svc.landing.url != null
    then svc.landing.url
    else if nonRoot == []
    then "/"
    else head nonRoot;

  landingEntries =
    mapAttrsToList (_: svc: {
      inherit (svc.landing) title description icon;
      url = linkOf svc;
    }) (filterAttrs (_: svc: svc.landing.advertise) cfg.services)
    ++ map (link: {inherit (link) title description icon url;}) cfg.landingPage.extraLinks;

  selfLinked = filter (entry: entry.url == "/") landingEntries;

  mkTile = entry:
    concatStringsSep "\n" (
      [''<a class="svc" href="${escapeXML entry.url}">'']
      ++ optional (entry.icon != "") ''<span class="svc-icon" aria-hidden="true">${escapeXML entry.icon}</span>''
      ++ [''<span class="svc-name">${escapeXML entry.title}</span>'']
      ++ optional (entry.description != "") ''<span class="svc-desc">${escapeXML entry.description}</span>''
      ++ [
        ''<span class="svc-addr">${escapeXML entry.url}</span>''
        ''</a>''
      ]
    );

  # A whole static site would be one file either way, so it is generated here
  # rather than kept alongside as HTML: the buttons have to agree with the
  # `services` attrset above, and the only way to guarantee that is to build
  # them from it.
  landingHtml = ''
    <!DOCTYPE html>
    <html lang="en">
    <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <meta name="color-scheme" content="light dark">
    <title>${escapeXML cfg.landingPage.title}</title>
    <link rel="icon" href="data:image/svg+xml,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 16 16'><circle cx='8' cy='8' r='6' fill='%23161e1a'/></svg>">
    <style>
    :root {
      --paper: #d7dad0;
      --face: #c7cbbf;
      --face-lit: #bcc1b3;
      --ink: #161e1a;
      --edge: #161e1a;
      --muted: #4a544d;
      --mono: ui-monospace, "SFMono-Regular", "JetBrains Mono", "DejaVu Sans Mono", monospace;
    }
    @media (prefers-color-scheme: dark) {
      :root {
        --paper: #0f1513;
        --face: #1c2420;
        --face-lit: #242d28;
        --ink: #d7dad0;
        --edge: #39443f;
        --muted: #8d968f;
      }
    }
    * { box-sizing: border-box; }
    body {
      margin: 0;
      padding: clamp(1.5rem, 5vw, 3.5rem) clamp(1rem, 5vw, 3.5rem) 4rem;
      background: var(--paper);
      color: var(--ink);
      font-family: system-ui, -apple-system, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif;
      font-size: 17px;
      line-height: 1.45;
      -webkit-text-size-adjust: 100%;
    }
    main { max-width: 62rem; margin: 0 auto; }
    h1 {
      margin: 0;
      font-size: clamp(2.75rem, 14vw, 6rem);
      font-weight: 800;
      letter-spacing: -0.045em;
      line-height: 0.9;
      text-transform: lowercase;
    }
    h1 + div {
      height: 3px;
      background: var(--ink);
      margin: 0.55rem 0 0.85rem;
    }
    .hosts {
      margin: 0 0 clamp(2rem, 6vw, 3rem);
      color: var(--muted);
      font-family: var(--mono);
      font-size: 0.78rem;
      line-height: 1.6;
      overflow-wrap: anywhere;
    }
    .grid {
      display: grid;
      gap: clamp(0.75rem, 2.5vw, 1.1rem);
      grid-template-columns: repeat(auto-fit, minmax(13.5rem, 1fr));
    }
    .svc {
      display: flex;
      flex-direction: column;
      gap: 0.3rem;
      min-height: 8.5rem;
      padding: 1rem 1.1rem;
      border: 2px solid var(--edge);
      border-radius: 4px;
      background: var(--face);
      color: inherit;
      text-decoration: none;
    }
    .svc:hover, .svc:focus-visible { background: var(--face-lit); }
    .svc:focus-visible { outline: 3px solid var(--ink); outline-offset: 3px; }
    .svc-icon { font-size: 1.5rem; line-height: 1; }
    .svc-name { font-size: 1.3rem; font-weight: 700; letter-spacing: -0.02em; }
    .svc-desc { color: var(--muted); font-size: 0.9rem; }
    .svc-addr {
      margin-top: auto;
      padding-top: 0.75rem;
      color: var(--muted);
      font-family: var(--mono);
      font-size: 0.78rem;
      overflow-wrap: anywhere;
    }
    .empty { color: var(--muted); }
    </style>
    </head>
    <body>
    <main>
      <h1>${escapeXML cfg.landingPage.title}</h1>
      <div></div>
      <p class="hosts">Answers to ${escapeXML (concatStringsSep ", " cfg.hostNames)}</p>
    ${
      if landingEntries == []
      then ''<p class="empty">No services are advertised yet. Add one under <code>services.localProxy.services</code>.</p>''
      else ''
          <div class="grid">
        ${concatStringsSep "\n" (map mkTile landingEntries)}
          </div>''
    }
    </main>
    </body>
    </html>
  '';

  landingRoot = pkgs.writeTextFile {
    name = "local-proxy-landing";
    destination = "/index.html";
    text = landingHtml;
  };

  # `handle /` and not `handle /*`: Caddy path matchers are exact unless they
  # end in `*`, so this claims the bare root and nothing else. The root
  # claimant's matcher-less `handle` still serves every other path, which is
  # what keeps an app like houston working underneath its own launcher button.
  landingHandle = ''
    handle / {
      root * ${landingRoot}
      file_server
    }
  '';
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

    landingPage = {
      enable = mkEnableOption ''
        a generated index at the bare root path, with a button per advertised
        service. It claims `/` exactly, so a service holding the root catch-all
        keeps serving every other path
      '';

      title = mkOption {
        type = types.str;
        default = config.hostname;
        defaultText = literalExpression "config.hostname";
        description = "Wordmark at the top of the page.";
      };

      extraLinks = mkOption {
        type = types.listOf (types.submodule {
          options = {
            title = mkOption {
              type = types.str;
              description = "Name on the button.";
            };

            url = mkOption {
              type = types.str;
              example = "http://halo:8096";
              description = "Where the button points.";
            };

            description = mkOption {
              type = types.str;
              default = "";
              description = "One line under the name, saying what the service does.";
            };

            icon = mkOption {
              type = types.str;
              default = "";
              example = "🎬";
              description = "Emoji on the button. Left out entirely when empty.";
            };
          };
        });
        default = [];
        description = ''
          Buttons for services this proxy does not front — anything answering on
          its own port, or living on another host.
        '';
      };
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
      {
        assertion = all (svc: subtractLists svc.paths svc.stripPrefix == []) (attrValues cfg.services);
        message = "services.localProxy: every stripPrefix entry must also appear in that service's paths.";
      }
      {
        # `handle_path` needs a matcher ending in `*`, which a root claim has none of.
        assertion = all (svc: !(elem "/" svc.stripPrefix)) (attrValues cfg.services);
        message = "services.localProxy: \"/\" cannot be stripped — it is the matcher-less catch-all.";
      }
      {
        assertion = !cfg.landingPage.enable || selfLinked == [];
        message = "services.localProxy: the landing page owns \"/\", so these buttons would point back at it: ${concatStringsSep ", " (map (entry: entry.title) selfLinked)}. Give each a non-root path, or set `landing.url`.";
      }
    ];

    services.caddy = {
      enable = true;

      virtualHosts.${vhostKey} = {
        # The vhost key above is space-separated http:// addresses; nixpkgs'
        # default log filename derives from that key, which would mangle into
        # an ~89-char name.
        logFormat = "output file ${config.services.caddy.logDir}/access-local-proxy.log";
        extraConfig = concatStringsSep "\n" (
          optional cfg.landingPage.enable landingHandle
          ++ flatten (mapAttrsToList (_: svc: map (mkHandle svc) svc.paths) cfg.services)
        );
      };
    };

    # Deliberately not networking.firewall.allowedTCPPorts: that opens every
    # interface, including whatever untrusted network a host roams onto.
    networking.firewall.interfaces = genAttrs cfg.lanInterfaces (_: {
      allowedTCPPorts = [80];
    });
  };
}
