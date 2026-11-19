package com.mhi2.androidadio;

import de.audi.atip.log.LogChannel;
import java.io.FileWriter;
import java.io.PrintWriter;
import java.text.SimpleDateFormat;
import java.util.Date;
import org.dsi.ifc.androidauto2.TrackData;
import org.dsi.ifc.androidauto2.PlaybackInfo;
import org.dsi.ifc.global.ResourceLocator;
import org.osgi.framework.BundleContext;

public class AAJavaBridge {
    private static boolean initialized;
    private static boolean started;
    private static BundleContext bundleContext;
    private static AATrackProvider trackProvider;
    private static AAManeuverProvider maneuverProvider;

    static {
        init();
    }

    public static void setBundleContext(BundleContext bc) {
        bundleContext = bc;
        debugLog("AAJavaBridge.setBundleContext called, bc=" + (bc != null ? "non-null" : "null"));
        if (initialized && !started) {
            startDSI();
        }
    }

    public static BundleContext getBundleContext() {
        return bundleContext;
    }

    public static AATrackProvider getTrackProvider() {
        return trackProvider;
    }

    public static AAManeuverProvider getManeuverProvider() {
        return maneuverProvider;
    }

    public static void debugLog(String msg) {
        try {
            SimpleDateFormat sdf = new SimpleDateFormat("HH:mm:ss.SSS");
            String line = sdf.format(new Date()) + " AAJavaBridge: " + msg;
            FileWriter fw = new FileWriter("/tmp/aacoverart.log", true);
            PrintWriter pw = new PrintWriter(fw);
            pw.println(line);
            pw.close();
        } catch (Throwable t) {}
    }

    public static void onNowPlayingData(TrackData trackData, int instanceId) {
        debugLog("AAJavaBridge.onNowPlayingData called");
        if (trackProvider != null) {
            trackProvider.handleNowPlayingData(trackData, instanceId);
        }
    }

    public static void onCoverArtUrl(ResourceLocator resourceLocator, int instanceId) {
        debugLog("AAJavaBridge.onCoverArtUrl called");
        if (trackProvider != null) {
            trackProvider.handleCoverArtUrl(resourceLocator, instanceId);
        }
    }

    public static void onNextTurnEvent(String roadName, int mainElement, int direction, int turnAngle, int turnNumber, int event) {
        debugLog("AAJavaBridge.onNextTurnEvent called");
        AAManeuverProvider.handleNextTurnEvent(roadName, mainElement, direction, turnAngle, turnNumber, event);
    }

    public static void onNextTurnDistance(int distance, int unit, int remainingDistance) {
        debugLog("AAJavaBridge.onNextTurnDistance called");
        AAManeuverProvider.handleNextTurnDistance(distance, unit, remainingDistance);
    }

    public static void init() {
        if (initialized) return;
        initialized = true;
        debugLog("AAJavaBridge.init() started, bundleContext=" + (bundleContext != null ? "set" : "null"));
        try {
            trackProvider = new AATrackProvider();
            debugLog("AATrackProvider created");
        } catch (Throwable t) {
            debugLog("AATrackProvider creation failed: " + t);
        }
        try {
            maneuverProvider = new AAManeuverProvider();
            debugLog("AAManeuverProvider created");
        } catch (Throwable t) {
            debugLog("AAManeuverProvider creation failed: " + t);
        }
        if (bundleContext != null && !started) {
            startDSI();
        }
        debugLog("AAJavaBridge.init() done");
    }

    public static void startDSI() {
        if (started) return;
        started = true;
        debugLog("AAJavaBridge.startDSI() started");
        if (trackProvider != null) {
            try {
                trackProvider.startDSI();
                debugLog("AATrackProvider.startDSI() called");
            } catch (Throwable t) {
                debugLog("AATrackProvider.startDSI() failed: " + t);
            }
        }
        debugLog("AAJavaBridge.startDSI() done");
    }

    private static class StubLogChannel extends de.audi.atip.log.LogChannel {
        public StubLogChannel() { super(); }
        public void log(int a, java.lang.String b, java.lang.Object c, java.lang.Object d, java.lang.Object e, java.lang.Object f, long g, long h, long i, int j, java.lang.Throwable k) {}
        public void log(int a, int b, java.lang.Object c, java.lang.Object d, java.lang.Object e, java.lang.Object f, long g, long h, long i, int j, java.lang.Throwable k) {}
        public boolean log(int a, java.lang.String b) { return false; }
    }
}
