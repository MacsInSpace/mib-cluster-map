#!/bin/sh
# unit_shell_lint: skip  (this file holds the shapes the lint refuses, as test text)
# What this unit's shell and tools do, as one line per check, so the simulator
# (tests/unit_sim) can be made to match it: tests/unit_sim/probe_compare.sh
# runs the same file there and lists every line that differs.
#
#   unit_probe.sh > tool_probe.txt
#
# Each check runs in its own child shell with no input, so none can stop or
# hang the caller. Writes only under /tmp. Changes nothing on the unit.
# Line format:  name|exit status|first output lines joined with ~
PATH=/proc/boot:/bin:/usr/bin:/usr/sbin:/sbin:/mnt/app/armle/bin:/mnt/app/armle/sbin:/mnt/app/armle/usr/bin:/mnt/app/armle/usr/sbin:$PATH
export PATH
W=/tmp/clustermap_probe.$$
rm -rf $W; mkdir -p $W/d/e || exit 0
cd $W || exit 0
echo "a b c" > f1; echo "x1 y2 z3" >> f1; echo "line three" >> f1
echo "TAB	here" > ft
: > fe
echo "k=v" > fk
touch d/e/g.txt d/h.sh
# c NAME CODE: run CODE under set -eu in a child shell.
c() {
    n=$1
    o=`sh -c "set -eu
$2" < /dev/null 2>&1`
    s=$?
    o=`echo "$o" | sed -e "s|$W|W|g" -e 's/^[ 	]*//' | head -3 | sed -e ':a' -e 'N' -e 's/\n/~/' -e 'ta'`
    echo "$n|$s|$o"
}
# x NAME CODE: the same without set -e (for output only).
x() {
    n=$1
    o=`sh -c "$2" < /dev/null 2>&1`
    s=$?
    o=`echo "$o" | sed -e "s|$W|W|g" -e 's/^[ 	]*//' | head -3 | sed -e ':a' -e 'N' -e 's/\n/~/' -e 'ta'`
    echo "$n|$s|$o"
}
echo "probe|1|`echo ${KSH_VERSION:-unknown}`"

# set -e: which shapes stop a script (docs/Unit-shell.md rule 1, 2, 7)
c e_if_end       'X=0; if true; then [ "$X" = 1 ] && echo on; fi; echo ok'
c e_else_end     'X=0; if false; then :; else [ "$X" = 1 ] && echo on; fi; echo ok'
c e_case_end     'X=0; case a in a) [ "$X" = 1 ] && echo on ;; esac; echo ok'
c e_for_end      'X=0; for i in 1; do [ "$X" = 1 ] && echo on; done; echo ok'
c e_while_end    'X=0; n=0; while [ $n -lt 1 ]; do n=1; [ "$X" = 1 ] && echo on; done; echo ok'
c e_brace_end    'X=0; { [ "$X" = 1 ] && echo on; }; echo ok'
c e_and_brace    'X=0; if true; then [ "$X" = 1 ] && { echo a; }; fi; echo ok'
c e_func_ifbody  'X=0; f() { if true; then [ "$X" = 1 ] && echo on; fi; return 0; }; f; echo ok'
c e_mid_block    'X=0; if true; then [ "$X" = 1 ] && echo on; echo mid; fi; echo ok'
c e_toplevel     'X=0; [ "$X" = 1 ] && echo on; echo ok'
c e_or_colon     'X=0; if true; then [ "$X" = 1 ] && echo on || :; fi; echo ok'
c e_not_stmt     '! false; echo ok'
c e_not_true     '! true; echo ok'
c e_func_end     'X=0; f() { [ "$X" = 1 ] && echo on; }; f; echo ok'
c e_cmdsub_false 'X=`false`; echo ok'
c e_cmdsub_pipe  'X=`false | tail -1`; echo ok'
c e_expr_zero    'X=`expr 1 - 1`; echo ok'
c e_grep_nomatch 'X=`grep zzz f1`; echo ok'
c e_head_nofile  'X=`head -1 /nonexistent 2>/dev/null`; echo ok'
c e_pipe_first   'false | cat; echo ok'
c e_subshell     '( false ); echo ok'
c e_dot_missing  '. ./nonexistent 2>/dev/null || :; echo ok'
c e_cd_fail      'cd /nonexistent 2>/dev/null || :; echo ok'
c u_unset        'echo $NOPE'
c u_at_empty     'set --; for a in "$@"; do :; done; echo ok'
c u_at_guard     'set --; for a in ${1+"$@"}; do :; done; echo ok'
c u_star_empty   'set --; x="$*"; echo ok'
c u_default      'echo ${NOPE:-dflt}'
c u_empty_redir  'F=; X=`wc -c < "$F" 2>/dev/null` || :; echo ok'

