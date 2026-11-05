#!/usr/bin/env bash
# Suspend/resume repro harness for halo's wlan0 wedge (nix-config #219).
#
# Measurement tool only. It never unmasks suspend, never wires the
# --probe-recovery diagnostic into a resume path, and makes no networking or
# power-management change.
set -euo pipefail

PROG=halo-wlan0-suspend-repro
RTC_WAKEALARM=/sys/class/rtc/rtc0/wakealarm

declare -A SIGNAL_HITS=(
  [xhci]=0 [thunderbolt]=0 [tb_cfg]=0 [mt76]=0 [mt7925]=0
  [amdgpu]=0 [pci_pm_resume]=0 [dpm_run_callback]=0
  ["PM: suspend entry"]=0 ["PM: suspend exit"]=0
)

usage() {
  cat <<'EOF'
Usage:
  halo-wlan0-suspend-repro --check
  halo-wlan0-suspend-repro -s SECONDS [-n COUNT] [-t SECONDS] [-i IFACE]
                            [-o DIR] [-p] [--continue-on-failure]

Runs N suspend/resume cycles and records, per iteration, whether the watched
interface regains an IPv4 address, the unfiltered resume-window kernel log,
and iwd/iwd-resume/NetworkManager journal output. Root required (rtcwake,
modprobe, journalctl --sync). The sleep/suspend systemd targets must already
be unmasked -- this script never unmasks them; run --check for the exact
steps if they are still masked.

  -s, --sleep-seconds N     suspend duration per iteration (required for a
                             real run; not needed for --check)
  -n, --iterations N        number of cycles (default: 1)
  -t, --ip-timeout N        seconds to wait post-resume for an IPv4 address
                             on IFACE before declaring the iteration failed
                             (default: 90)
  -i, --interface IFACE     interface to watch (default: wlan0)
  -o, --output-dir DIR      where the run log is written
                             (default: /var/log/halo-suspend-repro)
  -p, --probe-recovery      opt-in diagnostic: on a failed iteration, run
                             `modprobe -r mt7925e && modprobe mt7925e` and
                             re-poll for an IP, recording whether it
                             recovered. Off by default. This flag is the
                             only thing that ever triggers it, and only
                             after a failure already happened -- it is never
                             wired into a resume hook.
  -c, --check               preflight only: verify root, the RTC wake path,
                             unmasked sleep targets, and IFACE; arms and
                             clears a harmless 5s test alarm. Never
                             suspends. Run this first.
      --continue-on-failure keep looping after a non-recovered failure
                             (default: stop after the first one, since a
                             wedged interface usually means ssh to the box
                             is gone for the rest of the run)
  -h, --help                this text
EOF
}

die() {
  printf '%s: %s\n' "$PROG" "$1" >&2
  if [[ -n ${LOG_FILE:-} ]]; then
    printf '%s: %s\n' "$PROG" "$1" >>"$LOG_FILE" 2>/dev/null || true
  fi
  exit 1
}

clear_rtc() {
  if [[ -w $RTC_WAKEALARM ]]; then
    printf '0\n' >"$RTC_WAKEALARM" 2>/dev/null || true
  fi
}

# Clears, arms an RTC wake alarm $1 seconds out, and validates the readback.
# Never suspends. Sets WAKE_EPOCH on success. Returns 1 (does not exit) on
# any failure so callers -- including --check -- can report and continue.
arm_rtc() {
  local seconds=$1 before after expected delta
  clear_rtc
  before=$(date +%s)
  if ! rtcwake -u -m no -s "$seconds" >/dev/null 2>&1; then
    printf '%s: rtcwake failed to arm a %ss wake alarm\n' "$PROG" "$seconds" >&2
    return 1
  fi
  after=$(cat "$RTC_WAKEALARM" 2>/dev/null || printf '0')
  expected=$((before + seconds))
  if ((after >= expected)); then
    delta=$((after - expected))
  else
    delta=$((expected - after))
  fi
  if ((delta > 5)); then
    printf '%s: RTC alarm readback off by %ss (expected ~%s, got %s)\n' \
      "$PROG" "$delta" "$expected" "$after" >&2
    return 1
  fi
  WAKE_EPOCH=$after
  return 0
}

