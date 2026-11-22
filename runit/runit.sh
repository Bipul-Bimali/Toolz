#!/bin/bash
# runit - run a command detached; all state lives in ~/.runit/<PID>/
#   bash ./runit.sh '<command>'                 start, prints ONLY the PID
#   bash ./runit.sh status <pid>                STATE=running|finished EXIT=n|died_no_exit_code
#   bash ./runit.sh send <pid> [text]           send a line to the job's stdin (no text = Enter)
#   bash ./runit.sh log <pid> [console|stdout|stderr] [lines]
#   bash ./runit.sh ls                          list jobs
#   bash ./runit.sh kill <pid>
umask 077
B=${RUNIT_HOME:-$HOME/.runit}
SELF=$(readlink -f "$0")

case "$1" in
__run)  # internal: runs as the detached wrapper
  D=$B/$$; mkdir -p "$D"  && cd "$D" || exit 1
  mkfifo run.in; exec 3<>run.in          # fd 3 keeps the FIFO open (no EOF)
  echo $$ > job.pid; printf '%s\n' "$BG_CMD" > cmd; date -Is > started
  echo $$ > "$BG_TMP"                    # tell the launcher our PID
  bash -c "$BG_CMD" <&3 3<&- \
    > >(tee stdout >> console.out) 2> >(tee stderr >> console.out) &
  c=$!; echo $c > child.pid
  wait $c; rc=$?; sleep 0.3              # let tee flush
  echo $rc > exit.tmp; mv exit.tmp exit_code; date -Is > ended ;;

status)
  D=$B/$2; [ -d "$D" ] || { echo "STATE=unknown"; exit 1; }
  if [ -f "$D/exit_code" ]; then echo "STATE=finished EXIT=$(cat "$D/exit_code")"
  elif kill -0 "$(cat "$D/job.pid")" 2>/dev/null; then echo "STATE=running"
  else echo "STATE=died_no_exit_code"; fi ;;

send)
  D=$B/$2; [ -f "$D/exit_code" ] && { echo "job already finished" >&2; exit 1; }
  timeout 2 bash -c 'printf "%s\n" "$1" > "$2"' _ "$3" "$D/run.in" \
    || { echo "send failed (job not reading?)" >&2; exit 1; } ;;

log)
  f=${3:-console}; [ "$f" = console ] && f=console.out
  tail -n "${4:-20}" "$B/$2/$f" 2>/dev/null ;;

ls)
  for d in "$B"/[0-9]*; do [ -d "$d" ] || continue; p=${d##*/}
    echo "$p  $("$SELF" status "$p")  $(head -c 60 "$d/cmd")"; done ;;

kill)
  kill "$(cat "$B/$2/child.pid")" 2>/dev/null && echo "sent TERM" ;;

""|-h|--help) sed -n '2,8p' "$SELF"; exit 2 ;;

*)  # launch: join args into one command string
  mkdir -p "$B"; T=$(mktemp "$B/.new.XXXXXX")
  BG_CMD="$*" BG_TMP=$T setsid nohup bash "$SELF" __run </dev/null >/dev/null 2>&1 &
  for _ in $(seq 50); do [ -s "$T" ] && break; sleep 0.1; done
  [ -s "$T" ] || { echo "failed to start" >&2; rm -f "$T"; exit 1; }
  cat "$T"; rm -f "$T" ;;
esac
