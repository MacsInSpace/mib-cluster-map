package de.audi.app.terminalmode.smartphone.androidauto2;

import de.audi.app.terminalmode.IContext;
import de.audi.atip.log.LogChannel;
import com.mhi2.androidadio.AAJavaBridge;
import java.util.Vector;
import org.dsi.ifc.androidauto2.DSIAndroidAuto2Listener;
import org.dsi.ifc.androidauto2.TrackData;
import org.dsi.ifc.androidauto2.PlaybackInfo;
import org.dsi.ifc.androidauto2.CallState;
import org.dsi.ifc.androidauto2.TelephonyState;
import org.dsi.ifc.global.ResourceLocator;

public class AndroidAuto2ListenerDistributor implements DSIAndroidAuto2Listener {
    private static final String LOGCLASS = "AndroidAuto2ListenerDistributor";
    private LogChannel logger;
    private Vector listeners;
    private IContext context;
    private static boolean discoveryDone;

    public AndroidAuto2ListenerDistributor(IContext context) {
        this.context = context;
        this.listeners = new Vector();
        try {
            AAJavaBridge.setAppClass(this.getClass());
        } catch (Throwable t) {}
        try {
            this.logger = new StubLogChannel();
        } catch (Throwable t) {}
        debugLog("AndroidAuto2ListenerDistributor.<init> called");
        dumpObject(context, "IContext");
        discoverReferences(context);
    }

    public void addListener(DSIAndroidAuto2Listener[] listeners) {
        debugLog("AndroidAuto2ListenerDistributor.addListener called");
        if (listeners != null) {
            for (int i = 0; i < listeners.length; i++) {
                if (listeners[i] != null) {
                    StringBuffer lbl = new StringBuffer("listener[");
                    lbl.append(i);
                    lbl.append("]");
                    dumpObject(listeners[i], lbl.toString());
                    discoverReferences(listeners[i]);
                    if (AAJavaBridge.getAppClassLoader() == null) {
                        try {
                            AAJavaBridge.setAppClass(listeners[i].getClass());
                        } catch (Throwable t) {}
                    }
                    this.listeners.add(listeners[i]);
                }
            }
        }
        if (!discoveryDone) {
            discoveryDone = true;
            debugLog("Discovery phase complete");
        }
    }

    private void dumpObject(Object obj, String label) {
        if (obj == null) {
            StringBuffer sbn = new StringBuffer("DUMP ");
            sbn.append(label);
            sbn.append(" is null");
            debugLog(sbn.toString());
            return;
        }
        try {
            StringBuffer sb = new StringBuffer("DUMP ");
            sb.append(label);
            sb.append(" class=");
            sb.append(obj.getClass().getName());
            debugLog(sb.toString());

            java.lang.reflect.Method[] methods = obj.getClass().getMethods();
            for (int i = 0; i < methods.length; i++) {
                StringBuffer sm = new StringBuffer("  METHOD ");
                sm.append(methods[i].getName());
                sm.append("(");
                Class[] params = methods[i].getParameterTypes();
                for (int j = 0; j < params.length; j++) {
                    if (j > 0) sm.append(",");
                    sm.append(params[j].getName());
                }
                sm.append(") -> ");
                sm.append(methods[i].getReturnType().getName());
                debugLog(sm.toString());
            }

            Class cls = obj.getClass();
            while (cls != null) {
                java.lang.reflect.Field[] fields = cls.getDeclaredFields();
                for (int i = 0; i < fields.length; i++) {
                    try {
                        fields[i].setAccessible(true);
                        Object val = fields[i].get(obj);
                        StringBuffer sf = new StringBuffer("  FIELD ");
                        sf.append(fields[i].getName());
                        sf.append(" type=");
                        sf.append(fields[i].getType().getName());
                        sf.append(" value=");
                        sf.append(val != null ? val : "null");
                        debugLog(sf.toString());
                    } catch (Throwable t) {}
                }
                cls = cls.getSuperclass();
            }
        } catch (Throwable t) {
            StringBuffer sbt = new StringBuffer("DUMP ");
            sbt.append(label);
            sbt.append(" threw ");
            sbt.append(t);
            debugLog(sbt.toString());
        }
    }

