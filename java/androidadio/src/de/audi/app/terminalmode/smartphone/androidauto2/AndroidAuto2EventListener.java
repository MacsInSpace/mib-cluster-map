package de.audi.app.terminalmode.smartphone.androidauto2;

import com.mhi2.androidadio.AAJavaBridge;
import de.audi.app.terminalmode.dsi.androidauto2.DSIAndroidAuto2DefaultListener;
import de.audi.app.terminalmode.events.IEventBus;
import de.audi.app.terminalmode.events.PlayPositionLogger;
import de.audi.app.terminalmode.events.PlayPositionLoggerConfiguration;
import de.audi.app.terminalmode.events.PlayPositionLogEvent;
import de.audi.app.terminalmode.events.PlayPositionEvent;
import de.audi.app.terminalmode.events.PlaybackInfoChangedEvent;
import de.audi.app.terminalmode.events.TrackDataChangedEvent;
import de.audi.app.terminalmode.events.TrackPlayPositionEvent;
import de.audi.atip.log.LogChannel;
import org.dsi.ifc.androidauto2.DSIAndroidAuto2;
import org.dsi.ifc.androidauto2.PlaybackInfo;
import org.dsi.ifc.androidauto2.TrackData;
import org.dsi.ifc.global.ResourceLocator;

public class AndroidAuto2EventListener extends DSIAndroidAuto2DefaultListener {

    private static final java.lang.String LOGCLASS = "AndroidAuto2EventListener";

    private final de.audi.app.terminalmode.events.IEventBus eventBus;
    private final de.audi.atip.log.LogChannel lc;
    private volatile de.audi.app.terminalmode.events.TrackPlayPositionEvent notifiedPlayPosition;
    private final de.audi.app.terminalmode.events.PlayPositionLogger playPositionLogger;

    public AndroidAuto2EventListener(de.audi.app.terminalmode.events.IEventBus eventBus, de.audi.atip.log.LogChannel lc, org.dsi.ifc.androidauto2.DSIAndroidAuto2 dsi) {
        super();
        this.eventBus = eventBus;
        this.lc = lc;
        try {
            com.mhi2.androidadio.AAJavaBridge.setDSI(dsi);
        } catch (Throwable t) {}
        dsi.setNotification(new int[]{DSIAndroidAuto2.ATTR_NOWPLAYINGDATA, DSIAndroidAuto2.ATTR_PLAYBACKSTATE, DSIAndroidAuto2.ATTR_COVERARTURL}, this);
        de.audi.app.terminalmode.events.PlayPositionLoggerConfiguration config = new de.audi.app.terminalmode.events.PlayPositionLoggerConfiguration();
        config.setPlayPositionLogEvent(de.audi.app.terminalmode.events.PlayPositionEvent.STARTUP, new de.audi.app.terminalmode.events.PlayPositionLogEvent(lc, 1000000, 3));
        config.setPlayPositionLogEvent(de.audi.app.terminalmode.events.PlayPositionEvent.PLAYBACK_STATE_CHANGED, new de.audi.app.terminalmode.events.PlayPositionLogEvent(lc, 1000000, 2));
        config.setPlayPositionLogEvent(de.audi.app.terminalmode.events.PlayPositionEvent.TRACK_CHANGED, new de.audi.app.terminalmode.events.PlayPositionLogEvent(lc, 1000000, 3));
        config.setPlayPositionLogEvent(de.audi.app.terminalmode.events.PlayPositionEvent.ILLEGAL_PLAYPOSITION, new de.audi.app.terminalmode.events.PlayPositionLogEvent(lc, 10000, 3));
        config.setPlayPositionLogEvent(de.audi.app.terminalmode.events.PlayPositionEvent.TO_LATE_PLAYPOSITION, new de.audi.app.terminalmode.events.PlayPositionLogEvent(lc, 10000, 3));
        this.playPositionLogger = new de.audi.app.terminalmode.events.PlayPositionLogger(config);
    }

    public void asyncException(int errCode, java.lang.String msg, int requestType) {
        java.lang.StringBuffer sb = new java.lang.StringBuffer();
        sb.append("<- [AndroidAuto2EventListener.asyncException] errCode='");
        sb.append(java.lang.String.valueOf(errCode));
        sb.append("' msg='");
        sb.append(java.lang.String.valueOf(msg));
        sb.append("' requestType='");
        sb.append(java.lang.String.valueOf(requestType));
        sb.append("'");
        lc.log(10000, sb.toString(), LOGCLASS);
    }

