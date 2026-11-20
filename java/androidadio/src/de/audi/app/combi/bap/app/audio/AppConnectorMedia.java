package de.audi.app.combi.bap.app.audio;

import com.mhi2.androidadio.AAJavaBridge;
import de.audi.atip.interapp.bap.BAPServiceListener;
import de.audi.atip.interapp.combi.bap.audio.data.CombiBAPAudioSource;
import de.audi.atip.interapp.combi.bap.audio.data.CombiBAPCurrentStationInfo;
import de.audi.atip.interapp.combi.bap.audio.data.CombiBAPMediaBrowserListEntry;
import de.audi.atip.interapp.combi.bap.audio.data.PlayPosition;

public class AppConnectorMedia extends de.audi.app.combi.bap.app.audio.AbstractAppConnectorAudio {

    public AppConnectorMedia(CombiModuleAudio module) {
        super(module);
        try {
            AAJavaBridge.setCombiModule(module);
        } catch (Throwable t) {}
    }

    public void setAppServiceListener(BAPServiceListener listener) {
    }

    protected int getAudioApplication() {
        return 2;
    }

    protected java.lang.String getAudioApplicationName() {
        return "Media";
    }

    protected boolean isAudioApplicationInFocus() {
        try {
            Object combiModule = AAJavaBridge.getCombiModule();
            if (combiModule != null) {
                Object handler = combiModule.getClass().getMethod(
                    "getAudioApplicationFocusHandler", new Class[0]).invoke(combiModule, new Object[0]);
                if (handler != null) {
                    return ((Boolean) handler.getClass().getMethod(
                        "isMediaInFocus", new Class[0]).invoke(handler, new Object[0])).booleanValue();
                }
            }
        } catch (Throwable t) {}
        return false;
    }

    public void updateCurrentStation(CombiBAPCurrentStationInfo info) {
        super.updateCurrentStation(info);
    }

    public void updateActiveSource(int a, int b, int c, boolean d, boolean e, int f) {
    }

    protected void sendSourceChangeRelatedProperties() {
    }

    public void updateSourceListMedia(int[] a, CombiBAPAudioSource[][] b) {
    }

    public void goToResult(int a, int b) {
    }

    public void trackChangeIsComing() {
    }

    public void updateBrowserListSize(int a) {
    }

    public void updateCurrentBrowseFolder(int a, java.lang.String b, int c, int d, int e) {
    }

    public void responseMediaBrowserList(int a, CombiBAPMediaBrowserListEntry[] b) {
    }

    public void updatePlaybackFolder(boolean a) {
    }

    public void updateMediaImportState(int a, int b, boolean c, int d) {
    }

    public void responseCoverArt(long a, int b, java.lang.String c, int d) {
    }

    public void updatePlayPosition(PlayPosition a) {
    }
}
