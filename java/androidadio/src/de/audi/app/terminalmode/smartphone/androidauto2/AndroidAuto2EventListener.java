package de.audi.app.terminalmode.smartphone.androidauto2;

import de.audi.app.terminalmode.events.IEventBus;
import de.audi.atip.log.LogChannel;
import com.mhi2.androidadio.AAJavaBridge;
import de.audi.app.terminalmode.dsi.androidauto2.DSIAndroidAuto2DefaultListener;
import org.dsi.ifc.androidauto2.DSIAndroidAuto2;
import org.dsi.ifc.androidauto2.TrackData;
import org.dsi.ifc.androidauto2.PlaybackInfo;
import org.dsi.ifc.global.ResourceLocator;

public class AndroidAuto2EventListener extends DSIAndroidAuto2DefaultListener {

    private final IEventBus eventBus;
    private final LogChannel lc;
    private DSIAndroidAuto2 dsi;

    public AndroidAuto2EventListener(IEventBus eventBus, LogChannel lc, DSIAndroidAuto2 dsi) {
        this.eventBus = eventBus;
        this.lc = lc;
        this.dsi = dsi;
        try {
            AAJavaBridge.setDSI(dsi);
            int attrNowPlaying = getAttrInt(dsi, "ATTR_NOWPLAYINGDATA");
            int attrPlaybackState = getAttrInt(dsi, "ATTR_PLAYBACKSTATE");
            int attrCoverArtUrl = getAttrInt(dsi, "ATTR_COVERARTURL");
            if (attrNowPlaying >= 0 && attrPlaybackState >= 0 && attrCoverArtUrl >= 0) {
                dsi.setNotification(new int[]{new Integer(attrNowPlaying), new Integer(attrPlaybackState), new Integer(attrCoverArtUrl)}, this);
            }
        } catch (Throwable t) {}
    }

    private int getAttrInt(DSIAndroidAuto2 dsiObj, String name) {
        try {
            java.lang.reflect.Field f = dsiObj.getClass().getField(name);
            return f.getInt(dsiObj);
        } catch (Throwable t) {
            return -1;
        }
    }

    public void updateNowPlayingData(TrackData trackData, int instanceId) {
        try { AAJavaBridge.onNowPlayingData(trackData, instanceId); } catch (Throwable t) {}
    }

    public void updateCoverArtUrl(ResourceLocator resourceLocator, int instanceId) {
        try { AAJavaBridge.onCoverArtUrl(resourceLocator, instanceId); } catch (Throwable t) {}
    }

    public void updateNavigationNextTurnEvent(java.lang.String roadName, int mainElement, int direction, int turnAngle, int turnNumber, int event) {
        try { AAJavaBridge.onNextTurnEvent(roadName, mainElement, direction, turnAngle, turnNumber, event); } catch (Throwable t) {}
    }

    public void updateNavigationNextTurnDistance(int distance, int unit, int remainingDistance) {
        try { AAJavaBridge.onNextTurnDistance(distance, unit, remainingDistance); } catch (Throwable t) {}
    }

    public void updatePlaybackState(PlaybackInfo a, int b) {
    }

    public void updatePlayposition(int a, int b) {
    }

    public void asyncException(int a, java.lang.String b, int c) {
    }
    public void videoFocusNotification(int a, boolean b) {
    }
    public void audioFocusNotification(int a, boolean b) {
    }
    public void microphoneNotification(int a, boolean b) {
    }
    public void navFocusNotification(int a, boolean b) {
    }
    public void startService(org.dsi.ifc.androidauto2.ServiceConfiguration a) {
    }
    public void postButtonEvent(int a, int b) {
    }
    public void postTouchEvent(int a, org.dsi.ifc.androidauto2.TouchEvent[] b, int c, int d) {
    }
    public void postRotaryEvent(int a) {
    }
    public void setNightMode(boolean a) {
    }
    public void bluetoothPairingResponse(boolean a) {
    }
    public void bluetoothAuthenticationData(java.lang.String a) {
    }
}
