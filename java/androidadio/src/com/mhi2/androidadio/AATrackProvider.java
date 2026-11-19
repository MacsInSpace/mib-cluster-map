package com.mhi2.androidadio;

import de.audi.app.combi.bap.app.audio.AppConnectorMedia;
import de.audi.atip.interapp.combi.bap.audio.data.CombiBAPCurrentStationInfo;
import de.audi.atip.base.IFrameworkAccess;
import de.audi.atip.log.LogChannel;
import de.audi.app.combi.bap.app.kombipictures.IPictureManager;
import org.dsi.ifc.androidauto2.TrackData;
import org.dsi.ifc.global.ResourceLocator;
import org.osgi.framework.BundleContext;
import org.osgi.framework.FrameworkUtil;
import org.osgi.framework.ServiceReference;
import org.osgi.framework.Bundle;
import java.io.FileWriter;
import java.io.PrintWriter;
import java.text.SimpleDateFormat;
import java.util.Date;

public class AATrackProvider {
    private static final int SOURCE_TYPE_BT_STREAM = 3;
    private static AATrackProvider instance;
    private LogChannel log;
    private AppConnectorMedia mediaConnector;
    private IPictureManager pictureManager;
    private String lastTitle;
    private String lastArtist;
    private String lastAlbum;
    private String lastCoverUrl;
    private int lastPictureId;
    private long lastListRef;

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
        debugLog("AATrackProvider.<init> entered");
        mediaConnector = findMediaConnector();
        pictureManager = findPictureManager();
        if (mediaConnector != null) {
            log.log(100000, "media connector found");
            debugLog("mediaConnector found");
        } else {
            log.log(1000000, "media connector NOT found");
            debugLog("mediaConnector NOT found");
        }
        if (pictureManager != null) {
            log.log(100000, "picture manager found");
            debugLog("pictureManager found");
        } else {
            log.log(1000000, "picture manager NOT found");
            debugLog("pictureManager NOT found");
        }
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
        } catch (Throwable t) {
            debugLog("getLogChannel: OSGi IFrameworkAccess lookup threw " + t);
        }
        try {
            Class cls = Class.forName("de.audi.atip.base.IFrameworkAccess");
            java.lang.reflect.Field f = null;
            Class c = cls;
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
        } catch (Throwable t) {
            debugLog("getLogChannel: static instance lookup threw " + t);
        }
        return new StubLogChannel();
    }

    private BundleContext getBundleContext() {
        try {
            BundleContext bc = AAJavaBridge.getBundleContext();
            if (bc != null) {
                debugLog("AATrackProvider.getBundleContext: from AAJavaBridge");
                return bc;
            }
        } catch (Throwable t) {}
        try {
            Bundle b = FrameworkUtil.getBundle(AATrackProvider.class);
            if (b != null) {
                BundleContext bc2 = b.getBundleContext();
                debugLog("AATrackProvider.getBundleContext: from FrameworkUtil, bc=" + (bc2 != null ? "non-null" : "null"));
                return bc2;
            }
        } catch (Throwable t) {}
        debugLog("AATrackProvider.getBundleContext: returning null");
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
                        debugLog("findMediaConnector: found via OSGi CombiBAPServiceMedia");
                        return (AppConnectorMedia) svc;
                    }
                    bc.ungetService(ref);
                }
            }
        } catch (Throwable t) {
            debugLog("findMediaConnector: OSGi lookup threw " + t);
        }
        try {
            Class cls = Class.forName("de.audi.app.combi.bap.app.audio.CombiModuleAudio");
            java.lang.reflect.Method m = cls.getMethod("getMediaService");
            Object mod = findCombiModuleAudio(cls);
            if (mod != null) {
                Object svc = m.invoke(mod);
                if (svc instanceof AppConnectorMedia) {
                    debugLog("findMediaConnector: found via CombiModuleAudio.getMediaService");
                    return (AppConnectorMedia) svc;
                }
            }
        } catch (Throwable t) {
            debugLog("findMediaConnector: CombiModuleAudio lookup threw " + t);
        }
        debugLog("findMediaConnector: returning null");
        return null;
    }

    private Object findCombiModuleAudio(Class cls) throws Exception {
        java.lang.reflect.Field f = null;
        Class c = cls;
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
                if (pm instanceof IPictureManager) {
                    debugLog("findPictureManager: found via mediaConnector.getPictureManager()");
                    return (IPictureManager) pm;
                }
            } catch (Throwable t) {
                debugLog("findPictureManager: mediaConnector.getPictureManager threw " + t);
            }
        }
        try {
            BundleContext bc = getBundleContext();
            if (bc != null) {
                ServiceReference ref = bc.getServiceReference(IPictureManager.class.getName());
                if (ref != null) {
                    Object pm = bc.getService(ref);
                    if (pm != null) {
                        bc.ungetService(ref);
                        debugLog("findPictureManager: found via OSGi IPictureManager");
                        return (IPictureManager) pm;
                    }
                    bc.ungetService(ref);
                }
            }
        } catch (Throwable t) {
            debugLog("findPictureManager: OSGi lookup threw " + t);
        }
        debugLog("findPictureManager: returning null");
        return null;
    }

    public void startDSI() {
        debugLog("AATrackProvider.startDSI() entered");
    }

    public void handleNowPlayingData(TrackData trackData, int instanceId) {
        debugLog("handleNowPlayingData called, trackData=" + (trackData != null ? "non-null" : "null") + ", mediaConnector=" + (mediaConnector != null ? "non-null" : "null"));
        if (trackData == null || mediaConnector == null) {
            debugLog("handleNowPlayingData: returning early");
            return;
        }
        String title = trackData.getTitle();
        String artist = trackData.getArtist();
        String album = trackData.getAlbum();
        if (title == null) title = "";
        if (artist == null) artist = "";
        if (album == null) album = "";
        debugLog("handleNowPlayingData: title='" + title + "' artist='" + artist + "' album='" + album + "'");
        boolean changed = !title.equals(lastTitle) || !artist.equals(lastArtist) || !album.equals(lastAlbum);
        lastTitle = title;
        lastArtist = artist;
        lastAlbum = album;
        if (!changed && lastCoverUrl.length() == 0) {
            debugLog("handleNowPlayingData: no change and no cover url, returning");
            return;
        }
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
            debugLog("handleNowPlayingData: mediaConnector.updateCurrentStation(info) called, listRef=" + lastListRef);
        } catch (Throwable t) {
            log.log(1000000, "handleNowPlayingData failed");
            debugLog("handleNowPlayingData: mediaConnector.updateCurrentStation threw " + t);
        }
    }

    public void handleCoverArtUrl(ResourceLocator resourceLocator, int instanceId) {
        debugLog("handleCoverArtUrl called, pictureManager=" + (pictureManager != null ? "non-null" : "null"));
        if (pictureManager == null) {
            debugLog("handleCoverArtUrl: returning early");
            return;
        }
        String url = resourceLocator != null ? resourceLocator.getUrl() : null;
        if (url == null) url = "";
        boolean changed = !url.equals(lastCoverUrl);
        lastCoverUrl = url;
        lastPictureId = resourceLocator != null ? resourceLocator.getId() : 0;
        debugLog("handleCoverArtUrl: url='" + url + "' pictureId=" + lastPictureId + " changed=" + changed);
        if (!changed && lastTitle.length() == 0 && lastArtist.length() == 0) {
            debugLog("handleCoverArtUrl: no change and no track info, returning");
            return;
        }
        try {
            long listRef = lastListRef != 0 ? lastListRef : 1;
            pictureManager.responseCoverArt(listRef, SOURCE_TYPE_BT_STREAM, resourceLocator, true);
            log.log(100000, "cover art updated");
            debugLog("handleCoverArtUrl: pictureManager.responseCoverArt(listRef=" + listRef + ", sourceType=" + SOURCE_TYPE_BT_STREAM + ") called");
        } catch (Throwable t) {
            log.log(1000000, "handleCoverArtUrl failed");
            debugLog("handleCoverArtUrl: pictureManager.responseCoverArt threw " + t);
        }
    }

    private static void debugLog(String msg) {
        try {
            SimpleDateFormat sdf = new SimpleDateFormat("HH:mm:ss.SSS");
            String line = sdf.format(new Date()) + " AATrackProvider: " + msg;
            FileWriter fw = new FileWriter("/tmp/aacoverart.log", true);
            PrintWriter pw = new PrintWriter(fw);
            pw.println(line);
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
