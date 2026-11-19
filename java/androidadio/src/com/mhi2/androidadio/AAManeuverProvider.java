package com.mhi2.androidadio;

import de.audi.atip.base.IFrameworkAccess;
import de.audi.atip.log.LogChannel;
import de.audi.tghu.navi.app.cluster.ClusterService;
import org.dsi.ifc.androidauto2.DSIAndroidAuto2;
import org.dsi.ifc.androidauto2.DSIAndroidAuto2Listener;
import org.dsi.ifc.navigation.BapManeuverDescriptor;
import org.dsi.ifc.navigation.DistanceToNextManeuver;
import org.osgi.framework.BundleContext;
import org.osgi.framework.FrameworkUtil;
import org.osgi.framework.ServiceEvent;
import org.osgi.framework.ServiceListener;
import org.osgi.framework.ServiceReference;
import org.osgi.framework.Bundle;
import java.io.FileWriter;
import java.io.PrintWriter;
import java.text.SimpleDateFormat;
import java.util.Date;

public class AAManeuverProvider implements DSIAndroidAuto2Listener, ServiceListener {
    private static AAManeuverProvider instance;
    private DSIAndroidAuto2 dsi;
    private LogChannel log;
    private ClusterService clusterService;
    private boolean active;
    private int lastMainElement;
    private int lastDirection;
    private int lastDistance;
    private boolean dsiRetryScheduled;

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

    public AAManeuverProvider() {
        instance = this;
        log = getLogChannel();
        lastMainElement = 0;
        lastDirection = 0;
        lastDistance = 0;
        active = false;
        dsiRetryScheduled = false;
        debugLog("AAManeuverProvider.<init> entered");
        clusterService = findClusterService();
        if (clusterService != null) {
            log.log(100000, "cluster service found");
            debugLog("clusterService found");
        } else {
            log.log(1000000, "cluster service NOT found");
            debugLog("clusterService NOT found");
        }
        startDSI();
    }

