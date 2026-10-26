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
    mkMerge
    types
    literalExpression
    genAttrs
    concatStringsSep
    optional
    optionals
    optionalString
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
    intersectLists
    hasInfix
    hasPrefix
    hasSuffix
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

      upstreamHost = mkOption {
        type = types.nullOr types.str;
        default = null;
        example = "localhost:7757";
        description = ''
          Rewrite the `Host` header sent upstream (`header_up Host <value>`).
          Null keeps Caddy's default of forwarding the client's Host. Needed by
          an upstream that rejects any Host but its own loopback address, as a
          DNS-rebinding guard.
        '';
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
  # Host header is NOT rewritten by default (Caddy's default: preserved).
  # houston's own Host allowlist is what gates access, and it 403s any request
  # whose Origin disagrees with Host, so a proxy that rewrote Host would break it.
  # `upstreamHost` opts a single service into a rewrite.
  mkHandle = svc: path: let
    # Prefix glob (path* not path/*), so a bare /v1 is proxied along with
    # /v1/...; another host's reverse proxy hit this with /radarr vs /radarr/.
    matcher =
      if path == "/"
      then ""
      else " ${path}*";

    directive =
      if elem path svc.stripPrefix
      then "handle_path"
      else "handle";

    proxyLines =
      optional (svc.upstreamHost != null) "header_up Host ${svc.upstreamHost}"
      ++ optional svc.streaming "flush_interval -1"
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

    # `handle_path` strips the prefix but does not add the trailing slash back,
    # so an app that resolves its assets relatively asks for them one directory
    # up when the URL lacks it. Send the bare path to the slash form.
    slashRedirect =
      optional (elem path svc.stripPrefix && !(hasSuffix "/" path))
      "redir ${path} ${path}/ 308";
  in ''
    ${concatStringsSep "\n" slashRedirect}
    ${directive}${matcher} {
      ${reverseProxy}
    }
  '';

  # Both schemes in one site block on purpose: Caddy splits `https://`
  # addresses onto :443 and the rest onto :80 by itself, and because an
  # `https://` address is present it also adds the HTTP->HTTPS redirect for
  # those names. Two blocks would mean two of everything (log writer, landing
  # handle, every service handle) for no gain.
  vhostKey = concatStringsSep " " (
    map (h: "http://${h}") cfg.hostNames
    ++ map (h: "https://${h}") cfg.httpsHostNames
  );

  # Every address the vhost answers to, in either scheme. The landing page names
  # it, and "is this vhost addressed at all" is a question about the union — an
  # https-only vhost is a valid site.
  siteNames = cfg.hostNames ++ cfg.httpsHostNames;
  landingNames = siteNames ++ optional cfg.tailscale.enable cfg.tailscale.fqdn;

  # Pseudo-version of commit de41b249af4fd2083612c3b2303197e92787d1c5; the repo
  # has no tags.
  caddyTailscale = "github.com/tailscale/caddy-tailscale@v0.0.0-20260826180304-de41b249af4f";
  credentialPath = "/run/credentials/caddy.service/ts-authkey";

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
      <p class="hosts">Answers to ${escapeXML (concatStringsSep ", " landingNames)}</p>
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

  siteBody = concatStringsSep "\n" (
    optional cfg.landingPage.enable landingHandle
    ++ flatten (mapAttrsToList (_: svc: map (mkHandle svc) svc.paths) cfg.services)
  );
in {
  options.services.localProxy = {
    enable = mkEnableOption "Caddy reverse proxy for local services, addressed by path prefix";

    hostNames = mkOption {
      type = types.listOf types.str;
      default = [config.hostname "localhost"];
      description = "Names/addresses the vhost answers to (without the `http://` prefix, which the module adds).";
    };

    httpsHostNames = mkOption {
      type = types.listOf types.str;
      default = [];
      example = ["host.tailnet.ts.net"];
      description = ''
        Names/addresses the vhost also answers to over HTTPS, without the
        `https://` prefix (the module adds it). Caddy obtains each name's
        certificate itself — from the local Tailscale daemon for a `*.ts.net`
        name, which additionally needs `services.tailscale.permitCertUid` set
        to Caddy's user, or from a public CA otherwise.

        Plain-HTTP requests for these names are redirected to HTTPS, so a name
        must not also appear in `hostNames`.
      '';
    };

    listenAddresses = mkOption {
      type = types.listOf types.str;
      default = [];
      example = ["127.0.0.1" "::1"];
      description = ''
        Addresses the vhost binds to (Caddy's `bind`). Empty keeps Caddy's
        default of every interface.
      '';
    };

    lanInterfaces = mkOption {
      type = types.listOf types.str;
      default = [];
      example = ["enp97s0"];
      description = ''
        Interfaces to open TCP 80 on, and TCP 443 as well when
        `httpsHostNames` is set. Unless `listenAddresses` keeps Caddy off it,
        every registered service becomes reachable, unauthenticated, to
        whatever network segment the named interface is on — empty means
        tailnet-only reach, since `tailscale0` is already trusted.
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

    tailscale = {
      enable = mkEnableOption ''
        serving the vhost's routes over HTTPS on a dedicated Tailscale node that
        Caddy runs itself (the `tailscale/caddy-tailscale` plugin, userspace
        tsnet), separate from the host's tailscaled and restricted to
        `allowedLogins`
      '';

      nodeName = mkOption {
        type = types.str;
        example = "tp-g6-agents";
        description = "Node config name in Caddy, and the hostname the node requests.";
      };

      tailnetDomain = mkOption {
        type = types.str;
        example = "tail1234.ts.net";
        description = "The tailnet's MagicDNS domain.";
      };

      fqdn = mkOption {
        type = types.str;
        readOnly = true;
        default = "${cfg.tailscale.nodeName}.${cfg.tailscale.tailnetDomain}";
        defaultText = literalExpression ''"''${nodeName}.''${tailnetDomain}"'';
        description = ''
          The node's site address. Tailscale suffixes a name already taken on
          the tailnet (e.g. `-1`), so pick an unused `nodeName`.
        '';
      };

      authKeyFile = mkOption {
        type = types.nullOr types.externalPath;
        default = null;
        description = ''
          Auth key that registers the node on first start. Handed to Caddy with
          systemd `LoadCredential`, so the file can stay root-only. Null makes
          the node log a login URL to Caddy's journal instead. Only needed
          until the node's state exists in `stateDir`.
        '';
      };

      allowedLogins = mkOption {
        type = types.listOf types.str;
        default = [];
        example = ["alice@example.com"];
        description = ''
          Tailscale login names allowed in. Anyone else on the tailnet gets 403;
          tagged devices and non-tailnet clients get 401.
        '';
      };

      stateDir = mkOption {
        type = types.str;
        default = "${config.services.caddy.dataDir}/tailscale";
        defaultText = literalExpression ''"''${config.services.caddy.dataDir}/tailscale"'';
        description = "tsnet state; the node keeps its identity in `<stateDir>/<nodeName>`.";
      };
    };
  };

  config = mkIf cfg.enable (mkMerge [
    {
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
          # rather than an eval or runtime error. Applies to both lists — either
          # alone can address the vhost — and to `https://` as well as `http://`:
          # which scheme the module adds depends on the list.
          assertion =
            siteNames
            != []
            && !(any (h: hasInfix " " h || hasPrefix "http://" h || hasPrefix "https://" h) siteNames);
          message = "services.localProxy: hostNames and httpsHostNames must not both be empty, and no name in either may contain a space or a scheme prefix (the module adds `http://` or `https://`).";
        }
        {
          # A name in both lists is served on :80 and :443, so Caddy adds no
          # redirect for it — almost certainly not what was meant.
          assertion = intersectLists cfg.hostNames cfg.httpsHostNames == [];
          message = "services.localProxy: a name cannot be both http and https — Caddy already redirects `httpsHostNames` to HTTPS.";
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
          inherit (cfg) listenAddresses;
          extraConfig = siteBody;
        };
      };

      # Deliberately not networking.firewall.allowedTCPPorts: that opens every
      # interface, including whatever untrusted network a host roams onto.
      networking.firewall.interfaces = genAttrs cfg.lanInterfaces (_: {
        allowedTCPPorts = [80] ++ optional (cfg.httpsHostNames != []) 443;
      });
    }

    (mkIf cfg.tailscale.enable {
      assertions = [
        {
          assertion = cfg.tailscale.allowedLogins != [];
          message = "services.localProxy.tailscale: allowedLogins is empty, so every request would be refused.";
        }
        {
          assertion = cfg.tailscale.nodeName != "";
          message = "services.localProxy.tailscale: nodeName must not be empty.";
        }
        {
          assertion = cfg.tailscale.tailnetDomain != "";
          message = "services.localProxy.tailscale: tailnetDomain must not be empty.";
        }
      ];

      services.caddy = {
        package = pkgs.caddy.withPlugins {
          plugins = [caddyTailscale];
          hash = "sha256-OzzyBF/SA1WkX/g+WOwvZo2t5bfeNPOeYJ1ziOLlTTk=";
        };

        # h1/h2 only: the plugin's HTTP/3 listener calls tsnet `Up`, which blocks
        # until the node is logged in, so with h3 `caddy reload` (the switch
        # path) and shutdown hang while offline or before the auth key exists.
        #
        # The node reports its login URL at INFO, below nixpkgs' default ERROR
        # level, hence its own log.
        globalConfig = ''
          servers tailscale/${cfg.tailscale.nodeName}:443 {
            protocols h1 h2
          }
          log tsnet {
            include tailscale
            level INFO
          }
          tailscale {
            state_dir ${cfg.tailscale.stateDir}
            ${cfg.tailscale.nodeName} {
              ${optionalString (cfg.tailscale.authKeyFile != null) "auth_key {file.${credentialPath}}"}
            }
          }
        '';

        virtualHosts."https://${cfg.tailscale.fqdn}" = {
          listenAddresses = ["tailscale/${cfg.tailscale.nodeName}"];
          logFormat = "output file ${config.services.caddy.logDir}/access-local-proxy-tailscale.log";
          # `tailscale_auth` admits any tailnet user; the `vars` match on
          # `{http.auth.user.id}` (the login name) narrows it to the allowlist.
          # `respond` sorts after `handle`, and the root claimant's matcher-less
          # `handle` would always win, so the check runs inside a `route` (which
          # keeps written order) wrapping a `handle` (sorted as usual).
          extraConfig = ''
            route {
              tailscale_auth
              @denied not vars {http.auth.user.id} ${concatStringsSep " " cfg.tailscale.allowedLogins}
              respond @denied "Forbidden" 403
              handle {
                ${siteBody}
              }
            }
          '';
        };
      };

      systemd.services.caddy.serviceConfig.LoadCredential =
        mkIf (cfg.tailscale.authKeyFile != null)
        ["ts-authkey:${cfg.tailscale.authKeyFile}"];
    })
  ]);
}
