{
  systems = ["x86_64-linux" "aarch64-linux"];

  perSystem = {pkgs, ...}: {
    packages = {
      # Check if atlas-pro supports current architecture
      atlas-pro = pkgs.callPackage ./atlas_pro.nix {inherit pkgs;};
      tavily-mcp = pkgs.callPackage ./tavily-mcp.nix {};
      claude-squad = pkgs.callPackage ./claude-squad {};
    };
  };
}
