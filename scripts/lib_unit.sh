# Sourced by the installer, the green menu and the log collector. What this
# project knows about a train (profiles.conf), and what this unit really has.

# train_has <profiles.conf> <train> <word>: its "train" line says <word>.
train_has()
{
    while read -r KEY SUB REST; do
        [ "$KEY" = train ] || continue
        case "$2" in
            *$SUB*) case " $REST " in *" $3 "*) return 0 ;; esac ;;
        esac
    done < "$1"
    return 1
}

# unit_make <profiles.conf> <train>: sets CAR_MAKE, CAR_WINDOW, CAR_DPI,
# CAR_INSETS and CAR_CONTEXT from the first "make" line whose pattern matches.
unit_make()
{
    CAR_MAKE=; CAR_WINDOW=; CAR_DPI=125; CAR_INSETS=40,40,127,127; CAR_CONTEXT=70
    # The fields are read into MK_* names: plain DPI here overwrote the
    # installer's own DPI (its --dpi value), which then went into GAL's
    # environment and silently beat the owner's GAL_SECONDARY_DPI.
    while read -r MK_KEY MK_PAT MK_NAME MK_WIN MK_DPI MK_INS MK_CTX; do
        [ "$MK_KEY" = make ] || continue
        case "$2" in
            $MK_PAT) CAR_MAKE=$MK_NAME; CAR_WINDOW=$MK_WIN; CAR_DPI=$MK_DPI
                  CAR_INSETS=$MK_INS; CAR_CONTEXT=$MK_CTX; return 0 ;;
        esac
    done < "$1"
    return 1
}

# unit_gal_check <package folder>: compare this unit's gal with profiles.conf.
# Sets PROBE_OUT (what it found, kept for the logs) and PROBE_MATCH (profile
# name). The card may not allow running programs, so it runs from /tmp.
unit_gal_check()
{
    PROBE_OUT=; PROBE_MATCH=
    PROBE_BIN=/tmp/clustermap_profile_check
    cp "$1/profile_check" "$PROBE_BIN" 2>/dev/null || return 1
    chmod 755 "$PROBE_BIN" 2>/dev/null
    PROBE_OUT=`"$PROBE_BIN" /mnt/app/eso/bin/apps/gal "$1/profiles.conf" 2>&1`
    rm -f "$PROBE_BIN"
    PROBE_MATCH=`echo "$PROBE_OUT" | sed -n 's/^match=\([A-Za-z0-9_]*\) tested=.*/\1/p'`
    [ -n "$PROBE_OUT" ]
}

# unit_tools: which commands this unit lacks. Units differ, and more than once
# a script has failed on a command that one unit did not have (printf and tr,
# #19 and #28). UNIT_MISSING: needed, nothing may be changed without them.
# UNIT_ABSENT: scripts work without them, kept in the logs.
unit_tools()
{
    UNIT_MISSING=; UNIT_ABSENT=
    command -v sh >/dev/null 2>&1 || { UNIT_ABSENT="(no command -v, not checked)"; return 0; }
    for t in sed grep awk wc cp mv rm mkdir chmod mount expr head tail; do
        command -v $t >/dev/null 2>&1 || UNIT_MISSING="$UNIT_MISSING $t"
    done
    for t in printf tr cmp diff cut sort; do
        command -v $t >/dev/null 2>&1 || UNIT_ABSENT="$UNIT_ABSENT $t"
    done
    return 0
}
