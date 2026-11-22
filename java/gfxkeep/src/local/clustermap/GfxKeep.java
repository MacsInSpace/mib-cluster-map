package local.clustermap;

import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.lang.reflect.Array;
import java.lang.reflect.Field;
import java.lang.reflect.Method;

/**
 * mib-cluster-map:
 *  1. Put the AU57x (A6/A7/RS7 C7.5, MOST) cockpit in its MAP view while the
 *     CarPlay map is on it, whatever view it was in, and restore the previous
 *     view 4 s after CarPlay map streaming stops.
 *  2. Bridge CarPlay iAP2 route guidance (/tmp/clustermap-rgd.state, written
 *     by our ipod-drvr-iap2.so proxy) onto the AU57x ClusterService, KOMO
 *     (DSIKOMOView.setRouteInfoElement), and DDP2 HUD / cluster element bank
 *     (CombiElementBankDDP2 + CommandTypeInitialisationHUD frame 5 RGI_EXT),
 *     while keeping the cluster in VIEWMODE_MAP (2).
 *  3. When CarPlay route guidance is idle and a native Audi route is active,
 *     log any observed native short[] rgiString once per change to
 *     /tmp/clustermap-gfxstate.log for diagnostic verification.
 *
 * Every step goes to /tmp/clustermap-gfxstate.log. touch
 * /tmp/clustermap-gfxkeep-off stops both until the next boot. Stock classes
 * are reached by reflection only (as WheelZoom), Java 1.2 library only.
 */
public final class GfxKeep implements Runnable {
    private static final String STATE = "/tmp/mibr-carplay111.state";
    private static final String SUPERVISOR = "/tmp/carplay_cluster.pid";
    private static final String RGD_STATE = "/tmp/clustermap-rgd.state";
    private static final String RGD_OFF = "/tmp/clustermap-rgd.disabled";
    private static final String TELEMETRY_OFF = "/tmp/clustermap-telemetry.disabled";
    private static final String OFF = "/tmp/clustermap-gfxkeep-off";
    private static final String LOG = "/tmp/clustermap-gfxstate.log";
    private static final int LOG_MAX = 65536;
    private static final long GRACE_MS = 20000L;
    private static final long RESTORE_AFTER_MS = 4000L;
    private static final long REFORCE_EVERY_MS = 3000L;
    private static final long RGD_REFRESH_MS = 2500L;
    private static final long RGD_STALE_MS = 180000L;
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

