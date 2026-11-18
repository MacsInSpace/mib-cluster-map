#!/bin/sh
# tools/unit_shell_lint.py must flag every shape that was measured to stop or
# misbehave in the unit's shell, and must pass the safe spellings.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd); LINT="$HERE/../tools/unit_shell_lint.py"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
n=0; fail=0
bad()  { n=$((n+1)); printf 'set -eu\n%s\n' "$2" > "$T/c.sh"; if python3 "$LINT" "$T/c.sh" | grep -q ": $1 "; then :; else echo "MISSED $1: $2"; fail=1; fi; }
good() { n=$((n+1)); printf 'set -eu\n%s\n' "$1" > "$T/c.sh"; if python3 "$LINT" "$T/c.sh" >"$T/out"; then :; else echo "FALSE ALARM: $1"; sed 's/^/    /' "$T/out"; fail=1; fi; }
bad E1 'if true; then [ "$X" = 1 ] && echo on; fi'
bad E1 'if true; then
    [ "$X" = 1 ] && echo on
fi'
bad E1 'if false; then :; else [ "$X" = 1 ] && echo on; fi'
bad E1 'if a; then
    x
elif b; then
    [ "$X" = 1 ] && echo on
else
    y
fi'
bad E1 'case a in a) [ "$X" = 1 ] && echo on ;; esac'
bad E1 'case a in
    a)
        [ "$X" = 1 ] && echo on
        ;;
esac'
bad E1 'for i in 1 2; do [ "$i" = 1 ] && echo one; done'
bad E1 'while read k v; do
    [ "$k" = z ] && echo z
done < f'
bad E1 '{ [ "$X" = 1 ] && echo on; }'
bad E1 'if true; then
    mount -uw /mnt/app 2>/dev/null && { : > "$M"; mount -ur /mnt/app || true; }
fi'
bad E1 'if true; then
    cp a b &&
        mv b c && echo done
fi'
bad E1 'f() {
    if true; then [ "$X" = 1 ] && echo on; fi
    return 0
}'
bad E2 '! grep -q a file'
bad E3 'for a in "$@"; do :; done'
bad E4 'X=${Y/a/b}'
bad E4 'X=${Y:0:1}'
bad E4 'case $x in [[:alpha:]]*) : ;; esac'
bad E5 'echo "a\tb"'
bad E6 '. ./lib.sh 2>/dev/null || :'
good 'if [ -r ./lib.sh ]; then . ./lib.sh; fi'
bad E7 'mkdir -p /tmp/clustermap_work'
good 'echo x > /tmp/clustermap_file.txt'
good 'if [ "$X" = 1 ]; then echo on; fi'
good 'if true; then [ "$X" = 1 ] && echo on || :; fi'
good 'if true; then [ "$X" = 1 ] && echo on; echo next; fi'
good '[ "$X" = 1 ] && echo on'
good 'if [ "$X" = 1 ] && [ "$Y" = 2 ]; then echo on; fi'
good 'while read k v && [ -n "$k" ]; do echo "$k"; done < f'
good 'if true; then [ "$X" = 0 ] || echo off; fi'
good 'if true; then echo "a && b"; fi'
good 'if true; then X=`[ a = b ] && echo y || :`; fi'
good 'f() { [ -r "$1" ] && grep -q x "$1"; }
if f a; then :; fi'
good 'if ! grep -q a file; then :; fi'
good 'for a in ${1+"$@"}; do :; done'
good 'if true; then ( cd /eso && ./bin/apps/dmdt gd ) > out; fi'
good 'case a in
    a) if [ "$X" = 1 ]; then echo on; fi ;;
    *) : ;;
esac'
good 'X=`sed -n "s/a\(b\)/\1/p" f`'
good 'cat > f <<E
if true; then [ x ] && y; fi
E'
echo "unit_shell_lint_test: $n cases"
[ $fail = 0 ] && echo "PASS: unit_shell_lint" || { echo "FAIL: unit_shell_lint"; exit 1; }
