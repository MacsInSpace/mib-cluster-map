// Compile-time stand-in for the stock class of the same name (lsd.jxe):
// only the members this jar uses, with their stock signatures. Never packed.
package org.dsi.ifc.androidauto2;
import org.dsi.ifc.global.ResourceLocator;
public interface DSIAndroidAuto2Listener {
    void asyncException(int a, String b, int c);
    void videoFocusRequestNotification(int a, int b);
    void videoAvailable(boolean a, int b);
    void audioFocusRequestNotification(int a, int b);
    void audioAvailable(int a, boolean b, int c);
    void voiceSessionNotification(int a, int b);
    void microphoneRequestNotification(int a, int b);
    void navFocusRequestNotification(int a, int b);
    void updateCallState(CallState[] a, int b);
    void updateTelephonyState(TelephonyState a, int b);
    void updateNowPlayingData(TrackData a, int b);
    void updatePlaybackState(PlaybackInfo a, int b);
    void updatePlayposition(int a, int b);
    void updateCoverArtUrl(ResourceLocator a, int b);
    void updateNavigationNextTurnEvent(String a, int b, int c, int d, int e, int f);
    void updateNavigationNextTurnDistance(int a, int b, int c);
    void setExternalDestination(double a, double b, String c, String d, int e);
    void bluetoothPairingRequest(String a, int b);
}
