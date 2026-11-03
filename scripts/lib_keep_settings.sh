# Sourced by enable_hook.sh: carry the owner's own settings over to a new
# install, so a fresh gal_dualscreen.conf from a new zip does not quietly
# drop lines the owner had changed (#19: a card position lost on beta18).
#
# The owner's lines are the ones in the card's gal_dualscreen.conf that
# differ from the defaults shipped with that release
# (scripts/gal_dualscreen.default.conf). Each install saves them on the unit
# (gal_dualscreen.owner.conf). The next install puts a saved line back only
# where the new card still has the shipped default for that setting: a line
# the owner changes on the new card always wins. CLUSTERMAP_KEEP_SETTINGS=0
# on the card installs only what the card says; the uninstall forgets them.
#
# Plain POSIX awk with getline from named files: the unit's tools are few.

# keep_owner_lines CONF DEFAULT: print the KEY=VALUE lines of CONF whose
# value differs from DEFAULT's (first active line of each key, as the hook
# reads it), or whose key DEFAULT does not set.
keep_owner_lines()
{
    awk -v conf="$1" -v def="$2" '
    function kv(line) {
        if (line !~ /^[A-Z][A-Z0-9_]*=/) return 0
        K = substr(line, 1, index(line, "=") - 1)
        V = substr(line, index(line, "=") + 1)
        sub(/[ \t\r]+$/, "", V)
        return 1
    }
    BEGIN {
        while ((getline l < def) > 0) if (kv(l) && !(K in d)) d[K] = V
        close(def)
        while ((getline l < conf) > 0) {
            if (!kv(l) || (K in seen)) continue
            seen[K] = 1
            if (K == "CLUSTERMAP_KEEP_SETTINGS") continue
            if (!(K in d) || d[K] != V) print K "=" V
        }
        close(conf)
    }'
}

# keep_apply CONF OWNER DEFAULT: rewrite CONF (through CONF.new and a
# rename) with each OWNER line whose key CONF still has at DEFAULT's value,
# or leaves unset where DEFAULT does too. Prints the lines it put back.
# Returns 1, CONF untouched, if the rewrite fails.
keep_apply()
{
    awk -v conf="$1" -v own="$2" -v def="$3" -v out="$1.new" '
    function kv(line) {
        if (line !~ /^[A-Z][A-Z0-9_]*=/) return 0
        K = substr(line, 1, index(line, "=") - 1)
        V = substr(line, index(line, "=") + 1)
        sub(/[ \t\r]+$/, "", V)
        return 1
    }
    BEGIN {
        while ((getline l < def) > 0) if (kv(l) && !(K in d)) d[K] = V
        close(def)
        while ((getline l < conf) > 0) if (kv(l) && !(K in c)) c[K] = V
        close(conf)
        n = 0
        while ((getline l < own) > 0) {
            if (!kv(l) || K == "CLUSTERMAP_KEEP_SETTINGS" || (K in keep)) continue
            cv = (K in c) ? c[K] : "\001unset"
            dv = (K in d) ? d[K] : "\001unset"
            if (cv == dv && V != dv) { keep[K] = V; order[++n] = K }
        }
        close(own)
        if (n == 0) exit 0
        while ((getline l < conf) > 0) {
            if (kv(l) && (K in keep)) { print K "=" keep[K] > out; done[K] = 1 }
            else print l > out
        }
        close(conf)
        added = 0
        for (i = 1; i <= n; i++) {
            k = order[i]
            if (!(k in done)) {
                if (!added) { print "" > out; print "# Kept from your previous install (CLUSTERMAP_KEEP_SETTINGS=0 on the card for a clean one)" > out; added = 1 }
                print k "=" keep[k] > out
            }
            print k "=" keep[k]
        }
        close(out)
    }' && { [ ! -f "$1.new" ] || mv "$1.new" "$1"; } || { rm -f "$1.new" 2>/dev/null; return 1; }
}
