# Watchdog for every klt engine invocation in flow/ (issue #156). Source it:
#
#   . ./klt-watchdog.sh          # or . ../klt-watchdog.sh from flow/smoke/
#
# then replace each direct "$KLT" call with
#
#   klt_bounded <stdout-file> <stderr-file> <diag-file> cmd [args...]
#
# stdout-file / stderr-file: where cmd's stdout/stderr go; "-" passes the
# caller's own stdout/stderr through (synthesize.sh --check prints to the
# terminal exactly as it did unbounded). diag-file is written ONLY on expiry.
#
# Why: the yosys/ABC stage wedges intermittently on the shared worker. yosys
# blocks in anon_pipe_read on abc's stdout pipe while abc waits on stdin for
# the EOF that never comes; the pair sits at ~0% CPU forever, the wrapper
# hangs until something external kills it, and the orphaned pair survives
# that kill holding host resources.
#
# Behaviour:
#   * cmd runs in a NEW process group (setsid) -- never the wrapper's own --
#     so expiry kills the whole run (klt, yosys, yosys-abc) without touching
#     the wrapper or its caller. The group is asserted distinct from the
#     wrapper's before any signal is sent.
#   * Waits at most $KLT_TIMEOUT seconds (default $KLT_TIMEOUT_DEFAULT).
#   * Natural exit: cmd's exit status is returned unchanged and nothing is
#     written -- a healthy run is indistinguishable from an unbounded one.
#   * Expiry: per-process diagnostics first (pid, ppid, stat, cmdline, wchan
#     and the /proc fd listing of every process still in the run's group),
#     then SIGTERM then SIGKILL to that group, then returns 124
#     (timeout(1)'s convention for expiry) having named the diagnostic file
#     on stderr. 124 lets callers distinguish a timed-out run from an engine
#     failure that also exits non-zero.
#
# Callers must not enable job control (set -m): with job control on, setsid
# forks and the watchdog cannot learn the new group (it fails loudly instead).
# Diagnostics read /proc, so this is Linux-only -- every host this repo's flow
# runs on is Linux.
# shellcheck shell=bash

KLT_TIMEOUT_DEFAULT=900

