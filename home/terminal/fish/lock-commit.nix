# The lock-commit fish function body, shared by the Home Manager module that
# installs it (default.nix) and the regression check that exercises it
# (check.nix), so the tested artifact is byte-identical to the installed one.
{pkgs}: ''
  function lock-commit --description 'Commit a changed flake.lock with a deterministic conventional-commit message'
      argparse 'n/dry-run' -- $argv
      or return 1

      set -l jq ${pkgs.jq}/bin/jq
      set -l filter ${./lock-commit.jq}

      set -l root (command git rev-parse --show-toplevel 2>/dev/null)
      if test -z "$root"
          echo 'lock-commit: not inside a git repository' >&2
          return 1
      end

      set -l lock "$root/flake.lock"
      if not test -f "$lock"
          echo "lock-commit: no flake.lock at $lock" >&2
          return 1
      end

      # Old lock from HEAD; a missing file (or an unborn HEAD) is an empty lock,
      # so every input reads as added.
      set -l old_json (command git -C "$root" show HEAD:flake.lock 2>/dev/null | string collect)
      if test -z "$old_json"
          set old_json '{}'
      end

      # A bump of the secrets input names the secrets it added, updated or
      # removed. A blobless fetch of both revs reads trees and commits only, so
      # no ciphertext is downloaded; if it fails the plain input line remains.
      set -l secrets_input mysecrets
      set -l secrets null
      set -l locked_query '(.nodes[.root].inputs[$i]? // null) as $k
          | (if ($k | type) == "string" then .nodes[$k].locked else {} end)
          | "\(.type // "")\t\(.url // "")\t\(.rev // "")"'
      set -l old_ref (printf '%s' "$old_json" | $jq -r --arg i $secrets_input $locked_query | string split \t)
      set -l new_ref ($jq -r --arg i $secrets_input $locked_query "$lock" | string split \t)
      if test "$old_ref[1]" = git -a "$new_ref[1]" = git -a -n "$old_ref[3]" -a "$old_ref[3]" != "$new_ref[3]"
          set -l old_rev $old_ref[3]
          set -l new_rev $new_ref[3]
          set -l tmp (command mktemp -d)
          if command git -C $tmp init -q --bare
              and GIT_TERMINAL_PROMPT=0 command git -C $tmp fetch -q --filter=blob:none --no-tags $new_ref[2] $old_rev $new_rev
              set -l files (command git -C $tmp diff --no-renames --name-status $old_rev $new_rev -- '*.age')
              set -l commits (command git -C $tmp log --no-merges --format='%h %s' $old_rev..$new_rev)
              set secrets (printf '%s\n' $files | $jq -Rnc --arg input $secrets_input '
                  [inputs | select(length > 0) | split("\t") | {status: .[0][0:1], name: (.[1] | rtrimstr(".age"))}] as $f
                  | {input: $input,
                     added: [$f[] | select(.status == "A") | .name],
                     removed: [$f[] | select(.status == "D") | .name],
                     updated: [$f[] | select(.status != "A" and .status != "D") | .name],
                     commits: $ARGS.positional}' --args $commits)
          else
              echo "lock-commit: could not fetch $secrets_input history; using the plain message" >&2
          end
          command rm -rf $tmp
      end

      set -l result (printf '%s' "$old_json" | $jq -c -f "$filter" --slurpfile new "$lock" --argjson secrets "$secrets")
      if test -z "$result"
          echo 'lock-commit: failed to compute the lock diff' >&2
          return 1
      end

      if test (printf '%s' "$result" | $jq -r '.changed') != true
          echo 'lock-commit: flake.lock has no changes' >&2
          return 1
      end

      set -l subject (printf '%s' "$result" | $jq -r '.subject' | string collect)
      set -l body (printf '%s' "$result" | $jq -r '.body' | string collect)

      if set -q _flag_n
          printf '%s\n\n%s\n' "$subject" "$body"
          return 0
      end

      # `-- flake.lock` commits that path alone, leaving any other staged work
      # untouched.
      command git -C "$root" commit -m "$subject" -m "$body" -- flake.lock
  end
''