    private void discoverReferences(Object start) {
        if (start == null) return;
        Vector current = new Vector();
        Vector next = new Vector();
        Vector visited = new Vector();
        current.addElement(start);
        int depth = 0;
        while (!current.isEmpty() && depth < 4) {
            for (int i = 0; i < current.size(); i++) {
                Object obj = current.elementAt(i);
                if (obj == null) continue;
                // Skip primitive wrappers and leaf types to avoid dead ends
                String objClsName = obj.getClass().getName();
                if ("java.lang.String".equals(objClsName)) continue;
                if ("java.lang.Number".equals(objClsName)) continue;
                if ("java.lang.Boolean".equals(objClsName)) continue;
                if ("java.lang.Character".equals(objClsName)) continue;
                if ("java.lang.Class".equals(objClsName)) continue;
                if (obj.getClass().isPrimitive()) continue;
                if ("java.lang.Integer".equals(objClsName)) continue;
                if ("java.lang.Long".equals(objClsName)) continue;
                if ("java.lang.Double".equals(objClsName)) continue;
                if ("java.lang.Float".equals(objClsName)) continue;
                if ("java.lang.Short".equals(objClsName)) continue;
                if ("java.lang.Byte".equals(objClsName)) continue;
                if ("java.lang.Void".equals(objClsName)) continue;
                boolean seen = false;
                for (int j = 0; j < visited.size(); j++) {
                    if (visited.elementAt(j) == obj) { seen = true; break; }
                }
                if (seen) continue;
                visited.addElement(obj);

                checkAndStore(obj);
                walkFields(obj, next);
            }
            current = next;
            next = new Vector();
            depth++;
        }
    }

    private void checkAndStore(Object obj) {
        if (obj == null) return;
        String clsName = obj.getClass().getName();

        try {
            Class dsiCls = Class.forName("org.dsi.ifc.androidauto2.DSIAndroidAuto2");
            if (dsiCls.isInstance(obj)) {
                AAJavaBridge.setDSI(obj);
                try {
                    java.lang.reflect.Method setNotif = dsiCls.getMethod(
                        "setNotification", new Class[]{int[].class, org.dsi.ifc.androidauto2.DSIAndroidAuto2Listener.class});
                    int[] attrs = new int[]{
                        dsiCls.getField("ATTR_NOWPLAYINGDATA").getInt(null),
                        dsiCls.getField("ATTR_PLAYBACKSTATE").getInt(null),
                        dsiCls.getField("ATTR_COVERARTURL").getInt(null)
                    };
                    setNotif.invoke(obj, new Object[]{attrs, AndroidAuto2ListenerDistributor.this});
                    debugLog("DSIAndroidAuto2 discovered, setNotification called with ATTR_COVERARTURL");
                } catch (Throwable t) {
                    StringBuffer sbf = new StringBuffer("DSIAndroidAuto2 setNotification failed: ");
                    sbf.append(t);
                    debugLog(sbf.toString());
                }
            }
        } catch (Throwable t) {}

        if ("de.audi.app.combi.bap.app.audio.CombiModuleAudio".equals(clsName)) {
            AAJavaBridge.setCombiModule(obj);
            AAJavaBridge.setMediaConnector(obj);
            try {
                Object tms = obj.getClass().getMethod("getTerminalModeService", new Class[0]).invoke(obj, new Object[0]);
                AAJavaBridge.setTerminalModeConnector(tms);
            } catch (Throwable t) {
                StringBuffer sbg = new StringBuffer("CombiModuleAudio.getTerminalModeService threw: ");
                sbg.append(t);
                debugLog(sbg.toString());
            }
            try {
                Object pm = obj.getClass().getMethod("getPictureManager", new Class[0]).invoke(obj, new Object[0]);
                AAJavaBridge.setPictureManager(pm);
            } catch (Throwable t) {
                StringBuffer sbc = new StringBuffer("CombiModuleAudio.getPictureManager threw: ");
                sbc.append(t);
                debugLog(sbc.toString());
            }
        }

        if ("de.audi.app.combi.bap.app.audio.AppConnectorTerminalMode".equals(clsName)) {
            AAJavaBridge.setTerminalModeConnector(obj);
        }

        if ("de.audi.app.combi.bap.app.audio.AppConnectorMedia".equals(clsName)) {
            AAJavaBridge.setMediaConnector(obj);
        }

        if ("de.audi.app.combi.bap.app.kombipictures.IPictureManager".equals(clsName) ||
            implementsInterface(obj, "de.audi.app.combi.bap.app.kombipictures.IPictureManager")) {
            AAJavaBridge.setPictureManager(obj);
        }
    }

