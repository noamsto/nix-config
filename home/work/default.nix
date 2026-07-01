{
  lib,
  pkgs,
  ...
}: {
  home.packages = with pkgs; [
    slack

    stable.awscli2
    stable.aws-sam-cli
    stable.ssm-session-manager-plugin

    # chromium moved to programs.chromium in home/desktop/default.nix for commandLineArgs
    dbeaver-bin

    argocd # Argo CD CLI (auth/login; argonaut reads its ~/.config/argocd config)
    argonaut # keyboard-first terminal UI for Argo CD

    mkcert
    nss.tools
  ];

  # Trust vite-plugin-mkcert's local CA in NSS (Chromium) and Firefox stores.
  # CA is generated on first `vite` run; this activation is a no-op until then.
  home.activation.mkcertInstall = lib.hm.dag.entryAfter ["writeBoundary"] ''
    export CAROOT="$HOME/.vite-plugin-mkcert"
    export PATH="${pkgs.nss.tools}/bin:$PATH"
    if [ -f "$CAROOT/rootCA.pem" ]; then
      ${pkgs.mkcert}/bin/mkcert -install >/dev/null || true
    fi
  '';
}
