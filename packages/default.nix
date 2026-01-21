{inputs, ...}: {
  systems = ["x86_64-linux" "aarch64-linux"];

  perSystem = {
    pkgs,
    system,
    ...
  }: let
    # Import nixpkgs with allowUnfree for unfree packages
    pkgsUnfree = import inputs.nixpkgs {
      inherit system;
      config.allowUnfree = true;
    };
  in {
    packages = {
      # Check if atlas-pro supports current architecture
      atlas-pro = pkgs.callPackage ./atlas_pro.nix {inherit pkgs;};
      tavily-mcp = pkgs.callPackage ./tavily-mcp.nix {};
      claude-squad = pkgs.callPackage ./claude-squad {};
      claude-chill = pkgs.callPackage ./claude-chill {};
    };
  };
}