# shell syntax and builtins
x s_dollar_paren   'echo $(echo a)'
x s_nested_bt      'echo `echo \`echo a\``'
x s_arith          'n=1; echo $((n + 1))'
x s_arith_octal    'echo $((010 + 1))'
x s_arith_hex      'echo $((0x10))'
x s_len            'A=abcd; echo ${#A}'
x s_strip          'A=a/b/c.sh; echo ${A##*/} ${A%/*} ${A%.sh} ${A#a/}'
x s_subst          'A=abc; echo ${A/b/x}'
x s_substr         'A=abc; echo ${A:1:1}'
x s_ansi_c         "echo \$'a\\tb'"
x s_herestring     'cat <<< hi'
x s_heredoc_tab    'cat <<-E
	tabbed
	E'
x s_dbl_bracket    '[[ a = a ]] && echo yes'
x s_eqeq           '[ a == a ] && echo yes'
x s_local          'f() { local v=1; echo $v; }; f'
x s_typeset        'typeset -i n=3; echo $n'
x s_function_kw    'function f { echo fk; }; f'
x s_let            'let n=2+3; echo $n'
x s_dparen         'n=1; (( n == 1 )) && echo yes'
x s_dollar_lt      'echo $(< fk)'
x s_print          'print -r "a\nb"'
x s_whence         'whence sh'
x s_type           'type sh'
x s_command_v      'command -v sh'
x s_pipefail       'set -o pipefail && echo yes'
x s_amp_redir      'echo x &> /dev/null && echo yes'
x s_brace_exp      'echo {a,b}'
x s_case_paren     'echo $(case a in (a) echo y;; esac)'
x s_case_bare      'echo $(case a in a) echo y;; esac)'
x s_case_class     'case a1 in [[:alpha:]]*) echo posix;; *) echo no;; esac'
x s_case_caret     'case b in [^a]) echo caret;; *) echo no;; esac'
x s_pipe_var       'X=1; echo a | while read l; do X=2; done; echo $X'
x s_pipe_read      'echo val | read V; echo "[${V:-}]"'
x s_read_r         'echo "a\\b" | { read -r v; echo "$v"; }'
x s_read_ifs       'echo " a  b " | { read v; echo "[$v]"; }'
x s_random         '[ -n "${RANDOM:-}" ] && echo has-random'
x s_ppid           '[ -n "${PPID:-}" ] && echo has-ppid'
x s_lineno         'echo ${LINENO:-none}'
x s_trap_exit      'trap "echo bye" EXIT; :'
x s_trap_0         'trap "echo bye" 0; :'
x s_getopts        'set -- -a; while getopts a o; do echo $o; done'
x s_kill0          'kill -0 $$ && echo yes'
x s_sleep_frac     'sleep 0.1 && echo yes'
x s_test_nt        '[ f1 -nt fe ] || [ fe -nt f1 ] || echo same; echo done'
x s_test_L         '[ -L f1 ]; echo $?'
x s_test_h         '[ -h f1 ]; echo $?'
x s_test_s         '[ -s fe ]; echo $?'
x s_test_space_num '[ " 5" -eq 5 ] && echo same'

# echo
x echo_bs_n   'echo "a\nb"'
x echo_bs_t   'echo "a\tb" | sed -n l'
x echo_bs_c   'echo "a\cb"; echo z'
x echo_bs_bs  'echo "a\\\\b"'
x echo_bs_1   'echo "s/\(a\)/\1/"'
x echo_dash_n 'echo -n x; echo y'
x echo_dash_e 'echo -e "a"'
x echo_dash_E 'echo -E "a"'
x printf_cmd  'printf "%s-%d\n" a 5'

