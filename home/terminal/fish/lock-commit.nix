# The lock-commit fish function body, shared by the Home Manager module that
# installs it (default.nix) and the regression check that exercises it
# (check.nix), so the tested artifact differs from the installed one only in
# its watch list.
{
  pkgs,
  lib,
  watchedInputs,
}: ''
  function lock-commit --description 'Commit changed lockfiles with deterministic conventional-commit messages'
      argparse 'n/dry-run' -- $argv
      or return 1

      set -l jq ${pkgs.jq}/bin/jq

      set -l root (command git rev-parse --show-toplevel 2>/dev/null)
      if test -z "$root"
          echo 'lock-commit: not inside a git repository' >&2
          return 1
      end

      # Known lockfiles, each diffed against HEAD on its own and committed as
      # its own change.
      set -l lock_paths flake.lock
      set -l lock_filters ${./lock-commit.jq}

      set -l watched_inputs ${lib.escapeShellArgs (map (w: w.input) watchedInputs)}
      set -l watched_globs ${lib.escapeShellArgs (map (w: w.glob) watchedInputs)}

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
              # A bump of a watched input names the files it added, updated or
              # removed. A blobless fetch of both revs reads trees and commits
              # only, so no file contents are downloaded where the server supports
              # partial clone; if it fails the plain input line remains. Revs and
              # URL come from the lock unvalidated, so they are checked before
              # they can reach git as options.
              set -l watched_objs
              set -l locked_query '(.nodes[.root].inputs[$i]? // null) as $k
                  | (if ($k | type) == "string" then .nodes[$k].locked else {} end)
                  | "\(.type // "")\t\(.url // "")\t\(.rev // "")"'
              set -l w 0
              for input in $watched_inputs
                  set w (math $w + 1)
                  set -l glob $watched_globs[$w]
                  set -l old_ref (printf '%s' "$old_json" | $jq -r --arg i $input $locked_query | string split \t)
                  set -l new_ref ($jq -r --arg i $input $locked_query "$lock" | string split \t)
                  if test "$old_ref[1]" = git -a "$new_ref[1]" = git -a "$old_ref[3]" != "$new_ref[3]"
                      and string match -rq '^[0-9a-f]{40}$' -- "$old_ref[3]"
                      and string match -rq '^[0-9a-f]{40}$' -- "$new_ref[3]"
                      and not string match -q -- '-*' "$new_ref[2]"
                      set -l old_rev $old_ref[3]
                      set -l new_rev $new_ref[3]
                      set -l tmp (command mktemp -d)
                      if command git -C $tmp init -q --bare
                          and GIT_TERMINAL_PROMPT=0 command git -C $tmp fetch -q --filter=blob:none --no-tags --end-of-options $new_ref[2] $old_rev $new_rev
                          set -l files (command git -C $tmp diff --no-renames --name-status --end-of-options $old_rev $new_rev -- $glob)
                          set -l commits (command git -C $tmp log --no-merges --format='%h %s' --end-of-options $old_rev..$new_rev)
                          set -a watched_objs (printf '%s\n' $files | $jq -Rnc --arg input $input --arg glob $glob '
                              ($glob | split("*") | last) as $sfx
                              | [inputs | select(length > 0) | split("\t")
                                 | {status: .[0][0:1],
                                    name: (if ($glob | contains("*")) then (.[1] | rtrimstr($sfx)) else .[1] end)}] as $f
                              | {input: $input,
                                 added: [$f[] | select(.status == "A") | .name],
                                 removed: [$f[] | select(.status == "D") | .name],
                                 updated: [$f[] | select(.status != "A" and .status != "D") | .name],
                                 commits: $ARGS.positional}' --args $commits)
                      else
                          echo "lock-commit: could not fetch $input history; using the plain message" >&2
                      end
                      command rm -rf $tmp
                  end
              end
              set -l watched_json (printf '%s\n' $watched_objs | $jq -sc '.')
              set result (printf '%s' "$old_json" | $jq -c -f "$lock_filters[$i]" --slurpfile new "$lock" --argjson watched "$watched_json")
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
