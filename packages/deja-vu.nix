# deja-vu — local, model-free session-history index for coding agents.
#
# Not in nixpkgs. Upstream is a single Go module with no `require` and no
# `go.sum`, so there is nothing to vendor (`vendorHash = null`) and the default
# `buildGoModule` (nixpkgs go 1.26.x) satisfies its `go 1.25` directive.
#
# Self-update is left to upstream's own Nix guard rather than patched out:
# `deja update` resolves `os.Executable()` (via EvalSymlinks) and refuses to
# write when the path is under /nix/store (cmd/deja/update.go,
# packageManagerOwning), which is where both `~/.nix-profile/bin/deja` and
# `/etc/profiles/per-user/<user>/bin/deja` land. `deja update --force` would
# try, and then fail on the read-only store. Do not strip the version: it is
# what `--version` prints and what the guard's message names.
{
  lib,
  buildGoModule,
  fetchFromGitHub,
}: let
  version = "0.21.4";
in
  buildGoModule {
    pname = "deja-vu";
    inherit version;

    src = fetchFromGitHub {
      owner = "vshulcz";
      repo = "deja-vu";
      # v0.21.4 — the newest tag, verified with `git ls-remote --tags`.
      rev = "bb93e229a5e2c2ccd1fe4444479e7ea98d765600";
      hash = "sha256-wCxVvL9iG45EmGqWzHIld1IlB0XODB112ZLDJNIDhQA=";
    };

    vendorHash = null;

    # The session-start digest tells the agent to "call recall_context", a tool
    # only `deja mcp` provides, and no agent here registers it. 0.21.4 has no
    # shell form; newer upstream (#4596) swaps one in only when the hook payload
    # carries `deja_shell`, which hookyard's envelope cannot send. `deja show` is
    # read-only. --replace-fail makes an upstream rewording break the build
    # rather than revert silently.
    postPatch = ''
      substituteInPlace cmd/deja/hook_context.go \
        --replace-fail 'call recall_context with' 'run `deja show` in the shell with'
    '';

    # Only cmd/deja is the binary; the module also holds scripts and tools.
    subPackages = ["cmd/deja"];

    # Upstream's suite is not hermetic under the Nix sandbox: many tests shell
    # out to `git` or write into $HOME, and the check phase fails on them
    # (TestCompactionFreshness*, TestBashCompletionLimitScope, …) while the
    # binary itself builds and runs cleanly. The acceptance gate is the build
    # plus `deja --version`; do not pretend a green suite here.
    doCheck = false;

    # `var version = "dev"` in cmd/deja/main.go. -s -w strip the symbol table
    # and DWARF, matching a release build.
    ldflags = ["-s" "-w" "-X main.version=${version}"];

    meta = {
      description = "Local, model-free session-history index for coding agents";
      homepage = "https://github.com/vshulcz/deja-vu";
      license = lib.licenses.mit;
      mainProgram = "deja";
      platforms = lib.platforms.unix;
    };
  }