    public void updateNowPlayingData(org.dsi.ifc.androidauto2.TrackData trackData, int instanceId) {
        if (isValid(instanceId)) {
            de.audi.app.terminalmode.events.TrackDataChangedEvent.Builder builder = new de.audi.app.terminalmode.events.TrackDataChangedEvent.Builder();
            builder.setAlbum(trackData.getAlbum());
            builder.setArtist(trackData.getArtist());
            builder.setComposer(trackData.getComposer());
            builder.setDuration(trackData.getDuration());
            builder.setGenre(trackData.getGenre());
            builder.setTitle(trackData.getTitle());
            de.audi.app.terminalmode.events.TrackDataChangedEvent event = builder.build();
            lc.log(1000000, "<- [AndroidAuto2EventListener.updateNowPlayingData] %2", LOGCLASS, event);
            playPositionLogger.trackChanged();
            eventBus.updateNowPlayingData(event);
            de.audi.app.terminalmode.events.TrackPlayPositionEvent positionEvent = new de.audi.app.terminalmode.events.TrackPlayPositionEvent(0, trackData.getDuration() / 1000);
            notifyPlayPosition(positionEvent);
        }
    }

    public void updatePlaybackState(org.dsi.ifc.androidauto2.PlaybackInfo playbackInfo, int instanceId) {
        if (isValid(instanceId)) {
            de.audi.app.terminalmode.events.PlaybackInfoChangedEvent.Builder builder = new de.audi.app.terminalmode.events.PlaybackInfoChangedEvent.Builder();
            builder.setPlaybackState(convert(playbackInfo.getStatus()));
            de.audi.app.terminalmode.events.PlaybackInfoChangedEvent event = builder.build();
            lc.log(1000000, "<- [AndroidAuto2EventListener.updateNowPlayingData] %2", LOGCLASS, event);
            playPositionLogger.playbackStateChanged();
        }
    }

    private de.audi.app.terminalmode.events.PlaybackInfoChangedEvent.PlaybackState convert(int status) {
        switch (status) {
            case 0: return de.audi.app.terminalmode.events.PlaybackInfoChangedEvent.PlaybackState.STOPPED;
            case 1: return de.audi.app.terminalmode.events.PlaybackInfoChangedEvent.PlaybackState.PLAYING;
            case 2: return de.audi.app.terminalmode.events.PlaybackInfoChangedEvent.PlaybackState.SEEKBACKWARD;
            case 3: return de.audi.app.terminalmode.events.PlaybackInfoChangedEvent.PlaybackState.SEEKBACKWARD;
            case 4: return de.audi.app.terminalmode.events.PlaybackInfoChangedEvent.PlaybackState.SEEKBACKWARD;
            default: return de.audi.app.terminalmode.events.PlaybackInfoChangedEvent.PlaybackState.STOPPED;
        }
    }

    private void notifyPlayPosition(de.audi.app.terminalmode.events.TrackPlayPositionEvent event) {
        if (event.equals(notifiedPlayPosition)) {
            return;
        }
        notifiedPlayPosition = event;
        eventBus.updatePlayPosition(event);
    }

    public void updatePlayposition(int position, int instanceId) {
        if (isValid(instanceId)) {
            de.audi.app.terminalmode.events.TrackPlayPositionEvent event = new de.audi.app.terminalmode.events.TrackPlayPositionEvent(position / 1000, notifiedPlayPosition.getTotalTimeOfTrack());
            playPositionLogger.updatePlayPosition(event);
            notifyPlayPosition(event);
        }
    }

    private boolean isValid(int instanceId) {
        return instanceId == 1;
    }

    public void updateCoverArtUrl(org.dsi.ifc.global.ResourceLocator resourceLocator, int instanceId) {
        try {
            com.mhi2.androidadio.AAJavaBridge.onCoverArtUrl(resourceLocator, instanceId);
        } catch (Throwable t) {}
    }

    public void updateNavigationNextTurnEvent(java.lang.String roadName, int mainElement, int direction, int turnAngle, int turnNumber, int event) {
    }

    public void updateNavigationNextTurnDistance(int distance, int unit, int remainingDistance) {
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
