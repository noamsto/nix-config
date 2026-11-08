#!/usr/bin/env bash
# Bump pi-bolt to the newest signed bolt-v release.
#
# The key in allowed_signers, committed beside this script and never taken from
# a release, verifies SHA256SUMS. Its signed "# pi-bolt <version>" line must
# equal the tag, so a validly signed file from another release is refused.
#
# Usage: bump.sh | bump.sh --release-dir DIR --tag TAG
set -euo pipefail

repo=opensec-git/Pi-Bolt
targets="linux-x64 linux-arm64 darwin-arm64"
script_dir=$(dirname "$(readlink -f "$0")")
nix_file=$script_dir/default.nix

tmp=""
nix_tmp=""
cleanup() {
  if [ -n "$tmp" ]; then rm -rf "$tmp"; fi
  if [ -n "$nix_tmp" ]; then rm -f "$nix_tmp"; fi
}
trap cleanup EXIT

die() {
  echo "bump.sh: $*" >&2
  exit 1
}

usage() {
  echo "usage: bump.sh [--release-dir DIR --tag TAG]" >&2
  exit 2
}

report() {
  local line
  for line in "$@"; do
    echo "$line"
    if [ -n "${GITHUB_OUTPUT:-}" ]; then echo "$line" >>"$GITHUB_OUTPUT"; fi
  done
}

release_dir=""
tag=""
while [ $# -gt 0 ]; do
  case "$1" in
  --release-dir | --tag)
    [ $# -ge 2 ] && [ -n "$2" ] || usage
    if [ "$1" = --tag ]; then tag=$2; else release_dir=$2; fi
    shift 2
    ;;
  *) usage ;;
  esac
done
if [ -n "$release_dir" ] && [ -z "$tag" ]; then usage; fi
if [ -z "$release_dir" ] && [ -n "$tag" ]; then usage; fi

if [ -n "$tag" ]; then
  [[ $tag =~ ^bolt-v[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "invalid tag: $tag"
else
  tags=$(gh api --paginate "repos/$repo/releases?per_page=100" \
    --jq '.[] | select((.draft or .prerelease) | not) | .tag_name') ||
    die "cannot list releases"
  tag=$(printf '%s\n' "$tags" | grep -xE 'bolt-v[0-9]+\.[0-9]+\.[0-9]+' | sort -V | tail -n1) || true
  [ -n "$tag" ] || die "no bolt-v release found"
fi
new=${tag#bolt-v}

version_re='^  version = "[0-9]+\.[0-9]+\.[0-9]+";$'
version_lines=$(grep -E "$version_re" "$nix_file") || die "no version line in $nix_file"
[ "$(printf '%s\n' "$version_lines" | wc -l)" -eq 1 ] || die "expected exactly one version line in $nix_file"
old=${version_lines#*\"}
old=${old%\"*}

newest=$(printf '%s\n%s\n' "$old" "$new" | sort -V | tail -n1)
if [ "$new" = "$old" ] || [ "$newest" != "$new" ]; then
  echo "pi-bolt $old is packaged; $tag is not newer"
  report changed=false
  exit 0
fi

tmp=$(mktemp -d)
if [ -n "$release_dir" ]; then
  cp "$release_dir/SHA256SUMS" "$release_dir/SHA256SUMS.sshsig" "$tmp/" ||
    die "cannot copy SHA256SUMS and SHA256SUMS.sshsig from $release_dir"
else
  gh release download "$tag" -R "$repo" -p SHA256SUMS -p SHA256SUMS.sshsig -D "$tmp" ||
    die "cannot download release files for $tag"
fi
sums=$tmp/SHA256SUMS

ssh-keygen -Y verify -f "$script_dir/allowed_signers" -I pi-bolt -n pi-bolt-release \
  -s "$tmp/SHA256SUMS.sshsig" <"$sums" >&2 ||
  die "signature verification failed for $tag"

version_count=$(awk 'index($0, "# pi-bolt ") == 1 { c++ } END { print c + 0 }' "$sums")
[ "$version_count" -eq 1 ] || die "expected exactly one '# pi-bolt ' line, found $version_count"
signed_line=$(awk 'index($0, "# pi-bolt ") == 1' "$sums")
[ "$signed_line" = "# pi-bolt $new" ] ||
  die "signed version line '$signed_line' does not match tag $tag"

pairs=""
for target in $targets; do
  name=pi-bolt-$target.tar.xz
  count=$(awk -v name="$name" '$2 == name { c++ } END { print c + 0 }' "$sums")
  [ "$count" -eq 1 ] || die "expected exactly one line for $name, found $count"
  read -r fields hex < <(awk -v name="$name" '$2 == name { print NF, $1 }' "$sums")
  [ "$fields" -eq 2 ] && [[ $hex =~ ^[0-9a-f]{64}$ ]] || die "malformed entry for $name"
  sri=$(nix --extra-experimental-features nix-command hash convert \
    --hash-algo sha256 --to sri "$hex") || die "cannot convert hash for $name"
  [[ $sri == sha256-* ]] || die "unexpected hash conversion for $name: $sri"
  pairs="$pairs $target $sri"
done

nix_tmp=$(mktemp "$nix_file.XXXXXX")
awk -v old="$old" -v new="$new" -v pairs="$pairs" '
	BEGIN {
		n = split(pairs, a, " ")
		for (i = 1; i <= n; i += 2) sri[a[i]] = a[i + 1]
	}
	$0 == "  version = \"" old "\";" { print "  version = \"" new "\";"; versions++; next }
	{
		line = $0
		sub(/^[ \t]+/, "", line)
		for (t in sri) {
			if (line == "target = \"" t "\";") { pending = t }
		}
		if (pending != "" && line ~ /^hash = "/) {
			match($0, /^[ \t]*/)
			print substr($0, 1, RLENGTH) "hash = \"" sri[pending] "\";"
			done[pending]++
			pending = ""
			next
		}
		print
	}
	END {
		if (versions != 1) exit 1
		for (t in sri) if (done[t] != 1) exit 1
	}
' "$nix_file" >"$nix_tmp" || die "could not update every field in $nix_file"

chmod 644 "$nix_tmp"
mv "$nix_tmp" "$nix_file"
nix_tmp=""

report changed=true "old=$old" "new=$new" "tag=$tag"
