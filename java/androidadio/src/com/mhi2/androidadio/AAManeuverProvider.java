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
import org.osgi.framework.ServiceReference;
import org.osgi.framework.Bundle;

public class AAManeuverProvider implements DSIAndroidAuto2Listener {
    private static AAManeuverProvider instance;
    private DSIAndroidAuto2 dsi;
    private LogChannel log;
    private ClusterService clusterService;
    private boolean active;
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

    public AAManeuverProvider() {
        instance = this;
        log = getLogChannel();
        lastMainElement = 0;
        lastDirection = 0;
        lastDistance = 0;
        active = false;
        clusterService = findClusterService();
        if (clusterService != null) {
            log.log(100000, "cluster service found");
        } else {
            log.log(1000000, "cluster service NOT found");
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
            if (bc != null) return bc;
        } catch (Throwable t) {}
        try {
            Bundle b = FrameworkUtil.getBundle(AAManeuverProvider.class);
            if (b != null) return b.getBundleContext();
        } catch (Throwable t) {}
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
                        return (ClusterService) svc;
                    }
                    bc.ungetService(ref);
                }
            }
        } catch (Throwable t) {}
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
                if (inst != null && inst instanceof ClusterService) return (ClusterService) inst;
            }
        } catch (Throwable t) {}
        return null;
    }

    private void startDSI() {
        try {
            BundleContext bc = getBundleContext();
            if (bc == null) {
                log.log(1000000, "no BundleContext for DSI lookup");
                return;
            }
            ServiceReference ref = bc.getServiceReference(DSIAndroidAuto2.class.getName());
            if (ref == null) {
                log.log(1000000, "DSIAndroidAuto2 service not available yet");
                return;
            }
            dsi = (DSIAndroidAuto2) bc.getService(ref);
            bc.ungetService(ref);
            if (dsi != null) {
                log.log(100000, "DSIAndroidAuto2 service obtained");
                dsi.setNotification(this);
                try {
                    org.dsi.ifc.androidauto2.ServiceConfiguration config = new org.dsi.ifc.androidauto2.ServiceConfiguration();
                    dsi.startService(config);
                    log.log(100000, "DSIAndroidAuto2 service started");
                } catch (Throwable t) {
                    log.log(1000000, "DSIAndroidAuto2 startService failed");
                }
                active = true;
            }
        } catch (Throwable t) {
            log.log(1000000, "startDSI failed");
        }
    }

    public void updateNavigationNextTurnEvent(String roadName, int mainElement, int direction, int turnAngle, int turnNumber, int event) {
        if (!active) return;
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
        } catch (Throwable t) {
            log.log(1000000, "updateNavigationNextTurnEvent failed");
        }
    }

    public void updateNavigationNextTurnDistance(int distance, int unit, int remainingDistance) {
        if (!active) return;
        lastDistance = distance;
        try {
            DistanceToNextManeuver dist = new DistanceToNextManeuver(true, distance, true, 0);
            if (clusterService != null) {
                clusterService.updateDistanceToNextManeuver(dist);
            }
            log.log(100000, "distance update");
        } catch (Throwable t) {
            log.log(1000000, "updateNavigationNextTurnDistance failed");
        }
    }

    public void videoFocusRequestNotification(int a, int b) {}
    public void videoAvailable(boolean a, int b) {}
    public void audioFocusRequestNotification(int a, int b) {}
    public void audioAvailable(int a, boolean b, int c) {}
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

    private static class StubLogChannel extends de.audi.atip.log.LogChannel {
        public StubLogChannel() { super(); }
        public void log(int a, java.lang.String b, java.lang.Object c, java.lang.Object d, java.lang.Object e, java.lang.Object f, long g, long h, long i, int j, java.lang.Throwable k) {}
        public void log(int a, int b, java.lang.Object c, java.lang.Object d, java.lang.Object e, java.lang.Object f, long g, long h, long i, int j, java.lang.Throwable k) {}
        public boolean log(int a, java.lang.String b) { return false; }
    }
}
