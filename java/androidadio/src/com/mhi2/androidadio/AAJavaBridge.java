package com.mhi2.androidadio;

import de.audi.atip.log.LogChannel;

public class AAJavaBridge {
    private static boolean initialized;

    static {
        init();
    }

    public static void init() {
        if (initialized) return;
        initialized = true;
        LogChannel log = null;
        try {
            log = new StubLogChannel();
        } catch (Throwable t) {}
        try {
            new AATrackProvider();
            logIf(log, "AATrackProvider started");
        } catch (Throwable t) {
            logIf(log, "AATrackProvider failed");
        }
        try {
            new AAManeuverProvider();
            logIf(log, "AAManeuverProvider started");
        } catch (Throwable t) {
            logIf(log, "AAManeuverProvider failed");
        }
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