    /* Route guidance bridge state */
    private boolean rgdActive;
    private int lastRgdSeq = -1;
    private int lastMainElem = -1;
    private int lastDir = -1;
    private int lastDistM = -1;
    private int lastBar = -2;
    private int lastDestDistM = -1;
    private long lastRemSec = -1L;
    private String lastTurnStreet = "";
    private String lastCurrentStreet = "";
    private String lastExitInfo = "";
    private long lastRgdPush;
    private long lastRgdDiagLog;
    private String lastNativeRgi = "";
    private final HudTelemetry telemetry = new HudTelemetry();

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
                Thread.sleep((forcing || rgdActive) ? 500L : 1000L);
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
        boolean disabled = new File(OFF).exists();
        boolean on = !disabled && carplayOnCockpit();
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
        } else if (forcing) {
            if (offSince == 0) {
                offSince = now;
            } else if (now - offSince >= RESTORE_AFTER_MS) {
                forcing = false;
                offSince = 0;
                restore(now);
            }
        }
        try {
            stepRgd(now, disabled);
        } catch (Throwable t) {
            note("rgd step failed: ", t);
        }
        try {
            Object cs = null;
            try {
                cs = call(nav(), "getClusterService");
            } catch (Throwable ignored) {
            }
            telemetry.step(now, cs, rgdActive, lastDistM, disabled || new File(TELEMETRY_OFF).exists());
        } catch (Throwable t) {
            note("telemetry step failed: ", t);
        }
    }

    private void force() throws Exception {
        try {
            Object cs = call(nav(), "getClusterService");
            if (cs != null) {
                try {
                    cs.getClass().getMethod("mostAvailable", new Class[] {Boolean.TYPE})
                            .invoke(cs, new Object[] {new Boolean(true)});
                } catch (Throwable ignored) {
                }
                try {
                    Object cil = call(cs, "getClusterInputListener");
                    if (cil != null) {
                        cil.getClass().getMethod("setFavoredViewMode", new Class[] {Integer.TYPE, Boolean.TYPE})
                                .invoke(cil, new Object[] {new Integer(MAP), new Boolean(false)});
                    }
                } catch (Throwable ignored) {
                }
            }
        } catch (Throwable ignored) {
        }
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
            Object cs = call(nav(), "getClusterService");
            Object cvm = call(cs, "getClusterViewMode");
            valid = ((Integer) call(cvm, "getNewValidViewMode")).intValue();
            try {
                Object cil = call(cs, "getClusterInputListener");
                if (cil != null) {
                    cil.getClass().getMethod("setFavoredViewMode", new Class[] {Integer.TYPE, Boolean.TYPE})
                            .invoke(cil, new Object[] {new Integer(valid), new Boolean(false)});
                }
            } catch (Throwable ignored) {
            }
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

    /* ---- CarPlay iAP2 -> AU57x HUD & KOMO Route Guidance Bridge -------- */

    private void stepRgd(long now, boolean disabled) throws Exception {
        File f = new File(RGD_STATE);
        if (disabled || new File(RGD_OFF).exists() || !f.exists()) {
            if (rgdActive) {
                stopRgd(now, "state file absent or disabled");
            } else {
                observeNativeRgi(now);
                if (now - lastRgdDiagLog >= 30000L) {
                    lastRgdDiagLog = now;
                    log(now, "RGD diag: stateFile=" + f.exists() + " carplay=" + carplayOnCockpit() + " view=" + viewName(getView()));
                }
            }
            return;
        }
        long age = now - f.lastModified();
        if (age > RGD_STALE_MS && !carplayOnCockpit()) {
            if (rgdActive) {
                stopRgd(now, "state stale and CarPlay stopped");
            }
            return;
        }
        String text = readFileText(f, 2048);
        if (text == null || text.length() == 0) {
            return;
        }
        int seq = parseIntProp(text, "seq", -1);
        int active = parseIntProp(text, "active", 0);
        int routeState = parseIntProp(text, "route_state", 0);
        if (active != 1) {
            if (rgdActive) {
                stopRgd(now, "route ended (route_state=" + routeState + ")");
            } else {
                observeNativeRgi(now);
                if (now - lastRgdDiagLog >= 30000L) {
                    lastRgdDiagLog = now;
                    log(now, "RGD diag: idle seq=" + seq + " active=" + active + " route_state=" + routeState
                            + " ageMs=" + age + " view=" + viewName(getView()));
                }
            }
            return;
        }

        int mType = parseIntProp(text, "maneuver_type", -1);
        int turnAngle = parseIntProp(text, "turn_angle", 1000);
        boolean anglePresent = parseIntProp(text, "angle_present", 0) == 1;
        int junctionType = parseIntProp(text, "junction_type", -1);
        int drivingSide = parseIntProp(text, "driving_side", -1);
        int distM = parseIntProp(text, "dist_m", 0);
        boolean distPresent = parseIntProp(text, "dist_present", 0) == 1;
        int stepDistM = parseIntProp(text, "step_dist_m", 0);
        int destDistM = parseIntProp(text, "dest_dist_m", 0);
        boolean destDistPresent = parseIntProp(text, "dest_dist_present", 0) == 1;
        long remSec = parseLongProp(text, "rem_sec", 0L);
        boolean remPresent = parseIntProp(text, "rem_present", 0) == 1;
        String currentRoad = parseStrProp(text, "current_road");
        String turnRoad = parseStrProp(text, "turn_road");
        String turnDesc = parseStrProp(text, "turn_desc");
        String exitInfo = parseStrProp(text, "exit_info");
        String destName = parseStrProp(text, "dest_name");
        String sourceName = parseStrProp(text, "source_name");

        int mainElement;
        int direction;
        if ((routeState == 3 || routeState == 5) && mType < 0) {
            mainElement = (routeState == 3) ? ManeuverMapper.CALC_ROUTE : ManeuverMapper.RECALC_ROUTE;
            direction = ManeuverMapper.DIR_STRAIGHT;
        } else {
            int[] mapped = ManeuverMapper.map(mType, turnAngle, junctionType, drivingSide, anglePresent);
            mainElement = mapped[0];
            direction = mapped[1];
        }
        int bar = ManeuverMapper.computeBargraph(mType, distM, distPresent, stepDistM);
        String turnStreet = turnRoad.length() > 0 ? turnRoad : (turnDesc.length() > 0 ? turnDesc : destName);
        if (turnStreet.length() == 0 && sourceName.length() > 0) {
            turnStreet = sourceName;
        }
        String currentStreet = currentRoad.length() > 0 ? currentRoad : turnStreet;

        boolean changed = !rgdActive
                || seq != lastRgdSeq
                || mainElement != lastMainElem
                || direction != lastDir
                || (distPresent ? distM : -1) != lastDistM
                || bar != lastBar
                || (destDistPresent ? destDistM : -1) != lastDestDistM
                || (remPresent ? remSec : -1L) != lastRemSec
                || !turnStreet.equals(lastTurnStreet)
                || !currentStreet.equals(lastCurrentStreet)
                || !exitInfo.equals(lastExitInfo);

        if (!changed && now - lastRgdPush < RGD_REFRESH_MS) {
            return;
        }

        boolean starting = !rgdActive;
        boolean iconOrTextChanged = starting
                || mainElement != lastMainElem
                || direction != lastDir
                || !turnStreet.equals(lastTurnStreet)
                || bar != lastBar
                || (distPresent ? distM : -1) != lastDistM;

        rgdActive = true;
        lastRgdSeq = seq;
        lastMainElem = mainElement;
        lastDir = direction;
        lastDistM = distPresent ? distM : -1;
        lastBar = bar;
        lastDestDistM = destDistPresent ? destDistM : -1;
        lastRemSec = remPresent ? remSec : -1L;
        lastTurnStreet = turnStreet;
        lastCurrentStreet = currentStreet;
        lastExitInfo = exitInfo;
        lastRgdPush = now;

        if (starting || seq != lastRgdSeq || iconOrTextChanged) {
            log(now, new StringBuffer(192)
                    .append("RGD update: src=").append(sourceName)
                    .append(" state=").append(routeState)
                    .append(" mt=").append(mType)
                    .append(" angle=").append(turnAngle)
                    .append(" -> elem=").append(mainElement)
                    .append(" dir=").append(direction)
                    .append(" dist=").append(distPresent ? distM : -1)
                    .append("m bar=").append(bar)
                    .append(" road=\"").append(turnStreet).append('"').toString());
        }

        pushRgdToClusterAndHud(starting, iconOrTextChanged, mType, mainElement, direction,
                distM, distPresent, bar, destDistM, destDistPresent,
                remSec, remPresent, currentStreet, turnStreet, exitInfo);
    }

    private void pushRgdToClusterAndHud(boolean starting, boolean flushHud,
                                        int maneuverType, int mainElement, int direction,
                                        int distM, boolean distPresent, int bar,
                                        int destDistM, boolean destDistPresent,
                                        long remSec, boolean remPresent,
                                        String currentStreet, String turnStreet, String exitInfo) throws Exception {
        Object cs = call(nav(), "getClusterService");
        if (cs == null) {
            return;
        }
        Class strClass = "".getClass();

        /* 1. Mark ClusterService.rgActive = true without triggering CombiScreen(190137)
         *    (kombiNavCompass) repaints on Terminal 1, which would send FrameRequest(5, 0)
         *    and write street text to cluster Frame 7 (COMPASS) instead of HUD Frame 5. */
        try {
            Field fRg = cs.getClass().getDeclaredField("rgActive");
            fRg.setAccessible(true);
            fRg.setBoolean(cs, true);
        } catch (Throwable ignored) {
        }
        try {
            Field fRgiValid = cs.getClass().getDeclaredField("rgiDataValid");
            fRgiValid.setAccessible(true);
            fRgiValid.setBoolean(cs, true);
        } catch (Throwable ignored) {
        }

        /* 2. Update distance/time metrics and KOMO (DSIKOMONavInfo + DSIKOMOView) directly
         *    without mutating HMI models 46/53/55 that trigger CombiScreen(190137) Frame 7 repaints. */
        try {
            updateMetricMeters(cs, "distanceToManeuver", distPresent && distM >= 0 ? distM : 0);
            updateMetricMeters(cs, "distanceToDestination", destDistPresent && destDistM >= 0 ? destDistM : 0);
        } catch (Throwable ignored) {
        }
        try {
            Field fKm = cs.getClass().getDeclaredField("komoManager");
            fKm.setAccessible(true);
            Object km = fKm.get(cs);
            if (km != null) {
                Object navInfo = call(km, "getDSIKOMONavInfo");
                if (navInfo != null) {
                    boolean showDist = distPresent && distM >= 0;
                    try {
                        navInfo.getClass().getMethod("setDistanceToNextManeuver",
                                new Class[] {Long.TYPE, Integer.TYPE, Boolean.TYPE})
                                .invoke(navInfo, new Object[] {
                                    new Long(showDist ? (long) (distM * 10) : 0L),
                                    new Integer(1),
                                    new Boolean(showDist)
                                });
                    } catch (NoSuchMethodException nsme) {
                        navInfo.getClass().getMethod("setDistanceToNextManeuver",
                                new Class[] {Long.TYPE, Integer.TYPE, Boolean.TYPE, Integer.TYPE})
                                .invoke(navInfo, new Object[] {
                                    new Long(showDist ? (long) distM : 0L),
                                    new Integer(0),
                                    new Boolean(bar >= 0),
                                    new Integer(bar >= 0 ? bar : 0)
                                });
                    }
                    try {
                        navInfo.getClass().getMethod("setCurrentStreet", new Class[] {strClass})
                                .invoke(navInfo, new Object[] {currentStreet});
                    } catch (Throwable ignored) {
                    }
                    navInfo.getClass().getMethod("setTurnToStreet", new Class[] {strClass, strClass})
                            .invoke(navInfo, new Object[] {turnStreet, exitInfo});
                    navInfo.getClass().getMethod("setDistanceToDestination",
                            new Class[] {Long.TYPE, Integer.TYPE, Boolean.TYPE})
                            .invoke(navInfo, new Object[] {
                                new Long(destDistPresent && destDistM >= 0 ? (long) (destDistM * 10) : 0L),
                                new Integer(1),
                                new Boolean(destDistPresent && destDistM >= 0)
                            });
                    navInfo.getClass().getMethod("setETA",
                            new Class[] {Integer.TYPE, Short.TYPE, Short.TYPE, Short.TYPE, Boolean.TYPE, Boolean.TYPE})
                            .invoke(navInfo, new Object[] {
                                new Integer(0),
                                new Short((short) (remPresent ? ((remSec / 86400L) & 0x7FFF) : 0)),
                                new Short((short) (remPresent ? ((remSec % 86400L) / 3600L) : 0)),
                                new Short((short) (remPresent ? ((remSec % 3600L) / 60L) : 0)),
                                new Boolean(remPresent),
                                new Boolean(false)
                            });
                }
            }
        } catch (Throwable t) {
            if (starting) note("rgd DSIKOMONavInfo update failed: ", t);
        }

        String dText = formatClusterDistance(cs, "distanceToManeuver", distM, distPresent);
        String destCell0 = formatClusterDistance(cs, "distanceToDestination", destDistM, destDistPresent);

        /* 3. KOMO RouteInfoElement (DSIKOMOView.setRouteInfoElement) */
        try {
            Class meClass = Class.forName("org.dsi.ifc.komoview.ManeuverElement");
            Object me = meClass.newInstance();
            meClass.getField("element").setInt(me, mainElement);
            meClass.getField("direction").setShort(me, (short) direction);
            meClass.getField("attribute").setInt(me, 0);
            Object meArr = Array.newInstance(meClass, 1);
            Array.set(meArr, 0, me);

            Class rieClass = Class.forName("org.dsi.ifc.komoview.RouteInfoElement");
            Object rie = rieClass.newInstance();
            String remStr = remPresent ? String.valueOf(remSec / 60L) : "";
            try {
                rieClass.getField("distanceToElement").set(rie, dText.length() > 0 ? dText : destCell0);
                rieClass.getField("estimatedTimeToElement").set(rie, remStr);
                rieClass.getField("distanceToManeuver").set(rie, dText);
                rieClass.getField("estimatedTimeToManeuver").set(rie, remStr);
            } catch (IllegalArgumentException iae) {
                rieClass.getField("distanceToElement").setInt(rie, distPresent ? distM : 0);
                rieClass.getField("estimatedTimeToElement").setInt(rie, remPresent ? (int) (remSec / 60L) : 0);
                rieClass.getField("distanceToManeuver").setInt(rie, distPresent ? distM : 0);
            }
            rieClass.getField("routeInfoElementType").setInt(rie, 3);
            rieClass.getField("maneuverDescriptor").set(rie, meArr);
            rieClass.getField("turnToStreet").set(rie, turnStreet);
            rieClass.getField("exitNumber").set(rie, exitInfo);

            Object rieArr = Array.newInstance(rieClass, 2);
            Array.set(rieArr, 0, rie);
            Array.set(rieArr, 1, rie);
            cs.getClass().getMethod("setRouteInfo", new Class[] {rieArr.getClass()})
                    .invoke(cs, new Object[] {rieArr});
        } catch (Throwable t) {
            if (starting) note("rgd setRouteInfo failed: ", t);
        }

        /* 4. Direct DDP2 Frame 5 (RGI_EXT) HUD update via DSIDDP20Controller + CombiFrameStatusHandler.
         *    Bypasses CommandTypeInitialisationHUD (which copied dirty elements into Frame 7 COMPASS
         *    and sent FrameRequest(5, 1) backgrounding Frame 5 when no native Audi route was active). */
        if (flushHud || starting) {
            String prefix = ManeuverMapper.formatHudTurnPrefix(mainElement, direction, maneuverType, exitInfo);
            String topCell1;
            if (dText.length() > 0) {
                topCell1 = prefix + " " + dText;
            } else if (destCell0.length() > 0) {
                topCell1 = prefix + " " + destCell0;
            } else {
                topCell1 = prefix;
            }
            String bottomCell2 = turnStreet;
            if (exitInfo.length() > 0 && turnStreet.length() > 0 && turnStreet.indexOf(exitInfo) < 0) {
                bottomCell2 = "[" + exitInfo + "] " + turnStreet;
            } else if (bottomCell2.length() == 0 && currentStreet.length() > 0) {
                bottomCell2 = currentStreet;
            }
            short[] rgiStream = ManeuverMapper.buildDdp2RgiStream(mainElement, direction, maneuverType);
            pushHudFrame5(cs, starting, topCell1, true, destCell0, bottomCell2, bar, rgiStream);
        }
    }

    static void pushHudFrame5(Object cs, boolean starting, String cell1TopText, boolean prependSign13,
                              String cell0DestText, String cell2BottomText, int bar) {
        short[] defaultRgi = ManeuverMapper.buildDdp2RgiStream(
                ManeuverMapper.FOLLOW_STREET, ManeuverMapper.DIR_STRAIGHT, ManeuverMapper.MT_STRAIGHT_AHEAD);
        pushHudFrame5(cs, starting, cell1TopText, prependSign13, cell0DestText, cell2BottomText, bar, defaultRgi);
    }

    static void pushHudFrame5(Object cs, boolean starting, String cell1TopText, boolean prependSign13,
                              String cell0DestText, String cell2BottomText, int bar, short[] rgiStream) {
        if (cs == null) return;
        try {
            Class strClass = "".getClass();
            String topWithSign = cell1TopText != null ? cell1TopText : "";
            if (prependSign13 && topWithSign.length() > 0) {
                try {
                    Object sign13 = Class.forName("de.audi.atip.hmi.combi.ddp2.CombiSignConverter")
                            .getMethod("convertSign", new Class[] {Integer.TYPE})
                            .invoke(null, new Object[] {new Integer(13)});
                    if (sign13 != null) {
                        topWithSign = sign13.toString() + topWithSign;
                    }
                } catch (Throwable ignored) {
                }
            }
            String destStr = cell0DestText != null ? cell0DestText : "";
            String bottomStr = cell2BottomText != null ? cell2BottomText : "";

            /* Keep CombiElementBankDDP2 in sync for both Frame 5 (RGI_EXT) and Frame 6 (MOST)
             * so background repaints of kombiNavMost (Frame 6) never overwrite Frame 5 Cell 2
             * with an empty street name via CommandTypeScreenUpdateNavi.updateBCRoll(). */
            try {
                Object bank = Class.forName("de.audi.atip.hmi.combi.ddp2.CombiElementBankDDP2")
                        .getMethod("getInstance", new Class[0]).invoke(null, new Object[0]);
                Method getInt = bank.getClass().getMethod("getIntegerElementAt", new Class[] {Integer.TYPE, Integer.TYPE});
                Method getTxt = bank.getClass().getMethod("getTextElementAt", new Class[] {Integer.TYPE, Integer.TYPE});

                for (int fId = 5; fId <= 6; fId++) {
                    Integer frameObj = new Integer(fId);
                    Object distBar = getInt.invoke(bank, new Object[] {new Integer(20), frameObj});
                    if (distBar != null) {
                        distBar.getClass().getMethod("setValue", new Class[] {Integer.TYPE})
                                .invoke(distBar, new Object[] {new Integer(bar >= 0 ? bar : -1)});
                        distBar.getClass().getField("dirty").setBoolean(distBar, false);
                    }
                    Object navDistMan = getTxt.invoke(bank, new Object[] {new Integer(3), frameObj});
                    if (navDistMan != null) {
                        navDistMan.getClass().getMethod("setText", new Class[] {strClass})
                                .invoke(navDistMan, new Object[] {cell1TopText != null ? cell1TopText : ""});
                        navDistMan.getClass().getField("deleteText").setBoolean(navDistMan, false);
                        navDistMan.getClass().getField("dirty").setBoolean(navDistMan, false);
                    }
                    Object navDistDest = getTxt.invoke(bank, new Object[] {new Integer(4), frameObj});
                    if (navDistDest != null) {
                        navDistDest.getClass().getMethod("setText", new Class[] {strClass})
                                .invoke(navDistDest, new Object[] {destStr});
                        navDistDest.getClass().getField("deleteText").setBoolean(navDistDest, false);
                        navDistDest.getClass().getField("dirty").setBoolean(navDistDest, false);
                    }
                    Object navStreet = getTxt.invoke(bank, new Object[] {new Integer(5), frameObj});
                    if (navStreet != null) {
                        navStreet.getClass().getMethod("setText", new Class[] {strClass})
                                .invoke(navStreet, new Object[] {bottomStr});
                        navStreet.getClass().getField("deleteText").setBoolean(navStreet, false);
                        navStreet.getClass().getField("dirty").setBoolean(navStreet, false);
                    }
                }
                if (rgiStream != null) {
                    Object rgiElem = bank.getClass().getMethod("getRGIElement", new Class[0])
                            .invoke(bank, new Object[0]);
                    if (rgiElem != null) {
                        rgiElem.getClass().getField("rgiStream").set(rgiElem, rgiStream);
                        rgiElem.getClass().getField("dirty").setBoolean(rgiElem, false);
                    }
                }
            } catch (Throwable ignored) {
            }

            /* Drive DSIDDP20Controller and CombiFrameStatusHandler directly on Frame 5 (RGI_EXT) */
            Field fCombi = cs.getClass().getDeclaredField("combiService");
            fCombi.setAccessible(true);
            Object combi = fCombi.get(cs);
            if (combi == null) return;

            Field fCq = combi.getClass().getDeclaredField("commandQueue");
            fCq.setAccessible(true);
            Object cq = fCq.get(combi);
            Field fFsh = combi.getClass().getDeclaredField("frameStatusHandler");
            fFsh.setAccessible(true);
            Object fsh = fFsh.get(combi);
            if (cq == null || fsh == null) return;

            Object dsiCtrl = call(cq, "getDSIController");
            if (dsiCtrl == null) return;

            try {
                Class.forName("de.audi.tghu.combi.ddp2.CombiApplicationStatusHandler")
                        .getMethod("setRGState", new Class[] {Integer.TYPE})
                        .invoke(null, new Object[] {new Integer(6)});
            } catch (Throwable ignored) {
            }
            if (starting) {
                try {
                    Class.forName("de.audi.tghu.combi.ddp2.fw.CombiModelAccess")
                            .getMethod("setCombiRouteGuidanceStateChoiceValue", new Class[] {Integer.TYPE})
                            .invoke(null, new Object[] {new Integer(2)});
                } catch (Throwable ignored) {
                }
                try {
                    dsiCtrl.getClass().getMethod("applicationNaviUpdate", new Class[] {Integer.TYPE, Integer.TYPE})
                            .invoke(dsiCtrl, new Object[] {new Integer(3), new Integer(6)});
                } catch (Throwable ignored) {
                }
                try {
                    fsh.getClass().getMethod("updateFrame", new Class[] {Integer.TYPE, Integer.TYPE, Integer.TYPE})
                            .invoke(fsh, new Object[] {new Integer(0), new Integer(4), new Integer(2)});
                } catch (Throwable ignored) {
                }
            }

            if (rgiStream != null) {
                try {
                    Method mMan = dsiCtrl.getClass().getMethod("setManeuver",
                            new Class[] {Integer.TYPE, rgiStream.getClass(), Boolean.TYPE});
                    mMan.invoke(dsiCtrl, new Object[] {
                        new Integer(5), rgiStream, new Boolean(true)
                    });
                } catch (Throwable ignored) {
                }
            }

            Method mUpdTxt = dsiCtrl.getClass().getMethod("updateText",
                    new Class[] {Integer.TYPE, Short.TYPE, strClass, Short.TYPE, Boolean.TYPE});
            mUpdTxt.invoke(dsiCtrl, new Object[] {
                new Integer(5), new Short((short) 0), destStr, new Short((short) 0), new Boolean(true)
            });
            mUpdTxt.invoke(dsiCtrl, new Object[] {
                new Integer(5), new Short((short) 1), topWithSign, new Short((short) 0), new Boolean(true)
            });
            mUpdTxt.invoke(dsiCtrl, new Object[] {
                new Integer(5), new Short((short) 2), bottomStr, new Short((short) 0), new Boolean(true)
            });

            Method mBar = dsiCtrl.getClass().getMethod("setDistanceBar",
                    new Class[] {Integer.TYPE, Short.TYPE, Boolean.TYPE, Boolean.TYPE});
            mBar.invoke(dsiCtrl, new Object[] {
                new Integer(5),
                new Short((short) (bar >= 0 ? bar : 0)),
                new Boolean(bar < 0),
                new Boolean(true)
            });

            /* Examine activeNaviFrameID:
             *  - When cluster is in MOST map (Frame 6) or Compass (Frame 7), stock
             *    CombiFrameStatusHandler.setActiveNaviFrame(6) and CommandTypeScreenUpdateNavi
             *    use request=1 for Frame 5 (RGI_EXT on HUD in background without stealing
             *    FocusLevel_1 from Frame 6 on the cluster).
             *  - Only use request=18 when Frame 5 itself is the active cluster frame. */
            int activeFrame = 6;
            int req5Before = -1;
            int req6Before = -1;
            int req7Before = -1;
            try {
                activeFrame = ((Integer) fsh.getClass().getMethod("getActiveNaviFrameID", new Class[0])
                        .invoke(fsh, new Object[0])).intValue();
                Method mGetReq = fsh.getClass().getMethod("getFrameStatusRequest", new Class[] {Integer.TYPE});
                req5Before = ((Integer) mGetReq.invoke(fsh, new Object[] {new Integer(5)})).intValue();
                req6Before = ((Integer) mGetReq.invoke(fsh, new Object[] {new Integer(6)})).intValue();
                req7Before = ((Integer) mGetReq.invoke(fsh, new Object[] {new Integer(7)})).intValue();
            } catch (Throwable ignored) {
            }
            /* If CombiFrameStatusHandler is still on Frame 7 (COMPASS), switch activeNaviFrameID
             * to Frame 6 (when MOST map is active) or Frame 5 so Frame 7 does not invalidate Frame 5. */
            if (activeFrame == 7) {
                try {
                    int targetFrame = (getView() == MAP) ? 6 : 5;
                    fsh.getClass().getMethod("setActiveNaviFrame", new Class[] {Integer.TYPE})
                            .invoke(fsh, new Object[] {new Integer(targetFrame)});
                    activeFrame = targetFrame;
                } catch (Throwable ignored) {
                }
            }
            int req = (activeFrame == 5) ? 18 : 1;
            try {
                /* Reset cached status for Frame 5 first so updateFrame(0, 5, req) always
                 * emits a DisplayRequest(FrameRequest(5, req)), matching stock
                 * CommandTypeScreenUpdateNavi(frameID=5, confirmFrameStatus=true). */
                fsh.getClass().getMethod("resetFrameStatus", new Class[] {Integer.TYPE})
                        .invoke(fsh, new Object[] {new Integer(5)});
            } catch (Throwable ignored) {
            }
            fsh.getClass().getMethod("updateFrame", new Class[] {Integer.TYPE, Integer.TYPE, Integer.TYPE})
                    .invoke(fsh, new Object[] {new Integer(0), new Integer(5), new Integer(req)});
            try {
                /* Also send FrameUpdate(5, 0) when updating an already-active Frame 5 */
                Class fuClass = Class.forName("org.dsi.ifc.ddp20.FrameUpdate");
                Object fu = fuClass.getConstructor(new Class[] {Integer.TYPE, Integer.TYPE})
                        .newInstance(new Object[] {new Integer(5), new Integer(0)});
                Object fuArr = Array.newInstance(fuClass, 1);
                Array.set(fuArr, 0, fu);
                Class urClass = Class.forName("org.dsi.ifc.ddp20.UpdateRequest");
                Object ur = urClass.getConstructor(new Class[] {Integer.TYPE, fuArr.getClass()})
                        .newInstance(new Object[] {new Integer(1), fuArr});
                dsiCtrl.getClass().getMethod("frameUpdate", new Class[] {urClass})
                        .invoke(dsiCtrl, new Object[] {ur});
            } catch (Throwable ignored) {
            }
            log(System.currentTimeMillis(), "pushHudFrame5: activeFrame=" + activeFrame
                    + " req=" + req + " prevReq[5,6,7]=[" + req5Before + "," + req6Before + "," + req7Before + "]"
                    + " top=\"" + topWithSign + "\" dest=\"" + destStr + "\" bottom=\"" + bottomStr + "\" bar=" + bar);
        } catch (Throwable t) {
            if (starting) note("pushHudFrame5 failed: ", t);
        }
    }

    static void clearHudFrame5(Object cs) {
        if (cs == null) return;
        try {
            Class strClass = "".getClass();
            Field fCombi = cs.getClass().getDeclaredField("combiService");
            fCombi.setAccessible(true);
            Object combi = fCombi.get(cs);
            if (combi == null) return;

            Field fCq = combi.getClass().getDeclaredField("commandQueue");
            fCq.setAccessible(true);
            Object cq = fCq.get(combi);
            Field fFsh = combi.getClass().getDeclaredField("frameStatusHandler");
            fFsh.setAccessible(true);
            Object fsh = fFsh.get(combi);
            if (cq == null || fsh == null) return;

            Object dsiCtrl = call(cq, "getDSIController");
            if (dsiCtrl == null) return;

            Method mBar = dsiCtrl.getClass().getMethod("setDistanceBar",
                    new Class[] {Integer.TYPE, Short.TYPE, Boolean.TYPE, Boolean.TYPE});
            mBar.invoke(dsiCtrl, new Object[] {
                new Integer(5), new Short((short) 0), new Boolean(true), new Boolean(true)
            });

            Method mUpdTxt = dsiCtrl.getClass().getMethod("updateText",
                    new Class[] {Integer.TYPE, Short.TYPE, strClass, Short.TYPE, Boolean.TYPE});
            mUpdTxt.invoke(dsiCtrl, new Object[] {
                new Integer(5), new Short((short) 0), "", new Short((short) 0), new Boolean(true)
            });
            mUpdTxt.invoke(dsiCtrl, new Object[] {
                new Integer(5), new Short((short) 1), "", new Short((short) 0), new Boolean(true)
            });
            mUpdTxt.invoke(dsiCtrl, new Object[] {
                new Integer(5), new Short((short) 2), "", new Short((short) 0), new Boolean(true)
            });

            try {
                fsh.getClass().getMethod("resetFrameStatus", new Class[] {Integer.TYPE})
                        .invoke(fsh, new Object[] {new Integer(5)});
            } catch (Throwable ignored) {
            }
            fsh.getClass().getMethod("updateFrame", new Class[] {Integer.TYPE, Integer.TYPE, Integer.TYPE})
                    .invoke(fsh, new Object[] {new Integer(0), new Integer(5), new Integer(0)});

            try {
                Class.forName("de.audi.tghu.combi.ddp2.CombiApplicationStatusHandler")
                        .getMethod("setRGState", new Class[] {Integer.TYPE})
                        .invoke(null, new Object[] {new Integer(1)});
            } catch (Throwable ignored) {
            }
            try {
                dsiCtrl.getClass().getMethod("applicationNaviUpdate", new Class[] {Integer.TYPE, Integer.TYPE})
                        .invoke(dsiCtrl, new Object[] {new Integer(3), new Integer(1)});
            } catch (Throwable ignored) {
            }
        } catch (Throwable ignored) {
        }
    }

    private static void updateMetricMeters(Object cs, String fieldName, int meters) {
        try {
            Field f = cs.getClass().getDeclaredField(fieldName);
            f.setAccessible(true);
            Object metric = f.get(cs);
            if (metric != null) {
                metric.getClass().getMethod("setValue", new Class[] {Float.TYPE})
                        .invoke(metric, new Object[] {new Float(((float) meters) / 1000.0f)});
            }
        } catch (Throwable ignored) {
        }
    }

    private void stopRgd(long now, String why) {
        rgdActive = false;
        lastMainElem = -1;
        lastDir = -1;
        lastDistM = -1;
        lastBar = -2;
        lastDestDistM = -1;
        lastRemSec = -1L;
        lastTurnStreet = "";
        lastCurrentStreet = "";
        lastExitInfo = "";
        log(now, "RGD inactive (" + why + "): clearing HUD/cluster route guidance");
        try {
            Object cs = call(nav(), "getClusterService");
            if (cs == null) {
                return;
            }
            try {
                Field fRg = cs.getClass().getDeclaredField("rgActive");
                fRg.setAccessible(true);
                fRg.setBoolean(cs, false);
            } catch (Throwable ignored) {
            }
            try {
                Field fRgiValid = cs.getClass().getDeclaredField("rgiDataValid");
                fRgiValid.setAccessible(true);
                fRgiValid.setBoolean(cs, false);
            } catch (Throwable ignored) {
            }
            try {
                Method mDef = cs.getClass().getDeclaredMethod("setDefaultValues", new Class[0]);
                mDef.setAccessible(true);
                mDef.invoke(cs, new Object[0]);
            } catch (Throwable ignored) {
            }
            try {
                Class rieClass = Class.forName("org.dsi.ifc.komoview.RouteInfoElement");
                Object emptyArr = Array.newInstance(rieClass, 0);
                cs.getClass().getMethod("setRouteInfo", new Class[] {emptyArr.getClass()})
                        .invoke(cs, new Object[] {emptyArr});
            } catch (Throwable ignored) {
            }
            clearHudFrame5(cs);
        } catch (Throwable t) {
            note("stopRgd failed: ", t);
        }
    }

    private static String formatClusterDistance(Object cs, String fieldName, int meters, boolean present) {
        if (!present || meters < 0) {
            return "";
        }
        try {
            Field f = cs.getClass().getDeclaredField(fieldName);
            f.setAccessible(true);
            Object metric = f.get(cs);
            if (metric != null) {
                metric.getClass().getMethod("setValue", new Class[] {Float.TYPE})
                        .invoke(metric, new Object[] {new Float(((float) meters) / 1000.0f)});
                int mode = "distanceToDestination".equals(fieldName) ? 1 : 5;
                Object formatted = metric.getClass().getMethod("formatByMode", new Class[] {Integer.TYPE})
                        .invoke(metric, new Object[] {new Integer(mode)});
                if (formatted != null) {
                    return formatted.toString();
                }
            }
        } catch (Throwable ignored) {
        }
        if (meters >= 1000) {
            int km10 = (meters + 50) / 100;
            return (km10 / 10) + "." + (km10 % 10) + " km";
        }
        return meters + " m";
    }

    private void observeNativeRgi(long now) {
        try {
            Object dsiResp = Class.forName("de.audi.tghu.navi.app.command.DSIResponseContainer")
                    .getMethod("getInstance", new Class[0]).invoke(null, new Object[0]);
            short[] rgi = (short[]) call(dsiResp, "getRGIString");
            if (rgi == null || rgi.length == 0) {
                return;
            }
            StringBuffer sb = new StringBuffer(96);
            for (int i = 0; i < rgi.length; i++) {
                if (i > 0) sb.append(',');
                sb.append((int) (rgi[i] & 0xFFFF));
            }
            String s = sb.toString();
            if (!s.equals(lastNativeRgi)) {
                lastNativeRgi = s;
                log(now, "native RGIString=[" + s + "]");
            }
        } catch (Throwable ignored) {
        }
    }

    /* ---- state file parsing helpers ------------------------------------ */

    private static String readFileText(File f, int maxBytes) {
        FileInputStream in = null;
        try {
            byte[] b = new byte[maxBytes];
            in = new FileInputStream(f);
            int total = 0;
            while (total < b.length) {
                int n = in.read(b, total, b.length - total);
                if (n <= 0) break;
                total += n;
            }
            return total > 0 ? new String(b, 0, total) : "";
        } catch (Throwable t) {
            return null;
        } finally {
            if (in != null) {
                try {
                    in.close();
                } catch (Throwable ignored) {
                }
            }
        }
    }

    private static String parseStrProp(String text, String key) {
        String prefix = key + "=";
        int start = 0;
        int len = text.length();
        while (start < len) {
            int end = text.indexOf('\n', start);
            if (end < 0) end = len;
            if (end - start >= prefix.length() && text.startsWith(prefix, start)) {
                String val = text.substring(start + prefix.length(), end);
                if (val.endsWith("\r")) {
                    val = val.substring(0, val.length() - 1);
                }
                return val;
            }
            start = end + 1;
        }
        return "";
    }

    private static int parseIntProp(String text, String key, int defVal) {
        String s = parseStrProp(text, key);
        if (s.length() == 0) return defVal;
        try {
            return Integer.parseInt(s);
        } catch (Throwable t) {
            return defVal;
        }
    }

    private static long parseLongProp(String text, String key, long defVal) {
        String s = parseStrProp(text, key);
        if (s.length() == 0) return defVal;
        try {
            return Long.parseLong(s);
        } catch (Throwable t) {
            return defVal;
        }
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

    static void logTelemetry(long now, String what) {
        log(now, what);
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
