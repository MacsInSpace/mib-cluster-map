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
# expr is in /mnt/app/armle/usr/bin on this unit (Golf R log: "expr: cannot execute").
PATH=/proc/boot:/bin:/usr/bin:/usr/sbin:/sbin:/eso/bin:/mnt/app/eso/bin:/mnt/app/navigation:/mnt/app/armle/bin:/mnt/app/armle/usr/bin
export PATH

OWNER=${1:-}
PLAYER=/mnt/app/navigation/stream-player
SOURCE=tcp://127.0.0.1:19820
STATE=/tmp/mibr-carplay111.state
PIDFILE=/tmp/carplay_cluster.pid
PLAYER_LOG=/tmp/stream-player-carplay.log
PLAYER_PID=
PLAYER_START=0

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
    # The iPhone has just been unplugged: write down who is still running, so a
    # mm-ipod that did not exit (and then blocks the next CarPlay connection)
    # is on the card without Green Menu -> Save logs to SD.
    pidin ar > /tmp/clustermap-pidin-exit.txt 2>/dev/null
    sync_live_logs_now
    # Again a little later: by then mm-ipod should be gone.
    ( sleep 20
      pidin ar > /tmp/clustermap-pidin-after.txt 2>/dev/null
      sync_live_logs_now ) >/dev/null 2>&1 &
    [ "`cat $PIDFILE 2>/dev/null`" = $$ ] && rm -f "$PIDFILE"
}
trap cleanup 0
trap 'exit 0' 1 2 15

# Mirror live RAM logs to the SD card (if inserted in sda0/sdb0) every 15s so
# drive diagnostics are preserved even if the car is turned off without running
# Green Menu -> Save logs to SD.
# Run in a background subshell and skip if savelogs.sh/collect_logs.sh is running
# so we never block dio_manager teardown or race with Green Menu log collection.
SYNC_TICK=0
sync_live_logs_now() {
    [ -f /tmp/clustermap-savelogs.lock ] && return
    for SD in /fs/sda0 /fs/sdb0; do
        if [ -d "$SD/ClusterMap" ]; then
            mount -uw "$SD" 2>/dev/null
            mkdir -p "$SD/ClusterMap/live_logs" 2>/dev/null
            cp /tmp/clustermap-gfxstate.log /tmp/clustermap-rgd.log /tmp/clustermap-rgd.state \
               /tmp/clustermap-wheelzoom.log /tmp/carplay_cluster.log /tmp/stream-player-carplay.log \
               /tmp/mibr-carplay111.state /tmp/altscreen111.log /tmp/mibr-alt111-gen2.status \
               /tmp/clustermap-pidin-exit.txt /tmp/clustermap-pidin-after.txt \
               /dev/shmem/iap2.log "$SD/ClusterMap/live_logs/" 2>/dev/null
            break
        fi
    done
}
sync_live_logs() {
    [ -f /tmp/clustermap-savelogs.lock ] && return
    ( sync_live_logs_now ) >/dev/null 2>&1 &
}

log "started for dio_manager $OWNER"
# Snapshots of the previous unplug: not this one's, so they go first.
rm -f /tmp/clustermap-pidin-exit.txt /tmp/clustermap-pidin-after.txt 2>/dev/null
sync_live_logs
FAILS=0
while kill -0 "$OWNER" 2>/dev/null; do
    SYNC_TICK=`expr $SYNC_TICK + 1`
    if [ $SYNC_TICK -ge 15 ]; then
        SYNC_TICK=0
        sync_live_logs
    fi
    CUR=`cat "$STATE" 2>/dev/null`
    if [ "$CUR" = streaming ]; then
        if ! player_running; then
            if [ -n "$PLAYER_PID" ]; then
                # It ended on its own while CarPlay still streams. Only a
                # player that dies within 30 s counts towards giving up: one
                # that ran for minutes before the hook reset its stream is
                # not failing, and counting those made the cluster stay on
                # the car's map after the fifth reset of a drive (#10, #43).
                wait "$PLAYER_PID" 2>/dev/null
                PLAYER_PID=
                if [ `expr ${SECONDS%%.*} - $PLAYER_START` -ge 30 ]; then
                    FAILS=0
                fi
                FAILS=`expr $FAILS + 1`
                [ $FAILS -ge 5 ] && { log "player failed $FAILS times; giving up until CarPlay restarts"; break; }
                sleep 2
            fi
            log "CarPlay cluster stream is up; starting player"
            echo "==== stream-player for CarPlay ====" >> "$PLAYER_LOG"
            "$PLAYER" --no-ack "$SOURCE" >> "$PLAYER_LOG" 2>&1 &
            PLAYER_PID=$!
            PLAYER_START=${SECONDS%%.*}
        fi
    else
        [ -n "$PLAYER_PID" ] && stop_player "stream state ${CUR:-none}"
        FAILS=0
    fi
    sleep 1
done
log "dio_manager $OWNER is gone"
