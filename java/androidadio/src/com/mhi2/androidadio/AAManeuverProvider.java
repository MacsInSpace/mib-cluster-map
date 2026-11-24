package com.mhi2.androidadio;

import java.io.File;
import java.io.FileWriter;
import java.io.PrintWriter;
import java.lang.reflect.Method;
import java.text.SimpleDateFormat;
import java.util.Date;
import org.dsi.ifc.navigation.BapManeuverDescriptor;
import org.dsi.ifc.navigation.DistanceToNextManeuver;

public class AAManeuverProvider {
    private static AAManeuverProvider instance;
    private Object log;
    private Object clusterService;
    private int lastMainElement;
    private int lastDirection;
    private int lastDistance;

    public static AAManeuverProvider getInstance() {
        return instance;
    }

    public static int getLastMainElement() {
        return instance != null ? instance.lastMainElement : 0;
    }

    public static int getLastDirection() {
        return instance != null ? instance.lastDirection : 0;
    }

    public static int getLastDistance() {
        return instance != null ? instance.lastDistance : 0;
    }

    public static void handleNextTurnEvent(String roadName, int mainElement, int direction, int turnAngle, int turnNumber, int event) {
        StringBuffer sb = new StringBuffer("handleNextTurnEvent called, roadName='");
        sb.append(roadName);
        sb.append("' mainElement=");
        sb.append(mainElement);
        sb.append(" direction=");
        sb.append(direction);
        debugLog(sb.toString());
        if (instance == null) {
            debugLog("handleNextTurnEvent: no instance");
            return;
        }
        if (instance.clusterService == null) {
            debugLog("handleNextTurnEvent: clusterService null, attempting lazy lookup");
            instance.clusterService = instance.findClusterService();
            StringBuffer sb2 = new StringBuffer("handleNextTurnEvent: clusterService after lazy lookup=");
            sb2.append(instance.clusterService != null ? "non-null" : "null");
            debugLog(sb2.toString());
        }
        if (instance.clusterService == null) {
            debugLog("handleNextTurnEvent: no clusterService");
            return;
        }
        try {
            BapManeuverDescriptor[] desc = new BapManeuverDescriptor[1];
            desc[0] = new BapManeuverDescriptor(mainElement, direction, 0, null);
            Method m = instance.clusterService.getClass().getMethod("updateManeuverDescriptor", new Class[]{BapManeuverDescriptor[].class});
            m.invoke(instance.clusterService, new Object[]{desc});
            debugLog("handleNextTurnEvent: clusterService.updateManeuverDescriptor called");
        } catch (Throwable t) {
            StringBuffer sb3 = new StringBuffer("handleNextTurnEvent: threw ");
            sb3.append(t);
            debugLog(sb3.toString());
        }
    }

    public static void handleNextTurnDistance(int distance, int unit, int remainingDistance) {
        StringBuffer sb = new StringBuffer("handleNextTurnDistance called, distance=");
        sb.append(distance);
        debugLog(sb.toString());
        if (instance == null) {
            debugLog("handleNextTurnDistance: no instance");
            return;
        }
        if (instance.clusterService == null) {
            debugLog("handleNextTurnDistance: clusterService null, attempting lazy lookup");
            instance.clusterService = instance.findClusterService();
            StringBuffer sb2 = new StringBuffer("handleNextTurnDistance: clusterService after lazy lookup=");
            sb2.append(instance.clusterService != null ? "non-null" : "null");
            debugLog(sb2.toString());
        }
        if (instance.clusterService == null) {
            debugLog("handleNextTurnDistance: no clusterService");
            return;
        }
        try {
            DistanceToNextManeuver dist = new DistanceToNextManeuver(true, distance, true, 0);
            Method m = instance.clusterService.getClass().getMethod("updateDistanceToNextManeuver", new Class[]{DistanceToNextManeuver.class});
            m.invoke(instance.clusterService, new Object[]{dist});
            debugLog("handleNextTurnDistance: clusterService.updateDistanceToNextManeuver called");
        } catch (Throwable t) {
            StringBuffer sb3 = new StringBuffer("handleNextTurnDistance: threw ");
            sb3.append(t);
            debugLog(sb3.toString());
        }
    }

    public AAManeuverProvider() {
        instance = this;
        log = getLogChannel();
        lastMainElement = 0;
        lastDirection = 0;
        lastDistance = 0;
        debugLog("AAManeuverProvider.<init> entered (lazy clusterService lookup)");
    }

    private static Class<?> forName(String name) {
        ClassLoader tccl = Thread.currentThread().getContextClassLoader();
        if (tccl != null) {
            try {
                return Class.forName(name, true, tccl);
            } catch (ClassNotFoundException e) {
                // fall through to appClassLoader
            }
        }
        ClassLoader cl = AAJavaBridge.getAppClassLoader();
        if (cl != null) {
            try {
                return Class.forName(name, true, cl);
            } catch (ClassNotFoundException e) {
                // fall through to 1-arg
            }
        }
        try {
            return Class.forName(name);
        } catch (ClassNotFoundException e) {
            return null;
        }
    }

