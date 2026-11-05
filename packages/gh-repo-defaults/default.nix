{
  writeShellApplication,
  gh,
}:
writeShellApplication {
  name = "gh-repo-defaults";
  runtimeInputs = [gh];
  text = builtins.readFile ./gh-repo-defaults.sh;

  meta = {
    description = "Apply house GitHub repo settings: squash-only merges, delete branch on merge, auto-merge, Actions may open PRs";
    mainProgram = "gh-repo-defaults";
  };
}
