# A stand-in for the head unit's shell, for tests/unit_sim/run.sh.
#
# QNX 6.5's /bin/sh is "PD KSH v5.2.14 99/07/13.2". This builds the same
# upstream source, unpatched: Debian's later pdksh packages, mksh, dash and
# ksh93 all changed how "set -e" treats a failed "[ test ] && cmd", and an
# installer that passes there has stopped on real units four times.
# The commands a unit lacks are removed, so a script that needs them fails.
FROM debian/eol:squeeze
RUN apt-get -qq update && apt-get -qq install -y --force-yes gcc make libc6-dev wget >/dev/null
RUN cd /tmp && wget -q http://archive.debian.org/debian/pool/main/p/pdksh/pdksh_5.2.14.orig.tar.gz \
 && echo "ab15bcdd50f291edc632bca351b2edce5405d4f2ce3854d3d548d721ab9bbfa6  pdksh_5.2.14.orig.tar.gz" | sha256sum -c - \
 && tar xzf pdksh_5.2.14.orig.tar.gz && cd pdksh-5.2.14 \
 && sed -i "s/sort +2n +0n/sort -k3n -k1n/" siglist.sh \
 && ./configure >/dev/null && make >/dev/null 2>&1 && cp ksh /bin/unit-ksh
# The harness keeps its own copies; the scripts under test must not find them.
RUN mkdir /simtools && cp /usr/bin/sort /usr/bin/diff /usr/bin/cmp /usr/bin/cut /usr/bin/tr /usr/bin/md5sum /usr/bin/printf /simtools/ \
 && cp /bin/unit-ksh /bin/ksh && cp /bin/unit-ksh /bin/sh.new && mv -f /bin/sh.new /bin/sh \
 && rm -f /usr/bin/printf /usr/bin/tr /usr/bin/cmp /usr/bin/diff /usr/bin/cut /usr/bin/sort /usr/bin/seq \
          /usr/bin/stat /usr/bin/readlink /bin/readlink /bin/mktemp /usr/bin/mktemp /bin/bash /bin/dash
