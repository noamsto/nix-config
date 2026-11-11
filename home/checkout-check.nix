# Warn at activation when the nix-config checkout is missing: the
# out-of-store links into it would otherwise dangle silently.
{
  lib,
  osConfig,
  ...
}: {
  home.activation.checkNixConfigCheckout = lib.hm.dag.entryAfter ["writeBoundary"] ''
    if [ ! -d ${lib.escapeShellArg osConfig.nix-config.checkoutPath} ]; then
      warnEcho "nix-config checkout not found at "${lib.escapeShellArg osConfig.nix-config.checkoutPath}"; links into it will dangle. Set nix-config.checkoutPath to the real checkout."
    fi
  '';
}