# sed
x sed_n_p        'sed -n "2p" f1'
x sed_group      'sed -n "s/^\([a-z]*\)[0-9] .*/\1/p" f1'
x sed_multi_e    'sed -e "s/a/A/" -e "s/b/B/" f1 | head -1'
x sed_semicolon  'sed "s/a/A/;s/b/B/" f1 | head -1'
x sed_amp        'echo ab | sed "s/b/[&]/"'
x sed_g          'echo aaa | sed "s/a/b/g"'
x sed_last       'sed -n "\$p" f1'
x sed_range      'sed -n "1,2p" f1 | wc -l'
x sed_interval   'echo aaa | sed -n "s/a\{2\}/X/p"'
x sed_plus       'echo aaa | sed "s/a\+/X/"'
x sed_question   'echo ab | sed "s/ax\?b/X/"'
x sed_alt        'echo ab | sed "s/a\|b/X/g"'
x sed_class      'echo "a1 b" | sed "s/[[:digit:]]/D/; s/[[:space:]]/_/"'
x sed_tab_esc    'sed "s/\t/<T>/" ft'
x sed_tab_lit    'sed "s/	/<T>/" ft'
x sed_E          'echo ab | sed -E "s/(a)/<\1>/"'
x sed_r          'echo ab | sed -r "s/(a)/<\1>/"'
x sed_i          'cp fk fk2 && sed -i "s/v/w/" fk2 && cat fk2'
x sed_i_bak      'cp fk fk3 && sed -i.bak "s/v/w/" fk3 && cat fk3'
x sed_I          'echo ABC | sed "s/abc/x/I"'
x sed_y          'echo abc | sed "y/abc/xyz/"'
x sed_a          'echo a | sed "a\\
added"'
x sed_l          'sed -n l ft'
x sed_join       'sed -e ":a" -e "N" -e "s/\n/~/" -e "ta" f1'
x sed_q          'sed 1q f1'
x sed_nofile     'sed -n p /nonexistent; echo rc=$?'

# grep
x grep_q      'grep -q b f1 && echo yes'
x grep_v      'grep -v b f1 | wc -l'
x grep_c      'grep -c " " f1'
x grep_e2     'grep -e a -e z f1 | wc -l'
x grep_E      'grep -E "a|z" f1 | wc -l'
x grep_egrep  'egrep "a|z" f1 | wc -l'
x grep_bs_pipe 'grep "a\|z" f1 | wc -l'
x grep_F      'grep -F "a b" f1'
x grep_i      'grep -i "LINE" f1'
x grep_x      'grep -x "k=v" fk'
x grep_w      'grep -w "line" f1'
x grep_o      'grep -o "y2" f1'
x grep_n      'grep -n three f1'
x grep_l      'grep -l b f1 fk'
x grep_h      'grep -h b f1 fk'
x grep_s      'grep -s b /nonexistent; echo rc=$?'
x grep_r      'grep -r g d | wc -l'
x grep_class  'grep "[[:digit:]]" f1'
x grep_plus   'grep "x1\+" f1'
x grep_interval 'grep "x\{1\}1" f1'
x grep_nomatch 'grep zzz f1; echo rc=$?'
x grep_nofile 'grep a /nonexistent; echo rc=$?'