    private boolean implementsInterface(Object obj, String ifaceName) {
        Class[] ifaces = obj.getClass().getInterfaces();
        for (int i = 0; i < ifaces.length; i++) {
            if (ifaceName.equals(ifaces[i].getName())) return true;
        }
        Class cls = obj.getClass().getSuperclass();
        while (cls != null) {
            Class[] moreIfaces = cls.getInterfaces();
            for (int i = 0; i < moreIfaces.length; i++) {
                if (ifaceName.equals(moreIfaces[i].getName())) return true;
            }
            cls = cls.getSuperclass();
        }
        return false;
    }

    private void walkFields(Object obj, Vector next) {
        try {
            Class cls = obj.getClass();
            while (cls != null) {
                java.lang.reflect.Field[] fields = cls.getDeclaredFields();
                for (int i = 0; i < fields.length; i++) {
                    try {
                        fields[i].setAccessible(true);
                        Object val = fields[i].get(obj);
                        if (val != null) next.addElement(val);
                    } catch (Throwable t) {}
                }
                cls = cls.getSuperclass();
            }
        } catch (Throwable t) {}
    }

    public void updateNowPlayingData(TrackData trackData, int instanceId) {
        debugLog("updateNowPlayingData received from DSI");
        try { AAJavaBridge.onNowPlayingData(trackData, instanceId); } catch (Throwable t) {}
        forwardNowPlayingData(trackData, instanceId);
    }

    public void updateCoverArtUrl(ResourceLocator resourceLocator, int instanceId) {
        debugLog("updateCoverArtUrl received from DSI");
        try { AAJavaBridge.onCoverArtUrl(resourceLocator, instanceId); } catch (Throwable t) {}
        forwardCoverArtUrl(resourceLocator, instanceId);
    }

    public void updateNavigationNextTurnEvent(String roadName, int mainElement, int direction, int turnAngle, int turnNumber, int event) {
        debugLog("updateNavigationNextTurnEvent received from DSI");
        try { AAJavaBridge.onNextTurnEvent(roadName, mainElement, direction, turnAngle, turnNumber, event); } catch (Throwable t) {}
        forwardNextTurnEvent(roadName, mainElement, direction, turnAngle, turnNumber, event);
    }

    public void updateNavigationNextTurnDistance(int distance, int unit, int remainingDistance) {
        debugLog("updateNavigationNextTurnDistance received from DSI");
        try { AAJavaBridge.onNextTurnDistance(distance, unit, remainingDistance); } catch (Throwable t) {}
        forwardNextTurnDistance(distance, unit, remainingDistance);
    }

    public void videoFocusRequestNotification(int a, int b) {
        forwardVideoFocusRequestNotification(a, b);
    }

    public void videoAvailable(boolean a, int b) {
        forwardVideoAvailable(a, b);
    }

    public void audioFocusRequestNotification(int a, int b) {
        forwardAudioFocusRequestNotification(a, b);
    }

    public void audioAvailable(int a, boolean b, int c) {
        forwardAudioAvailable(a, b, c);
    }

