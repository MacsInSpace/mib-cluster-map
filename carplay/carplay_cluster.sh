#!/bin/ksh
# CarPlay map on the cluster: runs stream-player while CarPlay sends its
# cluster video, and stops it when CarPlay stops.
#
#   carplay_cluster.sh <dio_manager pid>
#
# Started by libcarplay_cluster.so when dio_manager (CarPlay) starts; ends
# when that dio_manager does. harman-f's libaltscreen111.so, in the same
# process, receives CarPlay's cluster stream and serves it as H.264 on
# 127.0.0.1:19820, at the cluster map window's size (set by the installer).
# While it does, it writes "streaming" to its state file.
# The player draws that stream on the cluster exactly as it draws Android
# Auto's, and on SIGTERM gives the cluster back to the stock map.
PATH=/proc/boot:/bin:/usr/bin:/usr/sbin:/sbin:/eso/bin:/mnt/app/eso/bin:/mnt/app/navigation
export PATH

OWNER=${1:-}
PLAYER=/mnt/app/navigation/stream-player
SOURCE=tcp://127.0.0.1:19820
STATE=/tmp/mibr-carplay111.state
PIDFILE=/tmp/carplay_cluster.pid
PLAYER_LOG=/tmp/stream-player-carplay.log
PLAYER_PID=

log() { echo "carplay_cluster $*"; }

[ -n "$OWNER" ] || { log "no dio_manager pid given"; exit 2; }
[ -x "$PLAYER" ] || { log "no player at $PLAYER"; exit 3; }

# One supervisor at a time: a dio_manager restart starts a new one.
if [ -r "$PIDFILE" ]; then
    OLD=`cat "$PIDFILE" 2>/dev/null`
    if [ -n "$OLD" ] && [ "$OLD" != $$ ] && kill -0 "$OLD" 2>/dev/null; then
        kill "$OLD" 2>/dev/null
        sleep 1
    fi
fi
echo $$ > "$PIDFILE"

player_running() { [ -n "$PLAYER_PID" ] && kill -0 "$PLAYER_PID" 2>/dev/null; }

stop_player() {
    player_running || { PLAYER_PID=; return; }
    log "stopping player $PLAYER_PID ($1)"
    kill -TERM "$PLAYER_PID" 2>/dev/null
    n=0
    # It restores the stock map before it exits; allow it the time.
    while player_running && [ $n -lt 8 ]; do sleep 1; n=`expr $n + 1`; done
    player_running && kill -9 "$PLAYER_PID" 2>/dev/null
    wait "$PLAYER_PID" 2>/dev/null
    PLAYER_PID=
}

cleanup() {
    stop_player "supervisor exit"
    [ "`cat $PIDFILE 2>/dev/null`" = $$ ] && rm -f "$PIDFILE"
}
trap cleanup 0
trap 'exit 0' 1 2 15

log "started for dio_manager $OWNER"
FAILS=0
while kill -0 "$OWNER" 2>/dev/null; do
    CUR=`cat "$STATE" 2>/dev/null`
    if [ "$CUR" = streaming ]; then
        if ! player_running; then
            if [ -n "$PLAYER_PID" ]; then
                # It ended on its own while CarPlay still streams.
                wait "$PLAYER_PID" 2>/dev/null
                PLAYER_PID=
                FAILS=`expr $FAILS + 1`
                [ $FAILS -ge 5 ] && { log "player failed $FAILS times; giving up until CarPlay restarts"; break; }
                sleep 2
            fi
            log "CarPlay cluster stream is up; starting player"
            echo "==== stream-player for CarPlay ====" >> "$PLAYER_LOG"
            "$PLAYER" --no-ack "$SOURCE" >> "$PLAYER_LOG" 2>&1 &
            PLAYER_PID=$!
        fi
    else
        [ -n "$PLAYER_PID" ] && stop_player "stream state ${CUR:-none}"
        FAILS=0
    fi
    sleep 1
done
log "dio_manager $OWNER is gone"
