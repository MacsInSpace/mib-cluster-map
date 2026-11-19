package com.mhi2.androidadio;

import de.audi.app.combi.bap.app.audio.AppConnectorMedia;
import de.audi.atip.interapp.combi.bap.audio.data.CombiBAPCurrentStationInfo;
import de.audi.atip.base.IFrameworkAccess;
import de.audi.atip.log.LogChannel;
import org.dsi.ifc.androidauto2.DSIAndroidAuto2;
import org.dsi.ifc.androidauto2.DSIAndroidAuto2Listener;
import org.dsi.ifc.androidauto2.TrackData;
import org.dsi.ifc.androidauto2.PlaybackInfo;
import org.dsi.ifc.global.ResourceLocator;
import de.audi.app.combi.bap.app.kombipictures.IPictureManager;
import org.osgi.framework.BundleContext;
import org.osgi.framework.FrameworkUtil;
import org.osgi.framework.ServiceReference;
import org.osgi.framework.Bundle;

public class AATrackProvider implements DSIAndroidAuto2Listener {
    private static final int SOURCE_TYPE_BT_STREAM = 3;
    private static AATrackProvider instance;
    private DSIAndroidAuto2 dsi;
    private LogChannel log;
    private AppConnectorMedia mediaConnector;
    private IPictureManager pictureManager;
    private String lastTitle;
    private String lastArtist;
    private String lastAlbum;
    private String lastCoverUrl;
    private int lastPictureId;
    private long lastListRef;
    private boolean active;

    public static AATrackProvider getInstance() {
        return instance;
    }

    public AATrackProvider() {
        instance = this;
        log = getLogChannel();
        lastTitle = "";
        lastArtist = "";
        lastAlbum = "";
        lastCoverUrl = "";
        lastPictureId = 0;
        lastListRef = 0;
        active = false;
        mediaConnector = findMediaConnector();
        pictureManager = findPictureManager();
        if (mediaConnector != null) {
            log.log(100000, "media connector found");
        } else {
            log.log(1000000, "media connector NOT found");
        }
        if (pictureManager != null) {
            log.log(100000, "picture manager found");
        } else {
            log.log(1000000, "picture manager NOT found");
        }
        startDSI();
    }

    private LogChannel getLogChannel() {
        try {
            BundleContext bc = getBundleContext();
            if (bc != null) {
                ServiceReference ref = bc.getServiceReference(IFrameworkAccess.class.getName());
                if (ref != null) {
                    Object fa = bc.getService(ref);
                    if (fa != null) {
                        java.lang.reflect.Method m = fa.getClass().getMethod("getLogChannel", String.class);
                        bc.ungetService(ref);
                        return (LogChannel) m.invoke(fa, "AATrackProvider");
                    }
                    bc.ungetService(ref);
                }
            }
        } catch (Throwable t) {}
        try {
            Class<?> cls = Class.forName("de.audi.atip.base.IFrameworkAccess");
            java.lang.reflect.Field f = null;
            Class<?> c = cls;
            while (c != null) {
                try {
                    f = c.getDeclaredField("instance");
                    break;
                } catch (NoSuchFieldException e) {
                    c = c.getSuperclass();
                }
            }
            if (f != null) {
                f.setAccessible(true);
                Object fa = f.get(null);
                if (fa != null) {
                    java.lang.reflect.Method m = fa.getClass().getMethod("getLogChannel", String.class);
                    return (LogChannel) m.invoke(fa, "AATrackProvider");
                }
            }
        } catch (Throwable t) {}
        return new StubLogChannel();
    }

    private BundleContext getBundleContext() {
        try {
            BundleContext bc = AAJavaBridge.getBundleContext();
            if (bc != null) return bc;
        } catch (Throwable t) {}
        try {
            Bundle b = FrameworkUtil.getBundle(AATrackProvider.class);
            if (b != null) return b.getBundleContext();
        } catch (Throwable t) {}
        return null;
    }

    private AppConnectorMedia findMediaConnector() {
        try {
            BundleContext bc = getBundleContext();
            if (bc != null) {
                ServiceReference ref = bc.getServiceReference(de.audi.atip.interapp.combi.bap.audio.CombiBAPServiceMedia.class.getName());
                if (ref != null) {
                    Object svc = bc.getService(ref);
                    if (svc instanceof AppConnectorMedia) {
                        bc.ungetService(ref);
                        return (AppConnectorMedia) svc;
                    }
                    bc.ungetService(ref);
                }
            }
        } catch (Throwable t) {}
        try {
            Class<?> cls = Class.forName("de.audi.app.combi.bap.app.audio.CombiModuleAudio");
            java.lang.reflect.Method m = cls.getMethod("getMediaService");
            Object mod = findCombiModuleAudio(cls);
            if (mod != null) {
                Object svc = m.invoke(mod);
                if (svc instanceof AppConnectorMedia) return (AppConnectorMedia) svc;
            }
        } catch (Throwable t) {}
        return null;
    }

    private Object findCombiModuleAudio(Class<?> cls) throws Exception {
        java.lang.reflect.Field f = null;
        Class<?> c = cls;
        while (c != null) {
            try {
                f = c.getDeclaredField("instance");
                break;
            } catch (NoSuchFieldException e) {
                c = c.getSuperclass();
            }
        }
        if (f != null) {
            f.setAccessible(true);
            return f.get(null);
        }
        return null;
    }