    public void voiceSessionNotification(int a, int b) {
        forwardVoiceSessionNotification(a, b);
    }
    public void microphoneRequestNotification(int a, int b) {
        forwardMicrophoneRequestNotification(a, b);
    }
    public void navFocusRequestNotification(int a, int b) {
        forwardNavFocusRequestNotification(a, b);
    }
    public void updateCallState(CallState[] a, int b) {
        forwardUpdateCallState(a, b);
    }
    public void updateTelephonyState(TelephonyState a, int b) {
        forwardUpdateTelephonyState(a, b);
    }
    public void updatePlaybackState(PlaybackInfo a, int b) {
        forwardUpdatePlaybackState(a, b);
    }
    public void updatePlayposition(int a, int b) {
        try { com.mhi2.androidadio.AAJavaBridge.onPlayPosition(a, b); } catch (Throwable t) {}
        forwardUpdatePlayposition(a, b);
    }
    public void setExternalDestination(double a, double b, String c, String d, int e) {
        forwardSetExternalDestination(a, b, c, d, e);
    }
    public void bluetoothPairingRequest(String a, int b) {
        forwardBluetoothPairingRequest(a, b);
    }
    public void asyncException(int a, String b, int c) {
        forwardAsyncException(a, b, c);
    }

    private void forwardNowPlayingData(TrackData trackData, int instanceId) {
        for (int i = 0; i < listeners.size(); i++) {
            DSIAndroidAuto2Listener l = (DSIAndroidAuto2Listener) listeners.elementAt(i);
            if (l != null) {
                try { l.updateNowPlayingData(trackData, instanceId); } catch (Throwable t) {}
            }
        }
    }

    private void forwardCoverArtUrl(ResourceLocator resourceLocator, int instanceId) {
        for (int i = 0; i < listeners.size(); i++) {
            DSIAndroidAuto2Listener l = (DSIAndroidAuto2Listener) listeners.elementAt(i);
            if (l != null) {
                try { l.updateCoverArtUrl(resourceLocator, instanceId); } catch (Throwable t) {}
            }
        }
    }

    private void forwardNextTurnEvent(String roadName, int mainElement, int direction, int turnAngle, int turnNumber, int event) {
        for (int i = 0; i < listeners.size(); i++) {
            DSIAndroidAuto2Listener l = (DSIAndroidAuto2Listener) listeners.elementAt(i);
            if (l != null) {
                try { l.updateNavigationNextTurnEvent(roadName, mainElement, direction, turnAngle, turnNumber, event); } catch (Throwable t) {}
            }
        }
    }

    private void forwardNextTurnDistance(int distance, int unit, int remainingDistance) {
        for (int i = 0; i < listeners.size(); i++) {
            DSIAndroidAuto2Listener l = (DSIAndroidAuto2Listener) listeners.elementAt(i);
            if (l != null) {
                try { l.updateNavigationNextTurnDistance(distance, unit, remainingDistance); } catch (Throwable t) {}
            }
        }
    }

    private void forwardVideoFocusRequestNotification(int a, int b) {
        for (int i = 0; i < listeners.size(); i++) {
            DSIAndroidAuto2Listener l = (DSIAndroidAuto2Listener) listeners.elementAt(i);
            if (l != null) {
                try { l.videoFocusRequestNotification(a, b); } catch (Throwable t) {}
            }
        }
    }

    private void forwardVideoAvailable(boolean a, int b) {
        for (int i = 0; i < listeners.size(); i++) {
            DSIAndroidAuto2Listener l = (DSIAndroidAuto2Listener) listeners.elementAt(i);
            if (l != null) {
                try { l.videoAvailable(a, b); } catch (Throwable t) {}
            }
        }
    }

    private void forwardAudioFocusRequestNotification(int a, int b) {
        for (int i = 0; i < listeners.size(); i++) {
            DSIAndroidAuto2Listener l = (DSIAndroidAuto2Listener) listeners.elementAt(i);
            if (l != null) {
                try { l.audioFocusRequestNotification(a, b); } catch (Throwable t) {}
            }
        }
    }

    private void forwardAudioAvailable(int a, boolean b, int c) {
        for (int i = 0; i < listeners.size(); i++) {
            DSIAndroidAuto2Listener l = (DSIAndroidAuto2Listener) listeners.elementAt(i);
            if (l != null) {
                try { l.audioAvailable(a, b, c); } catch (Throwable t) {}
            }
        }
    }

