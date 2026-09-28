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

      set -l result (printf '%s' "$old_json" | $jq -c -f "$filter" --slurpfile new "$lock")
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