    private LogChannel getLogChannel() {
        try {
            BundleContext bc = getBundleContext();
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
            Class<?> cls = Class.forName("de.audi.atip.base.IFrameworkAccess");
            java.lang.reflect.Field f = null;
            Class<?> c = cls;
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

    private BundleContext getBundleContext() {
        try {
            BundleContext bc = AAJavaBridge.getBundleContext();
            if (bc != null) {
                debugLog("AAManeuverProvider.getBundleContext: from AAJavaBridge");
                return bc;
            }
        } catch (Throwable t) {}
        try {
            Bundle b = FrameworkUtil.getBundle(AAManeuverProvider.class);
            if (b != null) {
                BundleContext bc2 = b.getBundleContext();
                debugLog("AAManeuverProvider.getBundleContext: from FrameworkUtil, bc=" + (bc2 != null ? "non-null" : "null"));
                return bc2;
            }
        } catch (Throwable t) {}
        debugLog("AAManeuverProvider.getBundleContext: returning null");
        return null;
    }

    private ClusterService findClusterService() {
        try {
            BundleContext bc = getBundleContext();
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
            Class<?> cls = Class.forName("de.audi.tghu.navi.app.cluster.ClusterService");
            java.lang.reflect.Field f = null;
            Class<?> c = cls;
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

    private void startDSI() {
        debugLog("AAManeuverProvider.startDSI() entered, active=" + active);
        try {
            BundleContext bc = getBundleContext();
            if (bc == null) {
                log.log(1000000, "no BundleContext for DSI lookup");
                debugLog("startDSI: bc is null");
                registerDsiRetry();
                return;
            }
            ServiceReference ref = bc.getServiceReference(DSIAndroidAuto2.class.getName());
            if (ref == null) {
                log.log(1000000, "DSIAndroidAuto2 service not available yet");
                debugLog("startDSI: DSIAndroidAuto2 service reference is null, registering retry listener");
                registerDsiRetry();
                return;
            }
            dsi = (DSIAndroidAuto2) bc.getService(ref);
            bc.ungetService(ref);
            if (dsi != null) {
                log.log(100000, "DSIAndroidAuto2 service obtained");
                debugLog("startDSI: DSIAndroidAuto2 service obtained");
                dsi.setNotification(this);
                debugLog("startDSI: dsi.setNotification(this) called");
                try {
                    org.dsi.ifc.androidauto2.ServiceConfiguration config = new org.dsi.ifc.androidauto2.ServiceConfiguration();
                    dsi.startService(config);
                    log.log(100000, "DSIAndroidAuto2 service started");
                    debugLog("startDSI: dsi.startService(config) called");
                    active = true;
                    debugLog("startDSI: active = true");
                } catch (Throwable t) {
                    log.log(1000000, "DSIAndroidAuto2 startService failed");
                    debugLog("startDSI: dsi.startService threw " + t);
                }
            } else {
                debugLog("startDSI: dsi is null after getService");
                registerDsiRetry();
            }
        } catch (Throwable t) {
            log.log(1000000, "startDSI failed");
            debugLog("startDSI: threw " + t);
            registerDsiRetry();
        }
    }

    private void registerDsiRetry() {
        if (dsiRetryScheduled) return;
        dsiRetryScheduled = true;
        try {
            BundleContext bc = getBundleContext();
            if (bc != null) {
                bc.addServiceListener(this, "(objectClass=" + DSIAndroidAuto2.class.getName() + ")");
                debugLog("registered ServiceListener for DSIAndroidAuto2 retry");
            }
        } catch (Throwable t) {
            debugLog("registerDsiRetry: threw " + t);
        }
    }

    public void serviceChanged(ServiceEvent event) {
        try {
            int type = event.getType();
            if (type == ServiceEvent.REGISTERED || type == ServiceEvent.MODIFIED) {
                ServiceReference ref = event.getServiceReference();
                String[] classes = (String[]) ref.getProperty("objectClass");
                for (int i = 0; i < classes.length; i++) {
                    if (DSIAndroidAuto2.class.getName().equals(classes[i])) {
                        debugLog("serviceChanged: DSIAndroidAuto2 became available, retrying startDSI");
                        dsiRetryScheduled = false;
                        try {
                            BundleContext bc = getBundleContext();
                            if (bc != null) bc.removeServiceListener(this);
                        } catch (Throwable t) {}
                        startDSI();
                        return;
                    }
                }
            }
        } catch (Throwable t) {
            debugLog("serviceChanged: threw " + t);
        }
    }

    public void updateNavigationNextTurnEvent(String roadName, int mainElement, int direction, int turnAngle, int turnNumber, int event) {
        debugLog("updateNavigationNextTurnEvent called, active=" + active + ", roadName='" + roadName + "' mainElement=" + mainElement + " direction=" + direction);
        if (!active) {
            debugLog("updateNavigationNextTurnEvent: not active, returning");
            return;
        }
        lastMainElement = mainElement;
        lastDirection = direction;
        lastDistance = 0;
        try {
            BapManeuverDescriptor[] desc = new BapManeuverDescriptor[1];
            desc[0] = new BapManeuverDescriptor(mainElement, direction, 0, null);
            if (clusterService != null) {
                clusterService.updateManeuverDescriptor(desc);
            }
            log.log(100000, "maneuver update");
            debugLog("updateNavigationNextTurnEvent: clusterService.updateManeuverDescriptor called");
        } catch (Throwable t) {
            log.log(1000000, "updateNavigationNextTurnEvent failed");
            debugLog("updateNavigationNextTurnEvent: threw " + t);
        }
    }

    public void updateNavigationNextTurnDistance(int distance, int unit, int remainingDistance) {
        debugLog("updateNavigationNextTurnDistance called, active=" + active + ", distance=" + distance);
        if (!active) {
            debugLog("updateNavigationNextTurnDistance: not active, returning");
            return;
        }
        lastDistance = distance;
        try {
            DistanceToNextManeuver dist = new DistanceToNextManeuver(true, distance, true, 0);
            if (clusterService != null) {
                clusterService.updateDistanceToNextManeuver(dist);
            }
            log.log(100000, "distance update");
            debugLog("updateNavigationNextTurnDistance: clusterService.updateDistanceToNextManeuver called");
        } catch (Throwable t) {
            log.log(1000000, "updateNavigationNextTurnDistance failed");
            debugLog("updateNavigationNextTurnDistance: threw " + t);
        }
    }

    public void videoFocusRequestNotification(int a, int b) {
        debugLog("videoFocusRequestNotification called");
    }
    public void videoAvailable(boolean a, int b) {
        debugLog("videoAvailable called");
    }
    public void audioFocusRequestNotification(int a, int b) {
        debugLog("audioFocusRequestNotification called");
    }
    public void audioAvailable(int a, boolean b, int c) {
        debugLog("audioAvailable called");
    }
    public void voiceSessionNotification(int a, int b) {}
    public void microphoneRequestNotification(int a, int b) {}
    public void navFocusRequestNotification(int a, int b) {}
    public void updateCallState(org.dsi.ifc.androidauto2.CallState[] a, int b) {}
    public void updateTelephonyState(org.dsi.ifc.androidauto2.TelephonyState a, int b) {}
    public void updateNowPlayingData(org.dsi.ifc.androidauto2.TrackData a, int b) {}
    public void updatePlaybackState(org.dsi.ifc.androidauto2.PlaybackInfo a, int b) {}
    public void updatePlayposition(int a, int b) {}
    public void updateCoverArtUrl(org.dsi.ifc.global.ResourceLocator a, int b) {}
    public void setExternalDestination(double a, double b, String c, String d, int e) {}
    public void bluetoothPairingRequest(String a, int b) {}
    public void asyncException(int a, String b, int c) {}
    public void registered(String a, int b) {}
    public void unregistered(String a, int b) {}

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