klt_bounded() {
  local out="$1" err="$2" diag="$3"
  shift 3
  local bound="${KLT_TIMEOUT:-$KLT_TIMEOUT_DEFAULT}"
  local mypgid pid pgid state waited rc survivors

  case $bound in
    '' | *[!0-9]*)
      echo "klt-watchdog: KLT_TIMEOUT='$bound' is not a non-negative integer" >&2
      return 2
      ;;
  esac
  if ! command -v setsid > /dev/null 2>&1; then
    echo "klt-watchdog: setsid not found; cannot start a bounded process group" >&2
    return 2
  fi

  mypgid=$(ps -o pgid= -p "$$" 2> /dev/null | tr -d '[:space:]' || true)

  if [ "$out" = "-" ]; then out=/dev/fd/1; fi
  if [ "$err" = "-" ]; then err=/dev/fd/2; fi
  # setsid: the child leaves the wrapper's process group. Without job control
  # (none of the callers use set -m) a background job is not a group leader,
  # so setsid execs in place and $! stays the command's pid AND the new group.
  setsid "$@" > "$out" 2> "$err" &
  pid=$!

  pgid=$(ps -o pgid= -p "$pid" 2> /dev/null | tr -d '[:space:]' || true)
  if [ "$pgid" = "$mypgid" ]; then
    # The setsid(2) call may not have landed yet; give it one chance before
    # concluding something is wrong.
    sleep 0.2
    pgid=$(ps -o pgid= -p "$pid" 2> /dev/null | tr -d '[:space:]' || true)
  fi
  if [ -z "$pgid" ]; then
    # Not every vanished pid is a mystery: a fast engine failure (bad
    # arguments, an immediate refusal) can finish before this first probe.
    # That is a normal exit -- reap it and return its status unchanged.
    state=$(ps -o stat= -p "$pid" 2> /dev/null | tr -d '[:space:]' || true)
    case $state in
      '' | Z*)
        rc=0
        wait "$pid" || rc=$?
        return "$rc"
        ;;
    esac
    echo "klt-watchdog: pid $pid vanished before its process group could be read" >&2
    kill -TERM "$pid" 2> /dev/null || true
    rc=0
    wait "$pid" || rc=$?
    return 2
  fi
  if [ "$pgid" = "$mypgid" ]; then
    echo "klt-watchdog: pid $pid stayed in the wrapper's own group $mypgid; refusing a group kill" >&2
    kill -TERM "$pid" 2> /dev/null || true
    rc=0
    wait "$pid" || rc=$?
    return 2
  fi

  # Bounded wait. kill -0 would never see an exit: the child stays a zombie
  # (kill-able) until this shell waits on it, so poll ps's state instead --
  # '' means gone, Z* means zombie, both mean the status is in wait.
  waited=0
  while :; do
    state=$(ps -o stat= -p "$pid" 2> /dev/null | tr -d '[:space:]' || true)
    case $state in
      '' | Z*) break ;;
    esac
    if [ "$waited" -ge "$bound" ]; then
      break
    fi
    sleep 1
    waited=$((waited + 1))
  done

  # Boundary race: the bound expired but the child finished in the same
  # second -- return its real status, not an expiry.
  state=$(ps -o stat= -p "$pid" 2> /dev/null | tr -d '[:space:]' || true)
  case $state in
    '' | Z*)
      rc=0
      wait "$pid" || rc=$?
      return "$rc"
      ;;
  esac

  echo "klt-watchdog: bound of ${bound}s exceeded running: $*" >&2

  # Diagnostics FIRST -- the wedged /proc state is the evidence; killing it
  # destroys it. Every process still in the run's group: pid, cmdline, wchan
  # and fd listing, enough that the next recurrence needs no live /proc
  # session to diagnose.
  mkdir -p "$(dirname "$diag")"
  {
    echo "klt-watchdog diagnostics (captured before any signal was sent)"
    echo "date: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "wrapper: pid $$ pgid $mypgid"
    echo "command: $*"
    echo "bound: ${bound}s (KLT_TIMEOUT=${KLT_TIMEOUT-<unset>}, default $KLT_TIMEOUT_DEFAULT)"
    echo "leader: pid $pid process group $pgid"
    echo
    local p pp st
    while read -r p pp st; do
      [ -n "$p" ] || continue
      echo "=== pid $p  ppid $pp  stat $st"
      echo "cmdline: $(tr '\0' ' ' < /proc/"$p"/cmdline 2>&1 || true)"
      echo "wchan:   $(cat /proc/"$p"/wchan 2>&1 || true)"
      echo "fds:"
      ls -l /proc/"$p"/fd 2>&1 || true
      echo
    done < <(ps -eo pid=,ppid=,pgid=,stat= 2> /dev/null | awk -v g="$pgid" '$3 == g')
    echo "(end of pre-kill diagnostics)"
  } > "$diag"

  # Kill the group the watchdog created -- SIGTERM first so a well-behaved
  # engine could clean up, SIGKILL so the wedged pair cannot survive.
  kill -TERM -- "-$pgid" 2> /dev/null || true
  sleep 2
  kill -KILL -- "-$pgid" 2> /dev/null || true
  sleep 1
  survivors=$(ps -eo pid=,pgid=,stat= 2> /dev/null \
    | awk -v g="$pgid" '$2 == g && $3 !~ /^Z/ { print $1 }' || true)
  {
    echo "kill: SIGTERM -> group $pgid, then SIGKILL after a 2s grace"
    echo "survivors after SIGKILL: ${survivors:-none}"
  } >> "$diag"
  if [ -n "$survivors" ]; then
    echo "klt-watchdog: WARNING: still alive in group $pgid after SIGKILL: $survivors" >&2
  fi

  rc=0
  wait "$pid" 2> /dev/null || rc=$?
  echo "klt-watchdog: timed out after ${bound}s running: $*" >&2
  echo "klt-watchdog: diagnostics in $diag" >&2
  return 124
}
