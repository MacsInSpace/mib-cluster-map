#!/bin/bash
# The wheel-zoom timer against stand-ins for the stock navigation classes,
# with the same access (package-private class and methods), loaded by a
# different class loader from the jar: a different runtime package, which is
# how J9 treats the jar and lsd.jxe. The stock zoom path must still work
# (no CarPlay stream on the host, so nothing is forwarded).
#
#   tests/wheelzoom_logic_test.sh [ClusterMapWheelZoom.jar]
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
JAR=${1:-"$ROOT/build/ClusterMapWheelZoom.jar"}
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/fakes"
javac --release 8 -nowarn -d "$T/fakes" $(find "$ROOT/tests/wheelzoom_fakes" -name '*.java')
cat > "$T/Run.java" <<'JAVA'
import java.lang.reflect.*;
import java.net.*;

public class Run {
    public static void main(String[] a) throws Exception {
        URLClassLoader stock = new URLClassLoader(new URL[] {new java.io.File(a[0]).toURI().toURL()}, ClassLoader.getPlatformClassLoader());
        // The jar's classes first, in a loader of their own (child-first).
        URLClassLoader jar = new URLClassLoader(new URL[] {new java.io.File(a[1]).toURI().toURL()}, stock) {
            protected Class<?> loadClass(String n, boolean r) throws ClassNotFoundException {
                synchronized (getClassLoadingLock(n)) {
                    Class<?> c = findLoadedClass(n);
                    if (c == null && (n.startsWith("local.") || n.endsWith("$ZoomUpdateDelayTimer"))) c = findClass(n);
                    return c != null ? c : super.loadClass(n, r);
                }
            }
        };
        Class<?> kombi = stock.loadClass("de.audi.tghu.navi.app.map.CtxMapInKombi");
        Constructor<?> kc = kombi.getDeclaredConstructor(); kc.setAccessible(true);
        Object ctx = kc.newInstance();
        Class<?> timer = jar.loadClass("de.audi.tghu.navi.app.map.CtxShown$ZoomUpdateDelayTimer");
        if (timer.getClassLoader() != jar) throw new IllegalStateException("timer not from the jar loader");
        Constructor<?> tc = timer.getDeclaredConstructors()[0]; tc.setAccessible(true);
        Object t = tc.newInstance(ctx);
        StringBuffer log = (StringBuffer) stock.loadClass("de.audi.tghu.navi.app.map.Calls").getField("LOG").get(null);
        String failed = "";
        try {
            timer.getMethod("restart", int.class).invoke(t, 2);
            timer.getMethod("restart", int.class).invoke(t, 9);
            timer.getMethod("restart", int.class).invoke(t, -1);
            timer.getMethod("setZoomIndex", int.class).invoke(t, 1);
            Method m = timer.getDeclaredMethod("access$000", timer); m.setAccessible(true);
            m.invoke(null, t);
            timer.getMethod("restart", int.class).invoke(t, 0);
        } catch (InvocationTargetException e) {
            failed = e.getCause().toString();
        } catch (Throwable e) {
            failed = e.toString();
        }
        System.out.println("calls: " + log);
        if (!failed.isEmpty()) { System.out.println("FAIL  " + failed); System.exit(1); }
        String want = "setMagnificationDisplay(2) kombi:setZoomIndexOnMap(2) "
            + "setMagnificationDisplay(4) kombi:setZoomIndexOnMap(4) "
            + "setMagnificationDisplay(3) kombi:setZoomIndexOnMap(3) "
            + "setMagnificationDisplay(1) kombi:setZoomIndexOnMap(1) ";
        if (!log.toString().equals(want)) { System.out.println("FAIL  expected: " + want); System.exit(1); }
        System.out.println("WHEELZOOM_LOGIC_OK");
    }
}
JAVA
java "$T/Run.java" "$T/fakes" "$JAR"
