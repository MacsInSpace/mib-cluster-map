package com.mhi2.androidadio;

import java.io.FileWriter;
import java.io.PrintWriter;
import java.lang.reflect.Method;
import java.text.SimpleDateFormat;
import java.util.Date;
import org.dsi.ifc.androidauto2.TrackData;
import org.dsi.ifc.global.ResourceLocator;

public class AAJavaBridge {
    private static boolean initialized;
    private static boolean started;
    private static Object bundleContext;
    private static Object trackProvider;
    private static Object maneuverProvider;
    private static Class appClass;
    private static ClassLoader appClassLoader;
    private static Object combiModule;
    private static Object dsiAndroidAuto2;
    private static Object terminalModeConnector;
    private static Object mediaConnector;
    private static Object pictureManager;

    static {
        init();
    }

    public static void setAppClass(Class cls) {
        appClass = cls;
        if (cls != null) {
            appClassLoader = cls.getClassLoader();
        }
        StringBuffer sb = new StringBuffer("AAJavaBridge.setAppClass called, appClass=");
        sb.append(appClass != null ? "set" : "null");
        sb.append(" appClassLoader=");
        sb.append(appClassLoader != null ? "set" : "null");
        debugLog(sb.toString());
    }

    public static Class getAppClass() {
        return appClass;
    }

    public static ClassLoader getAppClassLoader() {
        return appClassLoader;
    }

    public static void setCombiModule(Object module) {
        combiModule = module;
        StringBuffer sb = new StringBuffer("AAJavaBridge.setCombiModule called, module=");
        sb.append(module != null ? "non-null" : "null");
        debugLog(sb.toString());
    }

    public static Object getCombiModule() {
        return combiModule;
    }

    public static void setDSI(Object dsi) {
        dsiAndroidAuto2 = dsi;
        StringBuffer sb = new StringBuffer("AAJavaBridge.setDSI called, dsi=");
        sb.append(dsi != null ? "non-null" : "null");
        debugLog(sb.toString());
    }

    public static Object getDSI() {
        return dsiAndroidAuto2;
    }

    public static void setTerminalModeConnector(Object connector) {
        terminalModeConnector = connector;
        StringBuffer sb = new StringBuffer("AAJavaBridge.setTerminalModeConnector called, connector=");
        sb.append(connector != null ? "non-null" : "null");
        debugLog(sb.toString());
    }

    public static Object getTerminalModeConnector() {
        return terminalModeConnector;
    }

    public static void setMediaConnector(Object connector) {
        mediaConnector = connector;
        StringBuffer sb = new StringBuffer("AAJavaBridge.setMediaConnector called, connector=");
        sb.append(connector != null ? "non-null" : "null");
        debugLog(sb.toString());
    }

    public static Object getMediaConnector() {
        return mediaConnector;
    }

    public static void setPictureManager(Object pm) {
        pictureManager = pm;
        StringBuffer sb = new StringBuffer("AAJavaBridge.setPictureManager called, pm=");
        sb.append(pm != null ? "non-null" : "null");
        debugLog(sb.toString());
    }

    public static Object getPictureManager() {
        return pictureManager;
    }

    public static void setBundleContext(Object bc) {
        bundleContext = bc;
        StringBuffer sb = new StringBuffer("AAJavaBridge.setBundleContext called, bc=");
        sb.append(bc != null ? "non-null" : "null");
        debugLog(sb.toString());
        if (initialized && !started) {
            startDSI();
        }
    }

    public static Object getBundleContext() {
        return bundleContext;
    }

    public static Object getTrackProvider() {
        return trackProvider;
    }

    public static Object getManeuverProvider() {
        return maneuverProvider;
    }

    public static void debugLog(String msg) {
        try {
            SimpleDateFormat sdf = new SimpleDateFormat("HH:mm:ss.SSS");
            StringBuffer sb = new StringBuffer();
            sb.append(sdf.format(new Date()));
            sb.append(" AAJavaBridge: ");
            sb.append(msg);
            FileWriter fw = new FileWriter("/tmp/aacoverart.log", true);
            PrintWriter pw = new PrintWriter(fw);
            pw.println(sb.toString());
            pw.close();
        } catch (Throwable t) {}
    }

