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
        setZoomIndexOnMap, getMVRequestControl, setZoomLevel, getGuiInterface,
        getKombiMagnificationValue, getKombiMagnificationMinimum,
        getKombiMagnificationMaximum, setKombiMagnification;

    /*
     * Room for the roller (#171, #128). The stock GUIInterface passes a
     * cockpit roller step on only as far as the cockpit map's magnification
     * (the RangeModel of control -240844800) can still move: at its maximum
     * "out" steps are dropped, at its minimum "in" steps, before this class
     * is called. While CarPlay has the cockpit the stock map doesn't zoom, so
     * that value stays where the Audi map was, and if that was an end of its
     * zoom list one direction never reached CarPlay. So, only on the cockpit
     * map and only while the steps go to CarPlay, a check every second puts
     * the value in the middle of its range when it sits at an end, and puts
     * the saved value back once CarPlay has left. setKombiMagnification only
     * sets that value: the stock map doesn't zoom and no scale is shown.
     */
    private Timer roomTimer;
    private boolean roomMoved;
    private int roomSaved;
    private Object gui;

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
        if (this.kombi) {
            // Never let this stop the navigation loading: without it the
            // roller works as before, only one direction may be blocked.
            try {
                this.roomTimer = new Timer("ClusterMapZoomRoom", 1000L, false, this);
                this.roomTimer.start();
            } catch (Throwable t) {
                this.roomTimer = null;
                WheelZoom.note("zoom room timer not started: ", String.valueOf(t));
            }
        }
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
        if (timer != null && timer == this.roomTimer) {
            keepRoom();
            return;
        }
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

    /* See roomTimer. Any failure leaves things as they are. */
    private void keepRoom() {
        try {
            boolean on = WheelZoom.onCockpit();
            if (!on && !this.roomMoved) {
                return;
            }
            Object g = guiInterface();
            if (g == null) {
                return;
            }
            if (!on) {
                this.roomMoved = false;
                call(g, "setKombiMagnification", ONE_INT, intArg(this.roomSaved));
                WheelZoom.note("zoom room: restored ", String.valueOf(this.roomSaved));
                return;
            }
            int value = intOf(call(g, "getKombiMagnificationValue", NONE, NO_ARGS));
            int min = intOf(call(g, "getKombiMagnificationMinimum", NONE, NO_ARGS));
            int max = intOf(call(g, "getKombiMagnificationMaximum", NONE, NO_ARGS));
            if (value == Integer.MIN_VALUE || min == Integer.MIN_VALUE || max == Integer.MIN_VALUE
                    || max - min < 2 || (value > min && value < max)) {
                return;
            }
            if (!this.roomMoved) {
                this.roomMoved = true;
                this.roomSaved = value;
            }
            int mid = min + (max - min) / 2;
            call(g, "setKombiMagnification", ONE_INT, intArg(mid));
            WheelZoom.note("zoom room: ", new StringBuffer().append(value).append(" -> ").append(mid)
                .append(" (").append(min).append("..").append(max).append(')').toString());
        } catch (Throwable t) {
            WheelZoom.note("zoom room failed: ", String.valueOf(t));
        }
    }

    /* naviMap is a protected field of the stock Context, reached through
     * reflection like the methods, then Map.getGuiInterface(). */
    private Object guiInterface() {
        if (this.gui != null) {
            return this.gui;
        }
        Object map = null;
        for (Class c = this.ctx.getClass(); c != null && map == null; c = c.getSuperclass()) {
            try {
                java.lang.reflect.Field f = c.getDeclaredField("naviMap");
                f.setAccessible(true);
                map = f.get(this.ctx);
                if (map == null) {
                    return null; // not set yet: try again on the next tick
                }
            } catch (NoSuchFieldException e) {
                map = null;
            } catch (Throwable t) {
                WheelZoom.note("stock field failed: naviMap ", String.valueOf(t));
                return null;
            }
        }
        if (map == null) {
            WheelZoom.note("stock field not found: ", "naviMap");
            return null;
        }
        this.gui = call(map, "getGuiInterface", NONE, NO_ARGS);
        return this.gui;
    }

    private static int intOf(Object r) {
        return r instanceof Integer ? ((Integer) r).intValue() : Integer.MIN_VALUE;
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
        if (name.equals("getGuiInterface")) return this.getGuiInterface;
        if (name.equals("getKombiMagnificationValue")) return this.getKombiMagnificationValue;
        if (name.equals("getKombiMagnificationMinimum")) return this.getKombiMagnificationMinimum;
        if (name.equals("getKombiMagnificationMaximum")) return this.getKombiMagnificationMaximum;
        if (name.equals("setKombiMagnification")) return this.setKombiMagnification;
        return null;
    }

    private void keep(String name, Method m) {
        if (name.equals("getZoomList")) this.getZoomList = m;
        else if (name.equals("getRequestedZoomListIndex")) this.getRequestedZoomListIndex = m;
        else if (name.equals("setMagnificationDisplay")) this.setMagnificationDisplay = m;
        else if (name.equals("setZoomIndexOnMap")) this.setZoomIndexOnMap = m;
        else if (name.equals("getMVRequestControl")) this.getMVRequestControl = m;
        else if (name.equals("setZoomLevel")) this.setZoomLevel = m;
        else if (name.equals("getGuiInterface")) this.getGuiInterface = m;
        else if (name.equals("getKombiMagnificationValue")) this.getKombiMagnificationValue = m;
        else if (name.equals("getKombiMagnificationMinimum")) this.getKombiMagnificationMinimum = m;
        else if (name.equals("getKombiMagnificationMaximum")) this.getKombiMagnificationMaximum = m;
        else if (name.equals("setKombiMagnification")) this.setKombiMagnification = m;
    }
}
