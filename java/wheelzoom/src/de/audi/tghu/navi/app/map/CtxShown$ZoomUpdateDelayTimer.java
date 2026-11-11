package de.audi.tghu.navi.app.map;

import java.lang.reflect.Method;

import de.audi.atip.timer.Timer;
import de.audi.atip.timer.TimerListener;
import local.clustermap.WheelZoom;

/*
 * mib-cluster-map: a replacement, written for this project, of the zoom timer
 * the stock navigation map uses on MHI2_ER_AU57x_K3663 (MU1425), loaded ahead
 * of lsd.jxe from /eso/hmi/lsd/jars/ClusterMapWheelZoom.jar.
 *
 * It keeps the stock class's name, methods and behaviour, so the stock
 * CtxShown and CtxMapInKombi that create and call it work unchanged, and adds
 * one thing: a roller step on the cockpit's map (CtxMapInKombi) goes to the
 * CarPlay map while that covers it (WheelZoom).
 *
 * It needs no package access in either direction, so it does not depend on
 * J9 counting a class from a jar as part of lsd.jxe's package:
 *  - everything the stock classes call here is public;
 *  - everything this calls in them goes through reflection with
 *    setAccessible, as luka-dev's CarplayTouchpadMIB does on this unit, and
 *    the stock classes are never named in the bytecode except in the
 *    constructor's descriptor, which J9 does not check for access.
 * A failed call is logged (WheelZoom) and skipped: the map then does not
 * zoom, but the navigation keeps running.
 *
 * Only for this one HMI build: the installer checks lsd.jxe's size first.
 * tests/wheelzoom_check.sh compares this class with the stock one, and
 * tests/wheelzoom_logic_test.sh runs it against stand-ins.
 */
public final class CtxShown$ZoomUpdateDelayTimer implements TimerListener {
    private static final String KOMBI_MAP = "de.audi.tghu.navi.app.map.CtxMapInKombi";
    private static final Class[] NONE = new Class[0];
    private static final Class[] ONE_INT = new Class[] {Integer.TYPE};
    private static final Object[] NO_ARGS = new Object[0];

    private final Timer mTimer;
    private int mDelayedZoomIndex;
    private boolean mZoomUpdateTemporarilyDisabled = false;
    /* The CtxShown (or CtxMapInKombi) this timer belongs to. */
    private final Object ctx;
    private final boolean kombi;
    private Method getZoomList, getRequestedZoomListIndex, setMagnificationDisplay,
        setZoomIndexOnMap, getMVRequestControl, setZoomLevel;

    public CtxShown$ZoomUpdateDelayTimer(CtxShown ctxShown) {
        this.ctx = ctxShown;
        // Through Object: javac would name CtxShown as the owner of getClass().
        Object o = ctxShown;
        this.kombi = o != null && o.getClass().getName().equals(KOMBI_MAP);
        // 150 ms, as the stock class has it. Timer refuses 0 with an
        // IllegalArgumentException, which stops the navigation loading at 11%:
        // jxe2jar's older conversion of MU1425 shows a broken "ldc_w int 0"
        // here for the stock "ldc2_w 150L". The stock class never starts this
        // timer, so any delay above 0 behaves the same.
        this.mTimer = new Timer("ZoomUpdateDelayTimer", 150L, true, this);
    }

    /* n: signed roller steps, added to the index into the map's zoom list. */
    public void restart(int n) {
        if (this.kombi && WheelZoom.forward(n)) {
            return;
        }
        this.mDelayedZoomIndex += n;
        if (this.mDelayedZoomIndex < 0) {
            this.mDelayedZoomIndex = 0;
        }
        Object zoomList = call(this.ctx, "getZoomList", NONE, NO_ARGS);
        if (zoomList instanceof float[]) {
            int length = ((float[]) zoomList).length;
            if (this.mDelayedZoomIndex >= length && length > 0) {
                this.mDelayedZoomIndex = length - 1;
            }
        }
        call(this.ctx, "setMagnificationDisplay", ONE_INT, intArg(this.mDelayedZoomIndex));
        this.mZoomUpdateTemporarilyDisabled = true;
        this.fireTimer(this.mTimer);
    }

