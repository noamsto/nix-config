# Checks for the hyprmoncfg integration: the post-apply hook against a stub
# hyprctl, and the generated profile directory against hyprmoncfg's validator.
{pkgs}: let
  inherit (pkgs) lib;
  postApply = import ./services/hyprmoncfg/post-apply.nix {inherit pkgs;};
  mkProfiles = profiles: import ./services/hyprmoncfg/profiles.nix {inherit pkgs lib profiles;};
  laptop = import ./services/hyprmoncfg/laptop-profile.nix {
    inherit lib;
    internal = {
      make = "BOE";
      model = "NE140QDM-NX1";
      serial = "";
    };
    scale = 1.25;
  };
in {
  post-apply =
    pkgs.runCommand "hyprmoncfg-post-apply-check" {
      nativeBuildInputs = with pkgs; [
        bats
        bash
        coreutils
        gnugrep
      ];
    } ''
      export POST_APPLY=${postApply}/bin/hyprmoncfg-post-apply
      bats --tap ${./tests/hyprmoncfg-post-apply.bats}
      touch $out
    '';

  profiles-valid = mkProfiles {
    laptop =
      laptop
      // {
        name = "laptop";
        exec = "/bin/true";
      };
  };

  profiles-invalid = let
    failed = pkgs.testers.testBuildFailure (mkProfiles {
      bad = {
        name = "bad";
        outputs = [];
      };
    });
  in
    pkgs.runCommand "hyprmoncfg-profiles-invalid-check" {nativeBuildInputs = [pkgs.gnugrep];} ''
      grep -F 'profile has no outputs' ${failed}/testBuildFailure.log
      touch $out
    '';
}