# awk
x awk_F        'awk -F= "{print \$2}" fk'
x awk_v        'awk -v n=5 "BEGIN{print n+1}"'
x awk_printf   'awk "BEGIN{printf \"%05.1f|%x|%s\n\", 3.14159, 255, \"s\"}"'
x awk_funcs    'awk "BEGIN{s=\"Hello\"; print length(s), substr(s,2,3), index(s,\"l\"), tolower(s), toupper(s)}"'
x awk_sub      'echo aaa | awk "{gsub(/a/,\"b\"); sub(/b/,\"c\"); print}"'
x awk_split    'awk "BEGIN{n=split(\"a:b:c\",x,\":\"); print n, x[3]}"'
x awk_match    'awk "BEGIN{print match(\"xxab\",/ab/), RSTART, RLENGTH}"'
x awk_nr_end   'awk "NR==2{print \$1} END{print NR}" f1'
x awk_int      'awk "BEGIN{print int(7/2), 7%3, 2^10}"'
x awk_hex_in   'awk "BEGIN{print 0x10+0}"'
x awk_strtonum 'awk "BEGIN{print strtonum(\"0x10\")}"'
x awk_environ  'A=env1 awk "BEGIN{print ENVIRON[\"A\"]}"'
x awk_getline  'awk "BEGIN{while ((getline l < \"fk\") > 0) print l}"'
x awk_system   'awk "BEGIN{system(\"echo sys\")}"'
x awk_dyn_re   'awk -v r="^k" "\$0 ~ r {print \"m\"}" fk'
x awk_nextfile 'awk "{print; nextfile}" f1 fk'
x awk_length0  'echo abc | awk "{print length}"'

# expr, wc, head, tail, basename, dirname
x expr_arith  'expr 7 \* 6'
x expr_match  'expr "abc123" : "[a-z]*\([0-9]*\)"'
x expr_len    'expr "abc" : ".*"'
x expr_length 'expr length abc'
x expr_substr 'expr substr abcd 2 2'
x expr_cmp    'expr 10 \> 9'
x expr_zero   'expr 1 - 1; echo rc=$?'
x wc_c        'wc -c < f1'
x wc_l        'wc -l < f1'
x wc_file     'wc -l f1'
x head_1      'head -1 f1'
x head_n      'head -n 2 f1 | wc -l'
x head_c      'head -c 3 f1'
x tail_1      'tail -1 f1'
x tail_n      'tail -n 1 f1'
x tail_plus   'tail +2 f1 | head -1'
x tail_n_plus 'tail -n +2 f1 | head -1'
x tail_c      'tail -c 4 f1'
x basename_1  'basename /a/b/c.sh'
x basename_sfx 'basename /a/b/c.sh .sh'
x dirname_1   'dirname /a/b/c.sh'

# files
x ls_1        'ls -1 d'
x ls_l_fields 'ls -l f1 | awk "{print NF}"'
x ls_L        'ln -s f1 lnk 2>/dev/null; ls -lL lnk | awk "{print \$5}"'
x find_name   'find d -name "*.txt"'
x find_type   'find d -type f | wc -l'
x find_maxdepth 'find d -maxdepth 1 -type f'
x find_newer  'find d -newer f1 -type f | wc -l'
x find_exec   'find d -name "*.sh" -exec echo got {} \;'
x cp_p        'cp -p f1 f1p && echo yes'
x cp_R        'cp -R d d2 && ls d2/e'
x mv_dir      'mkdir -p m1 && mv m1 m2 && echo yes'
x mkdir_p     'mkdir -p p/q/r && echo yes'
x chmod_x     'chmod +x fe && [ -x fe ] && echo yes'
x touch_new   'touch tn && [ -f tn ] && echo yes'
x cat_dash    'echo in | cat - fk'
x date_s      'date +%s | wc -c'
x date_fmt    'date "+%Y-%m-%d" | wc -c'
x uname_a     'uname -a | wc -w'
x sync_cmd    'sync && echo yes'

# programs present: path and size
for t in sh ksh sed grep egrep fgrep awk expr head tail wc cat ls cp mv rm ln mkdir rmdir chmod touch find \
         basename dirname date sleep sync kill test echo printf tr cmp diff cut sort uniq seq tee xargs od \
         strings cksum md5 stat readlink mktemp which id env uname gzip tar dd hexdump more less \
         mount slay pidin on use sloginfo waitfor getconf; do
    p=`command -v $t 2>/dev/null` || p=
    if [ -z "$p" ]; then echo "has_$t|1|"; continue; fi
    case "$p" in
        /*) sz=`ls -lL "$p" 2>/dev/null | awk '{print $5}'`; echo "has_$t|0|$p $sz" ;;
        *) echo "has_$t|0|builtin" ;;
    esac
done
cd /tmp
rm -rf $W
echo "probe_end|0|"