    private void cancel() {
        if (this.mZoomUpdateTemporarilyDisabled) {
            this.mZoomUpdateTemporarilyDisabled = false;
            if (this.mDelayedZoomIndex != requestedIndex()) {
                Object control = call(this.ctx, "getMVRequestControl", NONE, NO_ARGS);
                if (control != null) {
                    call(control, "setZoomLevel", ONE_INT, intArg(this.mDelayedZoomIndex));
                }
            }
        }
        this.mTimer.cancel();
    }

    public void fireTimer(Timer timer) {
        this.mZoomUpdateTemporarilyDisabled = false;
        if (this.mDelayedZoomIndex != requestedIndex()) {
            call(this.ctx, "setZoomIndexOnMap", ONE_INT, intArg(this.mDelayedZoomIndex));
        }
    }

    public void cancelTimer(Timer timer) {
    }

    public boolean isTemporarilyDisabled() {
        return this.mZoomUpdateTemporarilyDisabled;
    }

    public void setZoomIndex(int n) {
        this.mDelayedZoomIndex = n < 0 ? 0 : n;
    }

    /* Called by CtxShown as the compiler named it for the original inner class. */
    public static void access$000(CtxShown$ZoomUpdateDelayTimer timer) {
        timer.cancel();
    }

    private int requestedIndex() {
        Object r = call(this.ctx, "getRequestedZoomListIndex", NONE, NO_ARGS);
        return r instanceof Integer ? ((Integer) r).intValue() : -1;
    }

    private static Object[] intArg(int n) {
        return new Object[] {new Integer(n)};
    }

    /* A method of target's class or its superclasses, whatever its access,
     * looked up once per name and kept. Virtual: an override in
     * CtxMapInKombi is the one that runs, as with a direct call. */
    private Object call(Object target, String name, Class[] types, Object[] args) {
        if (target == null) {
            return null;
        }
        try {
            Method m = cached(name);
            if (m == null) {
                for (Class c = target.getClass(); c != null && m == null; c = c.getSuperclass()) {
                    try {
                        m = c.getDeclaredMethod(name, types);
                    } catch (NoSuchMethodException e) {
                        m = null;
                    }
                }
                if (m == null) {
                    WheelZoom.note("stock method not found: ", name);
                    return null;
                }
                m.setAccessible(true);
                keep(name, m);
            }
            return m.invoke(target, args);
        } catch (Throwable t) {
            WheelZoom.note("stock call failed: ", new StringBuffer(name).append(' ').append(String.valueOf(t)).toString());
            return null;
        }
    }

    private Method cached(String name) {
        if (name.equals("getZoomList")) return this.getZoomList;
        if (name.equals("getRequestedZoomListIndex")) return this.getRequestedZoomListIndex;
        if (name.equals("setMagnificationDisplay")) return this.setMagnificationDisplay;
        if (name.equals("setZoomIndexOnMap")) return this.setZoomIndexOnMap;
        if (name.equals("getMVRequestControl")) return this.getMVRequestControl;
        if (name.equals("setZoomLevel")) return this.setZoomLevel;
        return null;
    }

    private void keep(String name, Method m) {
        if (name.equals("getZoomList")) this.getZoomList = m;
        else if (name.equals("getRequestedZoomListIndex")) this.getRequestedZoomListIndex = m;
        else if (name.equals("setMagnificationDisplay")) this.setMagnificationDisplay = m;
        else if (name.equals("setZoomIndexOnMap")) this.setZoomIndexOnMap = m;
        else if (name.equals("getMVRequestControl")) this.getMVRequestControl = m;
        else if (name.equals("setZoomLevel")) this.setZoomLevel = m;
    }
}
