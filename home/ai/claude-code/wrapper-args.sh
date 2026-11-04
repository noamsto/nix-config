# shellcheck shell=bash
# Sourced by the claude wrapper. Claude Code keeps only the last --settings, so a
# caller's own --settings would silently drop the nix overlay (status line,
# hookyard guards, permissions). Merge caller layers into it instead: hook
# arrays and permission lists concatenate, so a caller can add but never remove.
# Usage: claude_resolve_args <overlay> <merge-cmd> [args...]
# Sets: settings (path to pass as --settings), args (caller argv minus --settings).
# shellcheck disable=SC2034 # settings and args are read by the sourcing wrapper
claude_resolve_args() {
  local overlay=$1 merge=$2
  shift 2
  local layers=()
  args=()
  while [ $# -gt 0 ]; do
    case $1 in
    --)
      args+=("$@")
      break
      ;;
    --settings)
      [ $# -ge 2 ] || {
        echo "claude: --settings needs a value" >&2
        exit 2
      }
      layers+=("$2")
      shift 2
      ;;
    --settings=*)
      layers+=("${1#--settings=}")
      shift
      ;;
    *)
      args+=("$1")
      shift
      ;;
    esac
  done
  settings=$overlay
  if [ ${#layers[@]} -gt 0 ]; then
    settings=$("$merge" "$overlay" "${layers[@]}") || exit
  fi
}