    public static void onNowPlayingData(TrackData trackData, int instanceId) {
        debugLog("AAJavaBridge.onNowPlayingData called");
        if (trackProvider != null) {
            try {
                java.lang.reflect.Method m = trackProvider.getClass().getMethod(
                    "handleNowPlayingData", new Class[]{TrackData.class, int.class});
                m.invoke(trackProvider, new Object[]{trackData, new Integer(instanceId)});
            } catch (Throwable t) {
                StringBuffer sb = new StringBuffer("onNowPlayingData: trackProvider.handleNowPlayingData threw ");
                sb.append(t);
                debugLog(sb.toString());
            }
        }
    }

    public static void onCoverArtUrl(ResourceLocator resourceLocator, int instanceId) {
        debugLog("AAJavaBridge.onCoverArtUrl called");
        if (trackProvider != null) {
            try {
                java.lang.reflect.Method m = trackProvider.getClass().getMethod(
                    "handleCoverArtUrl", new Class[]{ResourceLocator.class, int.class});
                m.invoke(trackProvider, new Object[]{resourceLocator, new Integer(instanceId)});
            } catch (Throwable t) {
                StringBuffer sb = new StringBuffer("onCoverArtUrl: trackProvider.handleCoverArtUrl threw ");
                sb.append(t);
                debugLog(sb.toString());
            }
        }
    }

    public static void onNextTurnEvent(String roadName, int mainElement, int direction, int turnAngle, int turnNumber, int event) {
        debugLog("AAJavaBridge.onNextTurnEvent called");
        if (maneuverProvider != null) {
            try {
                java.lang.reflect.Method m = maneuverProvider.getClass().getMethod(
                    "handleNextTurnEvent", new Class[]{String.class, int.class, int.class, int.class, int.class, int.class});
                m.invoke(maneuverProvider, new Object[]{roadName, new Integer(mainElement), new Integer(direction), new Integer(turnAngle), new Integer(turnNumber), new Integer(event)});
            } catch (Throwable t) {
                StringBuffer sb = new StringBuffer("onNextTurnEvent: maneuverProvider.handleNextTurnEvent threw ");
                sb.append(t);
                debugLog(sb.toString());
            }
        }
    }

    public static void onNextTurnDistance(int distance, int unit, int remainingDistance) {
        debugLog("AAJavaBridge.onNextTurnDistance called");
        if (maneuverProvider != null) {
            try {
                java.lang.reflect.Method m = maneuverProvider.getClass().getMethod(
                    "handleNextTurnDistance", new Class[]{int.class, int.class, int.class});
                m.invoke(maneuverProvider, new Object[]{new Integer(distance), new Integer(unit), new Integer(remainingDistance)});
            } catch (Throwable t) {
                StringBuffer sb = new StringBuffer("onNextTurnDistance: maneuverProvider.handleNextTurnDistance threw ");
                sb.append(t);
                debugLog(sb.toString());
            }
        }
    }

    public static void init() {
        if (initialized) return;
        initialized = true;
        StringBuffer sb = new StringBuffer("AAJavaBridge.init() started, bundleContext=");
        sb.append(bundleContext != null ? "set" : "null");
        debugLog(sb.toString());
        try {
            trackProvider = new AATrackProvider();
            debugLog("AATrackProvider created");
        } catch (Throwable t) {
            StringBuffer sb2 = new StringBuffer("AATrackProvider creation failed: ");
            sb2.append(t);
            debugLog(sb2.toString());
        }
        try {
            maneuverProvider = new AAManeuverProvider();
            debugLog("AAManeuverProvider created");
        } catch (Throwable t) {
            StringBuffer sb2 = new StringBuffer("AAManeuverProvider creation failed: ");
            sb2.append(t);
            debugLog(sb2.toString());
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
                java.lang.reflect.Method m = trackProvider.getClass().getMethod("startDSI", new Class[0]);
                m.invoke(trackProvider, new Object[0]);
                debugLog("AATrackProvider.startDSI() called");
            } catch (Throwable t) {
                StringBuffer sb = new StringBuffer("AATrackProvider.startDSI() failed: ");
                sb.append(t);
                debugLog(sb.toString());
            }
        }
        debugLog("AAJavaBridge.startDSI() done");
    }
}
