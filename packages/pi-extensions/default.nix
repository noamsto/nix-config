# pi coding-agent extensions, loaded by store path: `pi -e <drv>/lib/node_modules/<npm name>`.
#
# The registry tarballs ship no lockfile, so each dir holds one generated with
# `npm install --package-lock-only --ignore-scripts --legacy-peer-deps` against
# the package.json as rewritten by `packageJsonFilter`. pi bundles its core
# packages (pi-ai, pi-agent-core, pi-coding-agent, pi-tui, typebox) and loads
# each extension with its own module root, so peers stay out of node_modules —
# the same `--legacy-peer-deps` install `pi install` does.
{
  lib,
  stdenv,
  buildNpmPackage,
  fetchurl,
  jq,
  autoPatchelfHook,
}: let
  mkPiExtension = {
    pname,
    npmName,
    version,
    hash,
    packageJsonFilter ? null,
    ...
  } @ args:
    buildNpmPackage ({
        src = fetchurl {
          url = "https://registry.npmjs.org/${npmName}/-/${lib.last (lib.splitString "/" npmName)}-${version}.tgz";
          inherit hash;
        };

        postPatch =
          ''
            cp ${./${pname}/package-lock.json} package-lock.json
          ''
          + lib.optionalString (packageJsonFilter != null) ''
            ${lib.getExe jq} '${packageJsonFilter}' package.json > package.json.new
            mv package.json.new package.json
          '';

        npmFlags = ["--legacy-peer-deps"];
        # Upstream lifecycle scripts fetch grammars, install git hooks, or strip
        # files that are not in the tarball; none may run in the sandbox.
        npmRebuildFlags = ["--ignore-scripts"];
        npmPackFlags = ["--ignore-scripts"];
        dontNpmBuild = true;

        meta = {
          homepage = "https://www.npmjs.com/package/${npmName}";
          license = lib.licenses.mit;
          platforms = lib.platforms.linux;
        };
      }
      // removeAttrs args ["npmName" "hash" "packageJsonFilter"]);
in {
  pi-lens = mkPiExtension {
    pname = "pi-lens";
    npmName = "pi-lens";
    version = "4.1.6";
    hash = "sha256-ELmU9bGDkXJY7PbziJXkPyWbZJLNWWZNU2600xAzAMA=";
    npmDepsHash = "sha256-I8aukh3x21XuJlanRgOkJqfSxGwfRo3MfYB9qkdPVUw=";

    # @ast-grep/napi and @ast-grep/cli-linux-x64-gnu ship prebuilt glibc
    # binaries; pi-lens's tool resolver takes the CLI from its own
    # node_modules before falling back to PATH or a managed download.
    nativeBuildInputs = [autoPatchelfHook];
    buildInputs = [stdenv.cc.cc.lib];
  };

  pi-web-access = mkPiExtension {
    pname = "pi-web-access";
    npmName = "pi-web-access";
    version = "0.29.0";
    hash = "sha256-yooPtDglWlqp/x1URIajH+axAOMOAggc/KvaoqFjXQk=";
    npmDepsHash = "sha256-nJ9tB1qLwgUq2rZurXcjIzOz4B1SDlUH8fELLTAPe04=";
    packageJsonFilter = "del(.devDependencies)";
  };

  rpiv-todo = mkPiExtension {
    pname = "rpiv-todo";
    npmName = "@juicesharp/rpiv-todo";
    version = "2.10.1";
    hash = "sha256-a1tVGhYwgRZFab8V6Za7/oanrCeeyWJgEsL3P06Yn04=";
    npmDepsHash = "sha256-iL7/b931OjB7v7SPI5B1E14JY23GQ9mJRj4im6vavEw=";
    # rpiv-i18n is an optional peer, but pi does not bundle it.
    packageJsonFilter = ''.dependencies["@juicesharp/rpiv-i18n"] = "2.10.1"'';
  };
}
