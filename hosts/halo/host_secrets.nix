{lib, ...}: {
  # secrets/default.nix points non-server hosts at a user key that does not
  # exist at activation time. identityPaths is a list, so a plain assignment
  # would append to that key rather than replace it.
  age.identityPaths = lib.mkForce ["/etc/ssh/ssh_host_ed25519_key"];
}