    private Object getLogChannel() {
        try {
            Object bc = AAJavaBridge.getBundleContext();
            if (bc != null) {
                Method getSR = bc.getClass().getMethod("getServiceReference", new Class[]{String.class});
                Object ref = getSR.invoke(bc, new Object[]{"de.audi.atip.base.IFrameworkAccess"});
                if (ref != null) {
                    Method getService = bc.getClass().getMethod("getService", new Class[]{ref.getClass()});
                    Object fa = getService.invoke(bc, new Object[]{ref});
                    if (fa != null) {
                        Method getLC = fa.getClass().getMethod("getLogChannel", new Class[]{String.class});
                        Object lc = getLC.invoke(fa, new Object[]{"AAManeuverProvider"});
                        Method unget = bc.getClass().getMethod("ungetService", new Class[]{ref.getClass()});
                        unget.invoke(bc, new Object[]{ref});
                        return lc;
                    }
                    Method unget = bc.getClass().getMethod("ungetService", new Class[]{ref.getClass()});
                    unget.invoke(bc, new Object[]{ref});
                }
            }
        } catch (Throwable t) {}
        try {
            Class<?> cls = forName("de.audi.atip.base.IFrameworkAccess");
            if (cls == null) {
                debugLog("getLogChannel: static instance lookup threw ClassNotFoundException");
            }
            Class<?> c = cls;
            java.lang.reflect.Field f = null;
            while (c != null) {
                try {
                    f = c.getDeclaredField("instance");
                    break;
                } catch (NoSuchFieldException e) {
                    c = c.getSuperclass();
                }
            }
            if (f != null) {
                f.setAccessible(true);
                Object fa = f.get(null);
                if (fa != null) {
                    Method getLC = fa.getClass().getMethod("getLogChannel", new Class[]{String.class});
                    return getLC.invoke(fa, new Object[]{"AAManeuverProvider"});
                }
            }
        } catch (Throwable t) {}
        return null;
    }

    private Object findClusterService() {
        try {
            Object bc = AAJavaBridge.getBundleContext();
            if (bc != null) {
                Method getSR = bc.getClass().getMethod("getServiceReference", new Class[]{String.class});
                Object ref = getSR.invoke(bc, new Object[]{"de.audi.tghu.navi.app.cluster.ClusterService"});
                if (ref != null) {
                    Method getService = bc.getClass().getMethod("getService", new Class[]{ref.getClass()});
                    Object svc = getService.invoke(bc, new Object[]{ref});
                    if (svc != null) {
                        Method unget = bc.getClass().getMethod("ungetService", new Class[]{ref.getClass()});
                        unget.invoke(bc, new Object[]{ref});
                        debugLog("findClusterService: found via OSGi ClusterService");
                        return svc;
                    }
                    Method unget = bc.getClass().getMethod("ungetService", new Class[]{ref.getClass()});
                    unget.invoke(bc, new Object[]{ref});
                }
            }
        } catch (Throwable t) {
            StringBuffer sb = new StringBuffer("findClusterService: OSGi lookup threw ");
            sb.append(t);
            debugLog(sb.toString());
        }
        try {
            Class<?> cls = forName("de.audi.tghu.navi.app.cluster.ClusterService");
            if (cls == null) {
                debugLog("findClusterService: static field lookup threw ClassNotFoundException");
            }
            Class<?> c = cls;
            java.lang.reflect.Field f = null;
            while (c != null) {
                try {
                    f = c.getDeclaredField("instance");
                    break;
                } catch (NoSuchFieldException e) {
                    c = c.getSuperclass();
                }
            }
            if (f != null) {
                f.setAccessible(true);
                Object inst = f.get(null);
                if (inst != null && "de.audi.tghu.navi.app.cluster.ClusterService".equals(inst.getClass().getName())) {
                    debugLog("findClusterService: found via static instance field");
                    return inst;
                }
            }
        } catch (Throwable t) {
            StringBuffer sb = new StringBuffer("findClusterService: static field lookup threw ");
            sb.append(t);
            debugLog(sb.toString());
        }
        debugLog("findClusterService: returning null");
        return null;
    }

    private void logCall(int level, String msg) {
        if (log != null) {
            try {
                Method m = log.getClass().getMethod("log", new Class[]{int.class, String.class});
                m.invoke(log, new Object[]{new Integer(level), msg});
            } catch (Throwable t) {}
        }
    }

    private static void debugLog(String msg) {
        if (!new File("/tmp/aa_debug").exists()) return;
        try {
            SimpleDateFormat sdf = new SimpleDateFormat("HH:mm:ss.SSS");
            StringBuffer sb = new StringBuffer();
            sb.append(sdf.format(new Date()));
            sb.append(" AAManeuverProvider: ");
            sb.append(msg);
            FileWriter fw = new FileWriter("/tmp/aacoverart.log", true);
            PrintWriter pw = new PrintWriter(fw);
            pw.println(sb.toString());
            pw.close();
        } catch (Throwable t) {}
    }
}
