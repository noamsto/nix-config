#!/usr/bin/env fish
# Refresh vicinae extension pins:
#   1. Bump the `vicinae-extensions` flake input to upstream HEAD.
#   2. Bump rev/hash in raycast-sources.nix to upstream HEAD of raycast/extensions,
#      using the `names` list already in that file.

set -l script_dir (status dirname)
set -l sources_file "$script_dir/raycast-sources.nix"
set -l flake_dir (git -C "$script_dir" rev-parse --show-toplevel)

if not test -f "$sources_file"
    echo "error: $sources_file not found" >&2
    exit 1
end

echo "==> Updating vicinae-extensions flake input"
nix flake update vicinae-extensions --flake "$flake_dir"

echo "==> Fetching latest raycast/extensions HEAD"
set -l rev (gh api /repos/raycast/extensions/commits/main --jq '.sha')
if test -z "$rev"
    echo "error: could not resolve raycast HEAD" >&2
    exit 1
end
echo "    rev = $rev"

echo "==> Reading sparseCheckout names from $sources_file"
set -l names_nix (nix eval --impure --raw --expr "builtins.toJSON (import $sources_file).names")
set -l names (echo $names_nix | jq -r '.[]')
if test -z "$names"
    echo "error: raycast-sources.nix has an empty or missing `names` list" >&2
    exit 1
end
set -l sparse_exprs
for n in $names
    set -a sparse_exprs "\"extensions/$n\""
end
set -l sparse_list (string join " " $sparse_exprs)

echo "==> Probing hash for sparseCheckout: $names"
set -l probe_expr "let pkgs = import <nixpkgs> {}; in pkgs.fetchFromGitHub { owner = \"raycast\"; repo = \"extensions\"; rev = \"$rev\"; hash = \"\"; sparseCheckout = [ $sparse_list ]; }"
set -l hash (nix build --no-link --impure --expr "$probe_expr" 2>&1 | awk '/got:/ {print $2; exit}')
if test -z "$hash"
    echo "error: failed to learn hash from nix build" >&2
    exit 1
end
echo "    hash = $hash"

echo "==> Rewriting $sources_file"
set -l names_rendered
for n in $names
    set -a names_rendered "\"$n\""
end
set -l names_line (string join " " $names_rendered)

printf '# Managed by `just update-vicinae-extensions`.
# Edit `names` to add/remove raycast extensions, then rerun the command to refresh
# `rev` and `hash`.
{
  names = [%s];
  rev = "%s";
  hash = "%s";
}
' "$names_line" "$rev" "$hash" >"$sources_file"

echo "==> Done. Diff:"
git -C "$flake_dir" --no-pager diff -- "$sources_file" flake.lock
