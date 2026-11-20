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
    }

    public void addListener(DSIAndroidAuto2Listener[] listeners) {
        debugLog("AndroidAuto2ListenerDistributor.addListener called");
        if (listeners != null) {
            for (int i = 0; i < listeners.length; i++) {
                if (listeners[i] != null) {
                    this.listeners.add(listeners[i]);
                }
            }
        }
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