    private IPictureManager findPictureManager() {
        if (mediaConnector != null) {
            try {
                java.lang.reflect.Method m = mediaConnector.getClass().getMethod("getPictureManager");
                Object pm = m.invoke(mediaConnector);
                if (pm instanceof IPictureManager) return (IPictureManager) pm;
            } catch (Throwable t) {}
        }
        try {
            BundleContext bc = getBundleContext();
            if (bc != null) {
                ServiceReference ref = bc.getServiceReference(IPictureManager.class.getName());
                if (ref != null) {
                    Object pm = bc.getService(ref);
                    if (pm != null) {
                        bc.ungetService(ref);
                        return (IPictureManager) pm;
                    }
                    bc.ungetService(ref);
                }
            }
        } catch (Throwable t) {}
        return null;
    }

    private void startDSI() {
        try {
            BundleContext bc = getBundleContext();
            if (bc == null) {
                log.log(1000000, "no BundleContext for DSI lookup");
                return;
            }
            ServiceReference ref = bc.getServiceReference(DSIAndroidAuto2.class.getName());
            if (ref == null) {
                log.log(1000000, "DSIAndroidAuto2 service not available yet");
                return;
            }
            dsi = (DSIAndroidAuto2) bc.getService(ref);
            bc.ungetService(ref);
            if (dsi != null) {
                log.log(100000, "DSIAndroidAuto2 service obtained");
                dsi.setNotification(this);
                try {
                    org.dsi.ifc.androidauto2.ServiceConfiguration config = new org.dsi.ifc.androidauto2.ServiceConfiguration();
                    dsi.startService(config);
                    log.log(100000, "DSIAndroidAuto2 service started");
                } catch (Throwable t) {
                    log.log(1000000, "DSIAndroidAuto2 startService failed");
                }
                active = true;
            }
        } catch (Throwable t) {
            log.log(1000000, "startDSI failed");
        }
    }

    public void updateNowPlayingData(TrackData trackData, int instanceId) {
        if (!active || trackData == null || mediaConnector == null) return;
        String title = trackData.getTitle();
        String artist = trackData.getArtist();
        String album = trackData.getAlbum();
        if (title == null) title = "";
        if (artist == null) artist = "";
        if (album == null) album = "";
        boolean changed = !title.equals(lastTitle) || !artist.equals(lastArtist) || !album.equals(lastAlbum);
        lastTitle = title;
        lastArtist = artist;
        lastAlbum = album;
        if (!changed && lastCoverUrl.isEmpty()) return;
        try {
            CombiBAPCurrentStationInfo info = new CombiBAPCurrentStationInfo();
            info.setPrimaryInformation(title, 0, 0);
            info.setSecondaryInformation(artist, 0);
            info.setTertiaryInformation(album, 0);
            info.setPicture(lastPictureId, lastCoverUrl);
            info.setListRef((int) (System.currentTimeMillis() & 0x7FFFFFFF));
            lastListRef = info.getListRef();
            mediaConnector.updateCurrentStation(info);
            log.log(100000, "track updated");
        } catch (Throwable t) {
            log.log(1000000, "updateNowPlayingData failed");
        }
    }

    public void updateCoverArtUrl(ResourceLocator resourceLocator, int instanceId) {
        if (!active || pictureManager == null) return;
        String url = resourceLocator != null ? resourceLocator.getUrl() : null;
        if (url == null) url = "";
        boolean changed = !url.equals(lastCoverUrl);
        lastCoverUrl = url;
        lastPictureId = resourceLocator != null ? resourceLocator.getId() : 0;
        if (!changed && lastTitle.isEmpty() && lastArtist.isEmpty()) return;
        try {
            long listRef = lastListRef != 0 ? lastListRef : 1;
            pictureManager.responseCoverArt(listRef, SOURCE_TYPE_BT_STREAM, resourceLocator, true);
            log.log(100000, "cover art updated");
        } catch (Throwable t) {
            log.log(1000000, "updateCoverArtUrl failed");
        }
    }

    public void videoFocusRequestNotification(int a, int b) {}
    public void videoAvailable(boolean a, int b) {}
    public void audioFocusRequestNotification(int a, int b) {}
    public void audioAvailable(int a, boolean b, int c) {}
    public void voiceSessionNotification(int a, int b) {}
    public void microphoneRequestNotification(int a, int b) {}
    public void navFocusRequestNotification(int a, int b) {}
    public void updateCallState(org.dsi.ifc.androidauto2.CallState[] a, int b) {}
    public void updateTelephonyState(org.dsi.ifc.androidauto2.TelephonyState a, int b) {}
    public void updatePlaybackState(PlaybackInfo a, int b) {}
    public void updatePlayposition(int a, int b) {}
    public void updateNavigationNextTurnEvent(String a, int b, int c, int d, int e, int f) {}
    public void updateNavigationNextTurnDistance(int a, int b, int c) {}
    public void setExternalDestination(double a, double b, String c, String d, int e) {}
    public void bluetoothPairingRequest(String a, int b) {}
    public void asyncException(int a, String b, int c) {}
    public void registered(String a, int b) {}
    public void unregistered(String a, int b) {}

    private static class StubLogChannel extends de.audi.atip.log.LogChannel {
        public StubLogChannel() { super(); }
        public void log(int a, java.lang.String b, java.lang.Object c, java.lang.Object d, java.lang.Object e, java.lang.Object f, long g, long h, long i, int j, java.lang.Throwable k) {}
        public void log(int a, int b, java.lang.Object c, java.lang.Object d, java.lang.Object e, java.lang.Object f, long g, long h, long i, int j, java.lang.Throwable k) {}
        public boolean log(int a, java.lang.String b) { return false; }
    }
}
