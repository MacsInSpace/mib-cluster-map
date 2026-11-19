package com.mhi2.androidadio;

import de.audi.atip.base.IFrameworkAccess;
import de.audi.atip.log.LogChannel;
import de.audi.tghu.navi.app.cluster.ClusterService;
import org.dsi.ifc.navigation.BapManeuverDescriptor;
import org.dsi.ifc.navigation.DistanceToNextManeuver;
import org.osgi.framework.BundleContext;
import org.osgi.framework.FrameworkUtil;
import org.osgi.framework.ServiceReference;
import org.osgi.framework.Bundle;
import java.io.FileWriter;
import java.io.PrintWriter;
import java.text.SimpleDateFormat;
import java.util.Date;

public class AAManeuverProvider {
    private static AAManeuverProvider instance;
    private LogChannel log;
    private ClusterService clusterService;
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
        debugLog("handleNextTurnEvent called, roadName='" + roadName + "' mainElement=" + mainElement + " direction=" + direction);
        if (instance != null && instance.clusterService != null) {
            try {
                BapManeuverDescriptor[] desc = new BapManeuverDescriptor[1];
                desc[0] = new BapManeuverDescriptor(mainElement, direction, 0, null);
                instance.clusterService.updateManeuverDescriptor(desc);
                debugLog("handleNextTurnEvent: clusterService.updateManeuverDescriptor called");
            } catch (Throwable t) {
                debugLog("handleNextTurnEvent: threw " + t);
            }
        } else {
            debugLog("handleNextTurnEvent: no instance or clusterService");
        }
    }

    public static void handleNextTurnDistance(int distance, int unit, int remainingDistance) {
        debugLog("handleNextTurnDistance called, distance=" + distance);
        if (instance != null && instance.clusterService != null) {
            try {
                DistanceToNextManeuver dist = new DistanceToNextManeuver(true, distance, true, 0);
                instance.clusterService.updateDistanceToNextManeuver(dist);
                debugLog("handleNextTurnDistance: clusterService.updateDistanceToNextManeuver called");
            } catch (Throwable t) {
                debugLog("handleNextTurnDistance: threw " + t);
            }
        } else {
            debugLog("handleNextTurnDistance: no instance or clusterService");
        }
    }

    public AAManeuverProvider() {
        instance = this;
        log = getLogChannel();
        lastMainElement = 0;
        lastDirection = 0;
        lastDistance = 0;
        debugLog("AAManeuverProvider.<init> entered");
        clusterService = findClusterService();
        if (clusterService != null) {
            log.log(100000, "cluster service found");
            debugLog("clusterService found");
        } else {
            log.log(1000000, "cluster service NOT found");
            debugLog("clusterService NOT found");
        }
    }

    private LogChannel getLogChannel() {
        try {
            BundleContext bc = AAJavaBridge.getBundleContext();
            if (bc != null) {
                ServiceReference ref = bc.getServiceReference(IFrameworkAccess.class.getName());
                if (ref != null) {
                    Object fa = bc.getService(ref);
                    if (fa != null) {
                        java.lang.reflect.Method m = fa.getClass().getMethod("getLogChannel", String.class);
                        bc.ungetService(ref);
                        return (LogChannel) m.invoke(fa, "AAManeuverProvider");
                    }
                    bc.ungetService(ref);
                }
            }
        } catch (Throwable t) {}
        try {
            Class cls = Class.forName("de.audi.atip.base.IFrameworkAccess");
            java.lang.reflect.Field f = null;
            Class c = cls;
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
                    java.lang.reflect.Method m = fa.getClass().getMethod("getLogChannel", String.class);
                    return (LogChannel) m.invoke(fa, "AAManeuverProvider");
                }
            }
        } catch (Throwable t) {}
        return new StubLogChannel();
    }

    private ClusterService findClusterService() {
        try {
            BundleContext bc = AAJavaBridge.getBundleContext();
            if (bc != null) {
                ServiceReference ref = bc.getServiceReference(ClusterService.class.getName());
                if (ref != null) {
                    Object svc = bc.getService(ref);
                    if (svc != null) {
                        bc.ungetService(ref);
                        debugLog("findClusterService: found via OSGi ClusterService");
                        return (ClusterService) svc;
                    }
                    bc.ungetService(ref);
                }
            }
        } catch (Throwable t) {
            debugLog("findClusterService: OSGi lookup threw " + t);
        }
        try {
            Class cls = Class.forName("de.audi.tghu.navi.app.cluster.ClusterService");
            java.lang.reflect.Field f = null;
            Class c = cls;
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
                if (inst != null && inst instanceof ClusterService) {
                    debugLog("findClusterService: found via static instance field");
                    return (ClusterService) inst;
                }
            }
        } catch (Throwable t) {
            debugLog("findClusterService: static field lookup threw " + t);
        }
        debugLog("findClusterService: returning null");
        return null;
    }

    private static void debugLog(String msg) {
        try {
            SimpleDateFormat sdf = new SimpleDateFormat("HH:mm:ss.SSS");
            String line = sdf.format(new Date()) + " AAManeuverProvider: " + msg;
            FileWriter fw = new FileWriter("/tmp/aacoverart.log", true);
            PrintWriter pw = new PrintWriter(fw);
            pw.println(line);
            pw.close();
        } catch (Throwable t) {}
    }

    private static class StubLogChannel extends de.audi.atip.log.LogChannel {
        public StubLogChannel() { super(); }
        public void log(int a, java.lang.String b, java.lang.Object c, java.lang.Object d, java.lang.Object e, java.lang.Object f, long g, long h, long i, int j, java.lang.Throwable k) {}
        public void log(int a, int b, java.lang.Object c, java.lang.Object d, java.lang.Object e, java.lang.Object f, long g, long h, long i, int j, java.lang.Throwable k) {}
        public boolean log(int a, java.lang.String b) { return false; }
    }
}