rtc_selftest() {
  if [[ ! -e $RTC_WAKEALARM ]]; then
    printf 'FAIL  no RTC wakealarm at %s -- no reliable unattended wake mechanism on this hardware.\n' "$RTC_WAKEALARM"
    printf '      Do not run unattended loops. Manual-wake fallback: be physically at the box\n'
    printf '      (power button / TV remote) to wake it after each suspend.\n'
    return 1
  fi
  if ! [[ -w $RTC_WAKEALARM ]]; then
    printf 'FAIL  %s exists but is not writable as this user.\n' "$RTC_WAKEALARM"
    return 1
  fi
  if arm_rtc 5; then
    clear_rtc
    printf 'ok    RTC wake alarm arms and reads back correctly (armed 5s ahead, verified, cleared)\n'
    return 0
  fi
  printf 'FAIL  RTC alarm did not arm or read back correctly -- see stderr above.\n'
  return 1
}

print_unmask_instructions() {
  cat <<'EOF'
      The sleep/suspend targets are masked on halo (hosts/halo/default.nix,
      the systemd.targets.{sleep,suspend,hibernate,hybrid-sleep}.enable =
      false block). `systemctl unmask` will NOT work here: /etc/systemd/system
      is a symlink into the read-only /nix/store, so the mask can't be
      deleted at runtime.

      To run this harness:
        1. Comment out (or delete) that four-line block in hosts/halo/default.nix
        2. sudo nixos-rebuild test --flake .#halo
           ("test", not switch/boot -- a reboot reverts to the masked
           config on its own, so this is self-healing)
        3. Re-run this harness
        4. When done, revert the file (git checkout) -- the mask returns on
           the next switch/reboot regardless, but keep the tree clean
EOF
}

check_sleep_unmasked() {
  local t state masked=0
  for t in sleep suspend hibernate hybrid-sleep; do
    state=$(systemctl is-enabled "${t}.target" 2>/dev/null || true)
    [[ $state == masked ]] && masked=1
  done
  ((masked == 0))
}

check_interface() {
  ip link show "$INTERFACE" >/dev/null 2>&1
}

preflight() {
  local ok=1

  if ((EUID == 0)); then
    printf 'ok    running as root\n'
  else
    printf 'FAIL  must run as root\n'
    ok=0
  fi

  if check_sleep_unmasked; then
    printf 'ok    sleep/suspend targets unmasked\n'
  else
    printf 'FAIL  sleep/suspend targets are masked\n'
    print_unmask_instructions
    ok=0
  fi

  if check_interface; then
    printf 'ok    interface %s exists\n' "$INTERFACE"
  else
    printf 'FAIL  interface %s not found\n' "$INTERFACE"
    ok=0
  fi

  rtc_selftest || ok=0

  ((ok))
}

validate_config() {
  [[ ${SLEEP_SECONDS:-} =~ ^[0-9]+$ ]] || die "-s/--sleep-seconds is required and must be a positive integer"
  [[ $SLEEP_SECONDS -ge 1 ]] || die "-s/--sleep-seconds must be >= 1"
  [[ $ITERATIONS =~ ^[0-9]+$ && $ITERATIONS -ge 1 ]] || die "-n/--iterations must be >= 1"
  [[ $IP_TIMEOUT =~ ^[0-9]+$ ]] || die "-t/--ip-timeout must be a non-negative integer"
}

# Polls for an IPv4 address on $INTERFACE for up to $1 seconds. Sets
# POLL_RESULT (PASS|FAIL) and POLL_ELAPSED. Never pipes to grep -- captures
# `ip` output into a variable and matches with a bash regex instead, so an
# address-less poll (the normal case at t=0) can't trip errexit/pipefail.
poll_for_ip() {
  local timeout=$1 elapsed=0 addr_out
  POLL_RESULT=FAIL
  POLL_ELAPSED=n/a
  while ((elapsed <= timeout)); do
    addr_out=$(ip -4 addr show dev "$INTERFACE" 2>/dev/null || true)
    if [[ $addr_out =~ inet\ [0-9]+\.[0-9]+\.[0-9]+\.[0-9]+ ]]; then
      POLL_RESULT=PASS
      POLL_ELAPSED=$elapsed
      return
    fi
    sleep 1
    elapsed=$((elapsed + 1))
  done
}

