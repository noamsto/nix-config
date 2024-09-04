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
  version = "2.0.9";

  src = fetchFromGitHub {
    owner = "tak-bro";
    repo = "aicommit2";
    rev = "v${finalAttrs.version}";
    hash = "";
  };

  pnpmDeps = pnpm.fetchDeps {
    inherit (finalAttrs) pname version src;
    hash = "";
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

    runHook postInstall
  '';

  preFixup = ''
    makeWrapper ${lib.getExe nodejs} $out/bin/aicommit2 \
    --chdir "$out/lib/aicommit2" \
    --append-flags "$out/lib/aicommit2/dist/cli.mjs"
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