    private void forwardVoiceSessionNotification(int a, int b) {
        for (int i = 0; i < listeners.size(); i++) {
            DSIAndroidAuto2Listener l = (DSIAndroidAuto2Listener) listeners.elementAt(i);
            if (l != null) {
                try { l.voiceSessionNotification(a, b); } catch (Throwable t) {}
            }
        }
    }

    private void forwardMicrophoneRequestNotification(int a, int b) {
        for (int i = 0; i < listeners.size(); i++) {
            DSIAndroidAuto2Listener l = (DSIAndroidAuto2Listener) listeners.elementAt(i);
            if (l != null) {
                try { l.microphoneRequestNotification(a, b); } catch (Throwable t) {}
            }
        }
    }

    private void forwardNavFocusRequestNotification(int a, int b) {
        for (int i = 0; i < listeners.size(); i++) {
            DSIAndroidAuto2Listener l = (DSIAndroidAuto2Listener) listeners.elementAt(i);
            if (l != null) {
                try { l.navFocusRequestNotification(a, b); } catch (Throwable t) {}
            }
        }
    }

    private void forwardUpdateCallState(CallState[] a, int b) {
        for (int i = 0; i < listeners.size(); i++) {
            DSIAndroidAuto2Listener l = (DSIAndroidAuto2Listener) listeners.elementAt(i);
            if (l != null) {
                try { l.updateCallState(a, b); } catch (Throwable t) {}
            }
        }
    }

    private void forwardUpdateTelephonyState(TelephonyState a, int b) {
        for (int i = 0; i < listeners.size(); i++) {
            DSIAndroidAuto2Listener l = (DSIAndroidAuto2Listener) listeners.elementAt(i);
            if (l != null) {
                try { l.updateTelephonyState(a, b); } catch (Throwable t) {}
            }
        }
    }

    private void forwardUpdatePlaybackState(PlaybackInfo a, int b) {
        for (int i = 0; i < listeners.size(); i++) {
            DSIAndroidAuto2Listener l = (DSIAndroidAuto2Listener) listeners.elementAt(i);
            if (l != null) {
                try { l.updatePlaybackState(a, b); } catch (Throwable t) {}
            }
        }
    }

    private void forwardUpdatePlayposition(int a, int b) {
        for (int i = 0; i < listeners.size(); i++) {
            DSIAndroidAuto2Listener l = (DSIAndroidAuto2Listener) listeners.elementAt(i);
            if (l != null) {
                try { l.updatePlayposition(a, b); } catch (Throwable t) {}
            }
        }
    }

    private void forwardSetExternalDestination(double a, double b, String c, String d, int e) {
        for (int i = 0; i < listeners.size(); i++) {
            DSIAndroidAuto2Listener l = (DSIAndroidAuto2Listener) listeners.elementAt(i);
            if (l != null) {
                try { l.setExternalDestination(a, b, c, d, e); } catch (Throwable t) {}
            }
        }
    }

    private void forwardBluetoothPairingRequest(String a, int b) {
        for (int i = 0; i < listeners.size(); i++) {
            DSIAndroidAuto2Listener l = (DSIAndroidAuto2Listener) listeners.elementAt(i);
            if (l != null) {
                try { l.bluetoothPairingRequest(a, b); } catch (Throwable t) {}
            }
        }
    }

    private void forwardAsyncException(int a, String b, int c) {
        for (int i = 0; i < listeners.size(); i++) {
            DSIAndroidAuto2Listener l = (DSIAndroidAuto2Listener) listeners.elementAt(i);
            if (l != null) {
                try { l.asyncException(a, b, c); } catch (Throwable t) {}
            }
        }
    }

    private void debugLog(String msg) {
        try {
            java.text.SimpleDateFormat sdf = new java.text.SimpleDateFormat("HH:mm:ss.SSS");
            StringBuffer sb = new StringBuffer();
            sb.append(sdf.format(new java.util.Date()));
            sb.append(" AAListenerDistributor: ");
            sb.append(msg);
            java.io.FileWriter fw = new java.io.FileWriter("/tmp/aacoverart.log", true);
            java.io.PrintWriter pw = new java.io.PrintWriter(fw);
            pw.println(sb.toString());
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
