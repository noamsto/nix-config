{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  nodejs,
  pnpm,
  makeWrapper,
}:
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "aicommit2";
  version = "2.1.2";

  src = fetchFromGitHub {
    owner = "tak-bro";
    repo = "aicommit2";
    rev = "v${finalAttrs.version}";
    hash = "sha256-O6IqLd1GNQVZ87b2al4Oz8tEtxZUfa+LNQR8bTXga2k=";
  };

  pnpmDeps = pnpm.fetchDeps {
    inherit (finalAttrs) pname version src;
    hash = "sha256-NQQmk3ZYpHUCgqc89BmBEJKbh/c/Lvv+yz+Gqa+in30=";
  };

  nativeBuildInputs = [
    nodejs
    pnpm.configHook
    makeWrapper
  ];
  buildInputs = [nodejs];

  buildPhase = ''
    runHook preBuild

    pnpm build

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p $out/{bin,lib/aicommit2}
    cp -r {dist,node_modules} $out/lib/aicommit2

    ln -s $out/lib/aicommit2/dist/cli.mjs $out/bin/aicommit2
    ln -s $out/lib/aicommit2/dist/cli.mjs $out/bin/aic2

    runHook postInstall
  '';

  meta = {
    description = "Reactive CLI that generates git commit messages with AI";
    homepage = "https://github.com/tak-bro/aicommit2";
    changelog = "https://github.com/tak-bro/aicommit2/blob/${finalAttrs.src.rev}/CHANGELOG.md";
    license = lib.licenses.mit;
    maintainers = with lib.maintainers; [ByteSudoer];
    mainProgram = "aicommit2";
    platforms = lib.platforms.all;
  };
})
