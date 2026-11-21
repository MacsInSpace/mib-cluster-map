package local.clustermap;

import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.lang.reflect.Method;

/**
 * mib-cluster-map: put the AU57x (A6/A7 C7.5, MOST) cockpit in its MAP view
 * while the CarPlay map is on it, whatever view it was in.
 *
 * The cockpit's navigation tab has views (stock ClusterViewMode, choice
 * model 51): 2 MAP and 3 KDK (route map) show the head unit's video,
 * 4 COMPASS does not. The player only replaces the MAP view's picture
 * (context 73). On an RS7 C7.5 (K3663, cluster variant MOST) the tab was on
 * COMPASS without a route and on KDK (context 75, 800x252) with one, and its
 * own menu had never been set to MAP, so the CarPlay map never showed:
 * nothing with the compass, a blank tab when the player pulled the cockpit
 * onto context 73 under the route layout. Choosing MAP in the cockpit's menu
 * would also do, but owners do not know that and it is lost to a reset; and
 * the stock MAP choice is refused outright on a unit not coded for a MOST
 * cluster (ClusterViewMode.setCurrentViewMode, SysConst 67).
 *
 * What this does, from a daemon thread polling once a second:
 *  - CarPlay map up (/tmp/mibr-carplay111.state "streaming" and
 *    carplay_cluster.sh running): remember the view, set model 51 to MAP and
 *    run the stock GfxStreamController.switchViewMode(MAP), which is what the
 *    stock MAP choice does after its coding check. Done again (at most every
 *    3 s, 30 times a session) if something puts the tab back.
 *  - CarPlay map gone for 4 s (the player has put the stock map back): the
 *    remembered view goes back through the stock validation
 *    (ClusterViewMode.getNewValidViewMode: KDK if a route runs, and so on).
 *
 * Also (filter): the cockpit's "graphics lost" report (GfxState 0) is passed
 * on as available while the CarPlay map is being swapped in or out. A guard
 * from the first theory on the RS7; that car never sent a 0, so it has not
 * been exercised.
 *
 * Every step goes to /tmp/clustermap-gfxstate.log. touch
 * /tmp/clustermap-gfxkeep-off stops both until the next boot. Stock classes
 * are reached by reflection only (as WheelZoom), Java 1.2 library only.
 */
public final class GfxKeep implements Runnable {
    private static final String STATE = "/tmp/mibr-carplay111.state";
    private static final String SUPERVISOR = "/tmp/carplay_cluster.pid";
    private static final String OFF = "/tmp/clustermap-gfxkeep-off";
    private static final String LOG = "/tmp/clustermap-gfxstate.log";
    private static final int LOG_MAX = 65536;
    private static final long GRACE_MS = 20000L;
    private static final long RESTORE_AFTER_MS = 4000L;
    private static final long REFORCE_EVERY_MS = 3000L;
    private static final int REFORCE_MAX = 30;
    private static final int MAP = 2;

    private static final Object LOCK = new Object();
    private static boolean announced;
    private static Thread worker;

    private boolean forcing;
    private int previous = -1;
    private long lastForce;
    private long offSince;
    private int reforces;

    private GfxKeep() {
    }

    /* Called for every GfxState report (UpdateGfxState); the first call, at
     * start-up, also starts the view thread. */
    public static int filter(int state) {
        try {
            startWorker();
            String why = null;
            if (state == 0 && !new File(OFF).exists()) {
                if (carplayOnCockpit()) {
                    why = "CarPlay map on the cockpit";
                } else if (stateChangedRecently()) {
                    why = "CarPlay map changed in the last 20 s";
                }
            }
            StringBuffer s = new StringBuffer(96);
            s.append(System.currentTimeMillis()).append(" cockpit graphics state=").append(state);
            if (why != null) {
                s.append(" -> passed on as 1 (").append(why).append(')');
            }
            logText(s.toString());
            return why != null ? 1 : state;
        } catch (Throwable t) {
            return state;
        }
    }

