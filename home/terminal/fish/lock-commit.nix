# The lock-commit fish function body, shared by the Home Manager module that
# installs it (default.nix) and the regression check that exercises it
# (check.nix), so the tested artifact is byte-identical to the installed one.
{pkgs}: ''
  function lock-commit --description 'Commit changed lockfiles with deterministic conventional-commit messages'
      argparse 'n/dry-run' -- $argv
      or return 1

      set -l jq ${pkgs.jq}/bin/jq

      set -l root (command git rev-parse --show-toplevel 2>/dev/null)
      if test -z "$root"
          echo 'lock-commit: not inside a git repository' >&2
          return 1
      end

      # Known lockfiles: Nix flake inputs and lazy.nvim plugin pins. Each is
      # diffed against HEAD on its own and committed as its own change, so a
      # bump of one never sweeps in the other.
      set -l lock_paths flake.lock home/nvim/lazyVim/lazy-lock.json
      set -l lock_filters ${./lock-commit.jq} ${./lock-commit-nvim.jq}

      set -l found 0
      set -l commit_paths
      set -l commit_subjects
      set -l commit_bodies

      for i in (seq (count $lock_paths))
          set -l lock_path $lock_paths[$i]
          set -l lock "$root/$lock_path"
          if not test -f "$lock"
              continue
          end
          set found 1

          # Old lock from HEAD; a missing file (or an unborn HEAD) is an empty
          # lock, so every entry reads as added.
          set -l old_json (command git -C "$root" show "HEAD:$lock_path" 2>/dev/null | string collect)
          if test -z "$old_json"
              set old_json '{}'
          end

          set -l result
          if test "$lock_path" = flake.lock
              # A bump of the secrets input names the secrets it added, updated
              # or removed. A blobless fetch of both revs reads trees and
              # commits only, so no ciphertext is downloaded; if it fails the
              # plain input line remains.
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
              set result (printf '%s' "$old_json" | $jq -c -f "$lock_filters[$i]" --slurpfile new "$lock" --argjson secrets "$secrets")
          else
              set result (printf '%s' "$old_json" | $jq -c -f "$lock_filters[$i]" --slurpfile new "$lock")
          end

          if test -z "$result"
              echo "lock-commit: failed to compute the $lock_path diff" >&2
              return 1
          end
          if test (printf '%s' "$result" | $jq -r '.changed') != true
              continue
          end

          set -a commit_paths $lock_path
          set -a commit_subjects (printf '%s' "$result" | $jq -r '.subject' | string collect)
          set -a commit_bodies (printf '%s' "$result" | $jq -r '.body' | string collect)
      end

      if test (count $commit_paths) -eq 0
          if test $found -eq 0
              echo 'lock-commit: no lock files found' >&2
          else
              echo 'lock-commit: lock files have no changes' >&2
          end
          return 1
      end

      for i in (seq (count $commit_paths))
          if set -q _flag_n
              printf '%s\n\n%s\n' "$commit_subjects[$i]" "$commit_bodies[$i]"
          else
              # `-- <path>` commits that path alone, leaving any other staged
              # work untouched.
              command git -C "$root" commit -m "$commit_subjects[$i]" -m "$commit_bodies[$i]" -- "$commit_paths[$i]"
          end
      end
  end
''
