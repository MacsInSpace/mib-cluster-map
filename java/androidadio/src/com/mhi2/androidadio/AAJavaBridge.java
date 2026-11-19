package com.mhi2.androidadio;

import de.audi.atip.log.LogChannel;
import java.io.FileWriter;
import java.io.IOException;
import java.io.PrintWriter;
import java.text.SimpleDateFormat;
import java.util.Date;
import org.osgi.framework.BundleContext;

public class AAJavaBridge {
    private static boolean initialized;
    private static BundleContext bundleContext;

    static {
        init();
    }

    public static void setBundleContext(BundleContext bc) {
        bundleContext = bc;
        debugLog("AAJavaBridge.setBundleContext called, bc=" + (bc != null ? "non-null" : "null"));
    }

    public static BundleContext getBundleContext() {
        return bundleContext;
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

    public static void init() {
        if (initialized) return;
        initialized = true;
        debugLog("AAJavaBridge.init() started");
        LogChannel log = null;
        try {
            log = new StubLogChannel();
        } catch (Throwable t) {}
        try {
            new AATrackProvider();
            logIf(log, "AATrackProvider started");
            debugLog("AATrackProvider started");
        } catch (Throwable t) {
            logIf(log, "AATrackProvider failed");
            debugLog("AATrackProvider failed: " + t);
        }
        try {
            new AAManeuverProvider();
            logIf(log, "AAManeuverProvider started");
            debugLog("AAManeuverProvider started");
        } catch (Throwable t) {
            logIf(log, "AAManeuverProvider failed");
            debugLog("AAManeuverProvider failed: " + t);
        }
        debugLog("AAJavaBridge.init() done, bundleContext=" + (bundleContext != null ? "set" : "null"));
    }

    private static void logIf(LogChannel log, String msg) {
        if (log != null) {
            try { log.log(100000, msg); } catch (Throwable t) {}
        }
        System.out.println(msg);
    }

    private static class StubLogChannel extends de.audi.atip.log.LogChannel {
        public StubLogChannel() { super(); }
        public void log(int a, java.lang.String b, java.lang.Object c, java.lang.Object d, java.lang.Object e, java.lang.Object f, long g, long h, long i, int j, java.lang.Throwable k) {}
        public void log(int a, int b, java.lang.Object c, java.lang.Object d, java.lang.Object e, java.lang.Object f, long g, long h, long i, int j, java.lang.Throwable k) {}
        public boolean log(int a, java.lang.String b) { return false; }
    }
}
