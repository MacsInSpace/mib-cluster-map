#!/bin/bash
# The cockpit map view watcher against stand-ins for the stock navigation
# classes (tests/gfxkeep_fakes), loaded by a different class loader from the
# jar, as J9 loads the jar apart from lsd.jxe. Plays a CarPlay session with an
# Audi route running (nav tab on KDK): the tab must go to MAP when the CarPlay
# map is up, back to MAP if something moves it, and back to KDK after the
# phone is gone. Uses the unit's /tmp file names on the host; takes ~25 s.
#
#   tests/gfxkeep_logic_test.sh [ClusterMapGfxKeep.jar]
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
JAR=${1:-"$ROOT/build/ClusterMapGfxKeep.jar"}
[ -r "$JAR" ] || "$ROOT/java/gfxkeep/build.sh" "$ROOT/build"
T=$(mktemp -d)
FILES="/tmp/mibr-carplay111.state /tmp/carplay_cluster.pid /tmp/clustermap-gfxstate.log /tmp/clustermap-gfxkeep-off"
for f in $FILES; do [ -e "$f" ] && mv "$f" "$T/$(basename "$f").saved"; done
restore() {
    rm -f $FILES
    for f in $FILES; do [ -e "$T/$(basename "$f").saved" ] && mv "$T/$(basename "$f").saved" "$f"; done
    rm -rf "$T"
}
trap restore EXIT
mkdir -p "$T/fakes" "$T/run"
javac -nowarn -d "$T/fakes" $(find "$ROOT/tests/gfxkeep_fakes" -name '*.java')
cat > "$T/run/Run.java" <<'JAVA'
import java.io.*;
import java.lang.reflect.*;
import java.net.*;

public class Run {
    static void state(String s) throws Exception {
        FileOutputStream o = new FileOutputStream("/tmp/mibr-carplay111.state");
        o.write(s.getBytes());
        o.close();
    }

    public static void main(String[] a) throws Exception {
        URLClassLoader stock = new URLClassLoader(new URL[] {new File(a[0]).toURI().toURL()}, Run.class.getClassLoader().getParent());
        URLClassLoader jar = new URLClassLoader(new URL[] {new File(a[1]).toURI().toURL()}, stock) {
            protected Class<?> loadClass(String n, boolean r) throws ClassNotFoundException {
                synchronized (getClassLoadingLock(n)) {
                    Class<?> c = findLoadedClass(n);
                    if (c == null && (n.startsWith("local.") || n.endsWith(".UpdateGfxState"))) c = findClass(n);
                    return c != null ? c : super.loadClass(n, r);
                }
            }
        };
        Class<?> calls = stock.loadClass("de.audi.tghu.navi.app.Calls");
        StringBuffer log = (StringBuffer) calls.getField("LOG").get(null);
        Class<?> event = jar.loadClass("de.audi.tghu.navi.app.cluster.UpdateGfxState");
        if (event.getClassLoader() != jar) throw new IllegalStateException("UpdateGfxState not from the jar");
        Constructor<?> ec = event.getConstructor(int.class);
        Method gs = event.getMethod("getGfxState");
        String fail = "";
        // Start-up: the first report starts the watcher; no CarPlay, a 0 stays 0.
        if (((Integer) gs.invoke(ec.newInstance(1))).intValue() != 1) fail += "start-up 1 changed; ";
        if (((Integer) gs.invoke(ec.newInstance(0))).intValue() != 0) fail += "0 without CarPlay changed; ";
        Thread.sleep(7000);
        if (log.length() != 0) fail += "acted without CarPlay: " + log + "; ";
        // CarPlay map up with a route running (KDK).
        new FileOutputStream("/tmp/carplay_cluster.pid").close();
        state("streaming\n");
        Thread.sleep(2500);
        if (((Integer) gs.invoke(ec.newInstance(0))).intValue() != 1) fail += "0 during CarPlay not held back; ";
        // Something puts the tab back on the route map.
        calls.getField("view").setInt(null, 3);
        Thread.sleep(4500);
        // Phone unplugged: the supervisor ends, the state changes.
        state("stopped\n");
        new File("/tmp/carplay_cluster.pid").delete();
        Thread.sleep(7000);
        String want = "set(2) switch(2) set(2) switch(2) set(3) switch(3) ";
        System.out.println("calls: " + log);
        if (!log.toString().equals(want)) fail += "expected calls: " + want;
        if (!fail.isEmpty()) { System.out.println("FAIL  " + fail); System.exit(1); }
        System.out.println("GFXKEEP_LOGIC_OK");
    }
}
JAVA
javac -nowarn -d "$T/run" "$T/run/Run.java"
java -cp "$T/run" Run "$T/fakes" "$JAR"
echo "--- /tmp/clustermap-gfxstate.log"
cat /tmp/clustermap-gfxstate.log
