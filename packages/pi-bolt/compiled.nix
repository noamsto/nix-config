{
  lib,
  stdenv,
  writeText,
  pi-bolt,
  extensions,
}: let
  settings = writeText "pi-bolt-compile-settings.json" (builtins.toJSON {inherit extensions;});

  # The compile only runs on x86_64-linux (the only target with compile assets
  # packaged); elsewhere this is plain pi-bolt.
  drv =
    if stdenv.hostPlatform.system == "x86_64-linux"
    then
      pi-bolt.overrideAttrs (old: {
        pname = "pi-bolt-compiled";
        meta =
          old.meta
          // {
            description = "Pi-Bolt with Pi extensions compiled in ahead of time";
          };

        # Facts that are not obvious:
        # - compile writes next to the install it runs from, so it needs a
        #   writable copy (the store original is read-only).
        # - compile ends with an `rm` of its `.compile-*` scratch dir that hits
        #   EACCES in the sandbox, after the build already succeeded; only that
        #   exact error is tolerated, and `Built Pi-Bolt` is still required.
        # - the runtime is autoPatchelf'd first because the compile runs
        #   `pi --help` and the sandbox has no /lib64 loader.
        # - the doctor "compiled in" stand-in match relies on the extension
        #   store paths and mtimes being identical at build and run time.
        postInstall =
          (old.postInstall or "")
          + ''
            export HOME=$TMPDIR/compile-home
            export PI_CODING_AGENT_DIR=$HOME/.pi/agent
            mkdir -p "$PI_CODING_AGENT_DIR"
            cp ${settings} "$PI_CODING_AGENT_DIR/settings.json"

            mkdir "$TMPDIR/runtime"
            tar -xzf ${pi-bolt.compileAssets.runtime} -C "$TMPDIR/runtime" --strip-components=1
            chmod -R u+w "$TMPDIR/runtime"
            autoPatchelf "$TMPDIR/runtime"

            cp -r ${pi-bolt}/libexec/pi-bolt "$TMPDIR/install"
            chmod -R u+w "$TMPDIR/install"

            set +e
            "$TMPDIR/install/pi" compile --kit ${pi-bolt.compileAssets.kit} --runtime "$TMPDIR/runtime/bun" --out "$TMPDIR/compiled" >"$TMPDIR/compile.log" 2>&1
            status=$?
            set -e
            grep -v 'passed over' "$TMPDIR/compile.log" || true
            echo "compile exit status: $status"
            if [ "$status" -ne 0 ]; then
              grep '^error:' "$TMPDIR/compile.log" | tail -n 1 \
                | grep -Eq "^error: pi-bolt compile failed: EACCES: permission denied, rm '.*/\.compile-[^/']+'$" \
                || { echo "pi-bolt compile failed unexpectedly" >&2; exit 1; }
            fi
            grep -q '^Built Pi-Bolt ' "$TMPDIR/compile.log"

            "$TMPDIR/compiled/pi" doctor --offline >"$TMPDIR/doctor.txt"
            sed -n '/^Extensions/,/^Packages/p' "$TMPDIR/doctor.txt"
            for e in ${lib.escapeShellArgs extensions}; do
              grep -F "$e/" "$TMPDIR/doctor.txt" | grep -Eq '^[[:space:]]*compiled in[[:space:]]' \
                || { echo "extension not compiled in: $e" >&2; exit 1; }
            done

            rm -rf "$out/libexec/pi-bolt"
            cp -r "$TMPDIR/compiled" "$out/libexec/pi-bolt"
          '';
      })
    else pi-bolt;
in
  lib.extendDerivation true {compiledExtensions = extensions;} drv