# Runs one suspend/resume cycle and records it. Sets ITER_STATUS. Deliberately
# not run in a subshell/command substitution by its caller -- it mutates the
# global SIGNAL_HITS correlation table, which a $(...) capture would discard.
run_iteration() {
  local n=$1
  local pre_epoch post_epoch suspend_rc=0
  local association=n/a default_route=n/a
  local probe_ran=no probe_recovered=n/a probe_output=n/a
  local kern_slice="" iwd_slice="" suspend_hits

  pre_epoch=$(date +%s)

  if ! arm_rtc "$SLEEP_SECONDS"; then
    die "RTC arming failed -- refusing to suspend unattended (rerun with --check for diagnostics)"
  fi

  printf 'iteration %d: armed RTC for %ss (epoch %s), issuing systemctl suspend\n' \
    "$n" "$SLEEP_SECONDS" "$WAKE_EPOCH"

  systemctl suspend || suspend_rc=$?

  # systemctl suspend only enqueues the sleep operation and returns
  # immediately (systemd docs: "will not wait for the suspend/resume cycle
  # to complete") -- this loop is what actually freezes and resumes with
  # the OS. The "did we actually suspend" check below (journal evidence,
  # not this loop's duration) is what catches a masked/blocked
  # never-suspended run.
  while (($(date +%s) < WAKE_EPOCH)); do
    sleep 1
  done
  post_epoch=$(date +%s)

  journalctl --sync 2>/dev/null || true

  kern_slice=$(journalctl -k --since "@$pre_epoch" --until "@$post_epoch" 2>/dev/null || true)
  suspend_hits=$(grep -c 'PM: suspend entry' <<<"$kern_slice" || true)

  if [[ ${suspend_hits:-0} -eq 0 ]]; then
    ITER_STATUS=NEVER-SUSPENDED
    printf 'iteration %d: no "PM: suspend entry" in the resume window -- the box never actually\n' "$n"
    printf '  suspended (masked target, blocked inhibitor?). Not counted as a pass.\n'
    write_iteration_block "$n" "$ITER_STATUS" "$pre_epoch" "$post_epoch" "$suspend_rc" \
      "$kern_slice" "" "n/a" "n/a" "$association" "$default_route" \
      "$probe_ran" "$probe_recovered" "$probe_output"
    record_signal_hits "$ITER_STATUS" "$kern_slice"
    return
  fi

  poll_for_ip "$IP_TIMEOUT"
  local ip_result=$POLL_RESULT ip_elapsed=$POLL_ELAPSED

  local iwd_out
  iwd_out=$(iwctl station "$INTERFACE" show 2>/dev/null || true)
  if [[ $iwd_out =~ State[[:space:]]+([A-Za-z_-]+) ]]; then
    association="${BASH_REMATCH[1]}"
  fi

  local route_out
  route_out=$(ip route show default 2>/dev/null || true)
  if [[ -n $route_out ]]; then
    default_route="$route_out"
  else
    default_route=none
  fi

  ITER_STATUS=$ip_result

  if [[ $ip_result == FAIL && $PROBE_RECOVERY -eq 1 ]]; then
    probe_ran=yes
    local mrc=0 merr probe_timeout
    merr=$({ modprobe -r mt7925e && sleep 2 && modprobe mt7925e; } 2>&1) || mrc=$?
    probe_output="${merr:-<no output>}"
    if ((mrc != 0)); then
      probe_recovered="probe-failed(rc=$mrc)"
      ITER_STATUS=NOT-RECOVERED
    else
      probe_timeout=$((IP_TIMEOUT < 60 ? IP_TIMEOUT : 60))
      poll_for_ip "$probe_timeout"
      if [[ $POLL_RESULT == PASS ]]; then
        probe_recovered=yes
        ITER_STATUS=RECOVERED
      else
        probe_recovered=no
        ITER_STATUS=NOT-RECOVERED
      fi
    fi
  fi

  iwd_slice=$(journalctl -u iwd -u iwd-resume -u NetworkManager \
    --since "@$pre_epoch" --until "@$(date +%s)" 2>/dev/null || true)

  write_iteration_block "$n" "$ITER_STATUS" "$pre_epoch" "$post_epoch" "$suspend_rc" \
    "$kern_slice" "$iwd_slice" "$ip_result" "$ip_elapsed" "$association" "$default_route" \
    "$probe_ran" "$probe_recovered" "$probe_output"
  record_signal_hits "$ITER_STATUS" "$kern_slice"

  sync
}

record_signal_hits() {
  local status=$1 slice=$2 key
  [[ $status == PASS ]] && return
  for key in "${!SIGNAL_HITS[@]}"; do
    if grep -qF "$key" <<<"$slice"; then
      SIGNAL_HITS[$key]=$((SIGNAL_HITS[$key] + 1))
    fi
  done
}

