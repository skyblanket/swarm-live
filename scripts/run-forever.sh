#!/bin/sh
# Keep an evolve run going: restart it (from its checkpoints) whenever it exits or crashes.
# usage: scripts/run-forever.sh <log> <command...>     e.g. scripts/run-forever.sh evolve3.log scripts/run.sh evolve3
log="$1"; shift
while :; do
    echo "[run-forever] $(date) starting: $*" >> "$log"
    "$@" >> "$log" 2>&1
    echo "[run-forever] $(date) exited with $?; restarting in 5s" >> "$log"
    sleep 5
done
