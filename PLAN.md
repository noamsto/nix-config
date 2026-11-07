# Plan: desktop evaluation fixture

Files:
- hosts/example-desktop/default.nix (create): same imports as example + desktop.mode=hyprland, machine.type=laptop, comment that it is eval-only
- flake-modules/nixos-systems.nix (modify): wire `example-desktop`
- CLAUDE.md (modify): one-line fixture mention
- .agents/skills/nix-rebuild/SKILL.md (modify): one-line fixture mention (names fixtures at lines 10, 87)

Steps:
- [ ] Step 1: create hosts/example-desktop/default.nix importing ../example/hardware-configuration.nix, nixosModules default/home/core/nice-looking-console (+ desktop/hyprland/laptop if eval requires beyond what `default` brings; check nixos/default.nix), hostname "example-desktop", dummy priors.personalStore as example, desktop.mode="hyprland", machine.type="laptop". Proof: `git add -A; nix eval --raw .#nixosConfigurations.example-desktop.config.system.build.toplevel.drvPath` prints /nix/store/*.drv (needs base branch with brave fix, which this branch contains).
- [ ] Step 2: wire into flake-modules/nixos-systems.nix as example-desktop. Proof: same eval; `nix eval .#nixosConfigurations --apply builtins.attrNames`.
- [ ] Step 3: confirm it exercises desktop trees: `nix eval .#nixosConfigurations.example-desktop.config.programs.hyprland.enable` is true and home-manager user has wayland.windowManager.hyprland.enable true (if a user exists in the fixture).
- [ ] Step 4: evidence: `git worktree add` a scratch worktree at origin/main in the scratchpad, copy fixture + wiring in, `git add`, eval; expect failure mentioning catppuccin.brave; record command+error line for PR; remove worktree/branch.
- [ ] Step 5: update CLAUDE.md and nix-rebuild skill one line each.
- [ ] Step 6: `nix flake check -L --no-build`; `nix fmt` and `git diff --exit-code`.
Acceptance: map to the 5 task items: step1/2 eval; step4 evidence; step6 check/fmt; secrets: grep diff for no real hostnames.
