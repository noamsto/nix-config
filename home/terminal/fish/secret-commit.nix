# The secret-commit fish function body, shared by the Home Manager module that
# installs it (default.nix) and the regression check that exercises it
# (secret-commit-check.nix). It reads sops YAML files as text — key names are
# plaintext — and never decrypts anything.
{pkgs}: ''
  function secret-commit --description 'Commit changed sops secret files with deterministic conventional-commit messages'
      argparse 'n/dry-run' -- $argv
      or return 1

      set -l jq ${pkgs.jq}/bin/jq
      set -l yq ${pkgs.yq}/bin/yq

      set -l root (command git rev-parse --show-toplevel 2>/dev/null)
      if test -z "$root"
          echo 'secret-commit: not inside a git repository' >&2
          return 1
      end

      # Changed sops files: tracked changes against HEAD (staged or unstaged,
      # including new and deleted files) plus untracked files. Each file is
      # diffed and committed on its own, so one secret never sweeps in another.
      set -l candidates
      for path in (command git -C "$root" diff HEAD --name-only -- secrets 2>/dev/null) \
                  (command git -C "$root" ls-files --others --exclude-standard -- secrets 2>/dev/null)
          if string match -rq '^secrets/[^/]+\.yaml$' -- "$path"
              set -a candidates $path
          end
      end

      # Whether the repo has any sops secret at all decides the error message
      # for an empty commit set; a changed file is itself proof.
      set -l found 0
      if test (count $candidates) -gt 0
          set found 1
      else if command git -C "$root" ls-files --cached --others --exclude-standard -- secrets 2>/dev/null | string match -rq '^secrets/[^/]+\.yaml$'
          set found 1
      end

      set -l commit_paths
      set -l commit_subjects
      set -l commit_bodies

      for path in (printf '%s\n' $candidates | sort -u)
          if test -z "$path"
              continue
          end
          set -l stem (string replace -r '\.yaml$' "" (path basename -- $path))

          # Old document from HEAD; a missing blob (new file or unborn HEAD) is
          # an empty document, so every key reads as added. A present blob that
          # yq cannot parse is an error, never a silent empty diff.
          set -l old_yaml (command git -C "$root" show "HEAD:$path" 2>/dev/null | string collect)
          set -l old_json '{}'
          if test -n "$old_yaml"
              set old_json (printf '%s' "$old_yaml" | $yq '.' 2>/dev/null | string collect)
              if test -z "$old_json"
                  echo "secret-commit: cannot parse the HEAD version of $path" >&2
                  return 1
              end
          end

          # New document from the worktree; a missing file (deleted) is empty,
          # so every key reads as removed. A present file that yq cannot parse
          # is an error, never a silent empty diff.
          set -l new_json '{}'
          if test -f "$root/$path"
              set new_json (command cat "$root/$path" | $yq '.' 2>/dev/null | string collect)
              if test -z "$new_json"
                  echo "secret-commit: cannot parse $path" >&2
                  return 1
              end
          end

          # --slurpfile needs a readable path, so the synthesized new document
          # goes to a temp file rather than a process substitution.
          set -l new_file (command mktemp)
          printf '%s' "$new_json" > "$new_file"
          set -l result (printf '%s' "$old_json" | $jq -c -f ${./secret-commit.jq} --arg stem "$stem" --slurpfile new "$new_file")
          command rm -f "$new_file"

          if test -z "$result"
              echo "secret-commit: failed to compute the $path diff" >&2
              return 1
          end
          if test (printf '%s' "$result" | $jq -r '.changed') != true
              continue
          end

          set -a commit_paths $path
          set -a commit_subjects (printf '%s' "$result" | $jq -r '.subject' | string collect)
          set -a commit_bodies (printf '%s' "$result" | $jq -r '.body' | string collect)
      end

      if test (count $commit_paths) -eq 0
          if test $found -eq 0
              echo 'secret-commit: no sops secret files found' >&2
          else
              echo 'secret-commit: sops secret files have no changes' >&2
          end
          return 1
      end

      for i in (seq (count $commit_paths))
          if set -q _flag_n
              printf '%s\n\n%s\n' "$commit_subjects[$i]" "$commit_bodies[$i]"
          else
              # Stage the path so an untracked new file or an unstaged deletion
              # is recorded, then `-- <path>` commits that path alone, leaving
              # any other staged work untouched.
              command git -C "$root" add -A -- "$commit_paths[$i]"
              command git -C "$root" commit -m "$commit_subjects[$i]" -m "$commit_bodies[$i]" -- "$commit_paths[$i]"
          end
      end
  end
''