    private static void startWorker() {
        synchronized (LOCK) {
            if (worker != null) {
                return;
            }
            worker = new Thread(new GfxKeep(), "ClusterMapGfxKeep");
            worker.setDaemon(true);
            worker.setPriority(Thread.MIN_PRIORITY);
            worker.start();
        }
    }

    public void run() {
        try {
            Thread.sleep(5000L);
        } catch (Throwable ignored) {
        }
        logText(new StringBuffer(160).append(System.currentTimeMillis())
                .append(" cockpit map guard running (mib-cluster-map): cluster variant=")
                .append(sysConst(67)).append(" (1 = MOST), cluster map=").append(sysConst(105))
                .append(", view=").append(viewName(getView())).toString());
        while (true) {
            try {
                Thread.sleep(1000L);
                step();
            } catch (Throwable t) {
                note("step failed: ", t);
                try {
                    Thread.sleep(5000L);
                } catch (Throwable ignored) {
                }
            }
        }
    }

    private void step() throws Exception {
        long now = System.currentTimeMillis();
        boolean on = !new File(OFF).exists() && carplayOnCockpit();
        if (on) {
            offSince = 0;
            if (!forcing) {
                forcing = true;
                reforces = 0;
                previous = getView();
                log(now, "CarPlay map up: view was " + viewName(previous) + ", cluster to MAP");
                force();
                lastForce = now;
            } else if (now - lastForce >= REFORCE_EVERY_MS && reforces < REFORCE_MAX && !onMap()) {
                reforces++;
                log(now, "cluster left MAP (view " + viewName(getView()) + "): back to MAP, " + reforces + " of " + REFORCE_MAX);
                force();
                lastForce = now;
            }
            return;
        }
        if (!forcing) {
            return;
        }
        if (offSince == 0) {
            offSince = now;
            return;
        }
        if (now - offSince < RESTORE_AFTER_MS) {
            return;
        }
        forcing = false;
        offSince = 0;
        restore(now);
    }

    private void force() throws Exception {
        setView(MAP);
        streetView(false);
        switchViewMode(MAP);
        logStatus();
    }

    private void restore(long now) throws Exception {
        int want = previous >= 0 ? previous : 4;
        setView(want);
        int valid = want;
        try {
            Object cvm = call(call(nav(), "getClusterService"), "getClusterViewMode");
            valid = ((Integer) call(cvm, "getNewValidViewMode")).intValue();
        } catch (Throwable t) {
            note("no stock validation, using the remembered view: ", t);
        }
        if (valid != want) {
            setView(valid);
        }
        streetView(valid == 3);
        switchViewMode(valid);
        log(now, "CarPlay map gone: cluster back to " + viewName(valid) + " (was " + viewName(want) + ")");
        logStatus();
    }

    /* ---- stock access, by reflection ---------------------------------- */

    private static Object nav() throws Exception {
        return Class.forName("de.audi.tghu.navi.app.Navigation")
                .getMethod("getInstance", new Class[0]).invoke(null, new Object[0]);
    }

    private static Object call(Object o, String name) throws Exception {
        return o.getClass().getMethod(name, new Class[0]).invoke(o, new Object[0]);
    }

    private static Object viewModel() throws Exception {
        Object fw = Class.forName("de.audi.tghu.navi.app.Navigation")
                .getMethod("getFramework", new Class[0]).invoke(null, new Object[0]);
        Object sys = Class.forName("de.audi.atip.base.IFrameworkAccess")
                .getMethod("getSysApp", new Class[0]).invoke(fw, new Object[0]);
        return Class.forName("de.audi.atip.sysapp.ISysApp")
                .getMethod("getChoiceModelApp", new Class[] {Integer.TYPE})
                .invoke(sys, new Object[] {new Integer(51)});
    }

    private static int getView() {
        try {
            Object m = viewModel();
            return ((Integer) Class.forName("de.audi.atip.hmi.modelaccess.ChoiceModelApp")
                    .getMethod("getValue", new Class[0]).invoke(m, new Object[0])).intValue();
        } catch (Throwable t) {
            return -1;
        }
    }