write_iteration_block() {
  local n=$1 status=$2 pre=$3 post=$4 suspend_rc=$5 kern=$6 iwd=$7
  local ip_result=$8 ip_elapsed=$9 association=${10} default_route=${11}
  local probe_ran=${12} probe_recovered=${13} probe_output=${14}
  {
    printf '\n=== iteration %s ===\n' "$n"
    printf 'status: %s\n' "$status"
    printf 'requested sleep: %ss   actual elapsed: %ss\n' "$SLEEP_SECONDS" "$((post - pre))"
    printf 'suspend trigger rc: %s\n' "$suspend_rc"
    printf 'ip result: %s   time-to-ip: %s\n' "$ip_result" "$ip_elapsed"
    printf 'iwd association state: %s\n' "$association"
    printf 'default route: %s\n' "$default_route"
    printf 'probe-recovery ran: %s   recovered: %s\n' "$probe_ran" "$probe_recovered"
    if [[ $probe_output != n/a ]]; then
      printf 'probe-recovery output:\n%s\n' "$probe_output"
    fi
    printf -- '--- kernel log, suspend->resume window, unfiltered ---\n'
    printf '%s\n' "${kern:-<empty>}"
    printf -- '--- iwd / iwd-resume / NetworkManager journal, resume window ---\n'
    printf '%s\n' "${iwd:-<empty>}"
  } >>"$LOG_FILE"
}

print_summary() {
  local total=$1 failed=$2
  {
    printf '\n=== summary ===\n'
    printf 'iterations run: %d   non-pass: %d\n' "$total" "$failed"
    printf 'signal correlation (count of non-PASS iterations whose kernel slice contains each pattern):\n'
    local key
    for key in "${!SIGNAL_HITS[@]}"; do
      printf '  %-20s %d\n' "$key" "${SIGNAL_HITS[$key]}"
    done
  } | tee -a "$LOG_FILE" || true
}

parse_args() {
  ITERATIONS=1
  IP_TIMEOUT=90
  INTERFACE=wlan0
  OUTPUT_DIR=/var/log/halo-suspend-repro
  PROBE_RECOVERY=0
  CHECK_ONLY=0
  CONTINUE_ON_FAILURE=0
  SLEEP_SECONDS=""

  while (($# > 0)); do
    case $1 in
    -s | --sleep-seconds)
      (($# >= 2)) || die "$1 requires a value"
      SLEEP_SECONDS=$2
      shift
      ;;
    -n | --iterations)
      (($# >= 2)) || die "$1 requires a value"
      ITERATIONS=$2
      shift
      ;;
    -t | --ip-timeout)
      (($# >= 2)) || die "$1 requires a value"
      IP_TIMEOUT=$2
      shift
      ;;
    -i | --interface)
      (($# >= 2)) || die "$1 requires a value"
      INTERFACE=$2
      shift
      ;;
    -o | --output-dir)
      (($# >= 2)) || die "$1 requires a value"
      OUTPUT_DIR=$2
      shift
      ;;
    -p | --probe-recovery) PROBE_RECOVERY=1 ;;
    -c | --check) CHECK_ONLY=1 ;;
    --continue-on-failure) CONTINUE_ON_FAILURE=1 ;;
    -h | --help)
      usage
      exit 0
      ;;
    -*)
      printf '%s: unknown flag %s\n\n' "$PROG" "$1" >&2
      usage >&2
      exit 2
      ;;
    *)
      printf '%s: unexpected argument %s\n\n' "$PROG" "$1" >&2
      usage >&2
      exit 2
      ;;
    esac
    shift
  done
}

main() {
  parse_args "$@"

  if ((CHECK_ONLY)); then
    preflight
    return $?
  fi

  ((EUID == 0)) || die "must run as root"
  validate_config

  # Clears any RTC alarm this run armed if the operator interrupts the
  # script (Ctrl-C/SIGTERM) mid-run, instead of leaving a stray future wake.
  trap clear_rtc EXIT

  mkdir -p "$OUTPUT_DIR"
  LOG_FILE="$OUTPUT_DIR/$(hostname)-$(date +%Y%m%dT%H%M%S).log"
  : >"$LOG_FILE"

  if ! preflight | tee -a "$LOG_FILE"; then
    die "preflight failed -- see above, and $LOG_FILE"
  fi

  printf 'log: %s\n' "$LOG_FILE"

  local i ran=0 failed=0
  for ((i = 1; i <= ITERATIONS; i++)); do
    ran=$i
    run_iteration "$i"
    printf 'iteration %d: %s\n' "$i" "$ITER_STATUS"
    if [[ $ITER_STATUS != PASS && $ITER_STATUS != RECOVERED ]]; then
      failed=$((failed + 1))
      if ((! CONTINUE_ON_FAILURE)); then
        printf 'stopping after failure (iteration %d); pass --continue-on-failure to keep going\n' "$i" |
          tee -a "$LOG_FILE"
        break
      fi
    fi
  done

  print_summary "$ran" "$failed"
  printf 'log: %s\n' "$LOG_FILE"
}

main "$@"