    private static void setView(int v) throws Exception {
        Object m = viewModel();
        Class.forName("de.audi.atip.hmi.modelaccess.ChoiceModelApp")
                .getMethod("setValue", new Class[] {Integer.TYPE}).invoke(m, new Object[] {new Integer(v)});
    }

    private static void switchViewMode(int v) throws Exception {
        Object g = call(nav(), "getGfxStreamController");
        g.getClass().getMethod("switchViewMode", new Class[] {Integer.TYPE}).invoke(g, new Object[] {new Integer(v)});
    }

    private static String status() {
        try {
            return (String) call(call(nav(), "getGfxStreamController"), "printGfxStreamStatus");
        } catch (Throwable t) {
            return "";
        }
    }

    private static boolean onMap() {
        return getView() == MAP && status().indexOf("currentViewMode = MAP") >= 0;
    }

    private static void streetView(boolean on) {
        try {
            Object ri = call(call(call(nav(), "getMapInterface"), "getMap"), "getRouteInfo");
            ri.getClass().getMethod("setKombiStreetViewSelected", new Class[] {Boolean.TYPE})
                    .invoke(ri, new Object[] {new Boolean(on)});
        } catch (Throwable ignored) {
        }
    }

    private static int sysConst(int i) {
        try {
            return ((Integer) Class.forName("de.audi.atip.sysapp.SysConst")
                    .getMethod("getSysConst", new Class[] {Integer.TYPE})
                    .invoke(null, new Object[] {new Integer(i)})).intValue();
        } catch (Throwable t) {
            return -1;
        }
    }

    private static String viewName(int v) {
        switch (v) {
            case 0: return "WAITING";
            case 1: return "RGI";
            case 2: return "MAP";
            case 3: return "KDK";
            case 4: return "COMPASS";
            default: return String.valueOf(v);
        }
    }

    /* ---- CarPlay state files ------------------------------------------- */

    private static boolean carplayOnCockpit() {
        if (!new File(SUPERVISOR).exists()) {
            return false;
        }
        FileInputStream in = null;
        try {
            byte[] b = new byte[16];
            in = new FileInputStream(STATE);
            int n = in.read(b);
            return n >= 9 && new String(b, 0, 9).equals("streaming");
        } catch (Throwable t) {
            return false;
        } finally {
            if (in != null) {
                try {
                    in.close();
                } catch (Throwable ignored) {
                }
            }
        }
    }

    private static boolean stateChangedRecently() {
        File f = new File(STATE);
        if (!f.exists()) {
            return false;
        }
        long d = System.currentTimeMillis() - f.lastModified();
        if (d < 0) {
            d = -d;
        }
        return d < GRACE_MS;
    }

    /* ---- log ------------------------------------------------------------ */

    private static void logStatus() {
        String s = status().replace('\n', ' ').replace('\r', ' ').trim();
        logText(new StringBuffer(s.length() + 32).append(System.currentTimeMillis())
                .append(" view=").append(viewName(getView())).append(' ').append(s).toString());
    }

    private static void log(long now, String what) {
        logText(new StringBuffer(what.length() + 24).append(now).append(' ').append(what).toString());
    }

    private static void note(String what, Throwable t) {
        Throwable c = t;
        if (t instanceof java.lang.reflect.InvocationTargetException) {
            Throwable x = ((java.lang.reflect.InvocationTargetException) t).getTargetException();
            if (x != null) {
                c = x;
            }
        }
        logText(new StringBuffer(96).append(System.currentTimeMillis()).append(' ').append(what)
                .append(String.valueOf(c)).toString());
    }

    private static void logText(String line) {
        FileOutputStream out = null;
        try {
            synchronized (LOCK) {
                File f = new File(LOG);
                StringBuffer s = new StringBuffer(line.length() + 64);
                if (!announced) {
                    announced = true;
                    s.append("cockpit graphics guard active (mib-cluster-map)\n");
                }
                s.append(line).append('\n');
                out = new FileOutputStream(LOG, f.length() < LOG_MAX);
                out.write(s.toString().getBytes());
            }
        } catch (Throwable ignored) {
        } finally {
            if (out != null) {
                try {
                    out.close();
                } catch (Throwable ignored) {
                }
            }
        }
    }
}
