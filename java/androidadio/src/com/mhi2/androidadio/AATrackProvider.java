package com.mhi2.androidadio;

import java.io.FileWriter;
import java.io.PrintWriter;
import java.lang.reflect.Method;
import java.text.SimpleDateFormat;
import java.util.Date;
import org.dsi.ifc.androidauto2.TrackData;
import org.dsi.ifc.global.ResourceLocator;

public class AATrackProvider {
    private static final int SOURCE_TYPE_BT_STREAM = 3;
    private static AATrackProvider instance;
    private Object log;
    private Object mediaConnector;
    private Object pictureManager;
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
        debugLog("AATrackProvider.<init> entered (lazy service lookup)");
    }

    private Object getLogChannel() {
        try {
            Object bc = getBundleContext();
            if (bc != null) {
                Method getSR = bc.getClass().getMethod("getServiceReference", String.class);
                Object ref = getSR.invoke(bc, "de.audi.atip.base.IFrameworkAccess");
                if (ref != null) {
                    Method getService = bc.getClass().getMethod("getService", ref.getClass());
                    Object fa = getService.invoke(bc, ref);
                    if (fa != null) {
                        Method getLC = fa.getClass().getMethod("getLogChannel", String.class);
                        Object lc = getLC.invoke(fa, "AATrackProvider");
                        Method unget = bc.getClass().getMethod("ungetService", ref.getClass());
                        unget.invoke(bc, ref);
                        return lc;
                    }
                    Method unget = bc.getClass().getMethod("ungetService", ref.getClass());
                    unget.invoke(bc, ref);
                }
            }
        } catch (Throwable t) {
            StringBuffer sb = new StringBuffer("getLogChannel: OSGi IFrameworkAccess lookup threw ");
            sb.append(t);
            debugLog(sb.toString());
        }
        try {
            Class<?> cls = forName("de.audi.atip.base.IFrameworkAccess");
            if (cls == null) {
                debugLog("getLogChannel: static instance lookup threw ClassNotFoundException");
            }
            Class<?> c = cls;
            java.lang.reflect.Field f = null;
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
                    Method getLC = fa.getClass().getMethod("getLogChannel", String.class);
                    return getLC.invoke(fa, "AATrackProvider");
                }
            }
        } catch (Throwable t) {
            StringBuffer sb = new StringBuffer("getLogChannel: static instance lookup threw ");
            sb.append(t);
            debugLog(sb.toString());
        }
        return new StubLogChannel();
    }

    private Object getBundleContext() {
        try {
            Object bc = AAJavaBridge.getBundleContext();
            if (bc != null) {
                debugLog("AATrackProvider.getBundleContext: from AAJavaBridge");
                return bc;
            }
        } catch (Throwable t) {}
        try {
            Class<?> fuCls = forName("org.osgi.framework.FrameworkUtil");
            if (fuCls == null) {
                debugLog("AATrackProvider.getBundleContext: FrameworkUtil not found");
                return null;
            }
            Method getBundle = fuCls.getMethod("getBundle", Class.class);
            Object bundle = getBundle.invoke(null, AAJavaBridge.getAppClass());
            if (bundle != null) {
                Method getBC = bundle.getClass().getMethod("getBundleContext");
                Object bc2 = getBC.invoke(bundle);
                StringBuffer sb = new StringBuffer("AATrackProvider.getBundleContext: from FrameworkUtil, bc=");
                sb.append(bc2 != null ? "non-null" : "null");
                debugLog(sb.toString());
                return bc2;
            }
        } catch (Throwable t) {}
        debugLog("AATrackProvider.getBundleContext: returning null");
        return null;
    }

    private Object findMediaConnector() {
        try {
            Object bc = getBundleContext();
            if (bc != null) {
                Method getSR = bc.getClass().getMethod("getServiceReference", String.class);
                Object ref = getSR.invoke(bc, "de.audi.atip.interapp.combi.bap.audio.CombiBAPServiceMedia");
                if (ref != null) {
                    Method getService = bc.getClass().getMethod("getService", ref.getClass());
                    Object svc = getService.invoke(bc, ref);
                    if (svc != null && "de.audi.app.combi.bap.app.audio.AppConnectorMedia".equals(svc.getClass().getName())) {
                        Method unget = bc.getClass().getMethod("ungetService", ref.getClass());
                        unget.invoke(bc, ref);
                        debugLog("findMediaConnector: found via OSGi CombiBAPServiceMedia");
                        return svc;
                    }
                    if (svc != null) {
                        Method unget = bc.getClass().getMethod("ungetService", ref.getClass());
                        unget.invoke(bc, ref);
                    }
                }
            }
        } catch (Throwable t) {
            StringBuffer sb = new StringBuffer("findMediaConnector: OSGi lookup threw ");
            sb.append(t);
            debugLog(sb.toString());
        }
        try {
            Class<?> cls = forName("de.audi.app.combi.bap.app.audio.CombiModuleAudio");
            if (cls == null) {
                debugLog("findMediaConnector: CombiModuleAudio not found");
            } else {
                Method getMediaService = cls.getMethod("getMediaService");
                Object mod = findStaticInstance(cls);
                if (mod != null) {
                    Object svc = getMediaService.invoke(mod);
                    if (svc != null && "de.audi.app.combi.bap.app.audio.AppConnectorMedia".equals(svc.getClass().getName())) {
                        debugLog("findMediaConnector: found via CombiModuleAudio.getMediaService");
                        return svc;
                    }
                }
            }
        } catch (Throwable t) {
            StringBuffer sb = new StringBuffer("findMediaConnector: CombiModuleAudio lookup threw ");
            sb.append(t);
            debugLog(sb.toString());
        }
        debugLog("findMediaConnector: returning null");
        return null;
    }

    private static Class<?> forName(String name) {
        ClassLoader cl = AAJavaBridge.getAppClassLoader();
        if (cl != null) {
            try {
                return Class.forName(name, true, cl);
            } catch (ClassNotFoundException e) {
                // fall through to 1-arg
            }
        }
        try {
            return Class.forName(name);
        } catch (ClassNotFoundException e) {
            return null;
        }
    }

    private Object findStaticInstance(Class<?> cls) throws Exception {
        Class<?> c = cls;
        while (c != null) {
            try {
                java.lang.reflect.Field f = c.getDeclaredField("instance");
                f.setAccessible(true);
                return f.get(null);
            } catch (NoSuchFieldException e) {
                c = c.getSuperclass();
            }
        }
        return null;
    }

    private Object findPictureManager() {
        if (mediaConnector != null) {
            try {
                Method m = mediaConnector.getClass().getMethod("getPictureManager");
                Object pm = m.invoke(mediaConnector);
                if (pm != null) {
                    debugLog("findPictureManager: found via mediaConnector.getPictureManager()");
                    return pm;
                }
            } catch (Throwable t) {
                StringBuffer sb = new StringBuffer("findPictureManager: mediaConnector.getPictureManager threw ");
                sb.append(t);
                debugLog(sb.toString());
            }
        }
        try {
            Object bc = getBundleContext();
            if (bc != null) {
                Method getSR = bc.getClass().getMethod("getServiceReference", String.class);
                Object ref = getSR.invoke(bc, "de.audi.app.combi.bap.app.kombipictures.IPictureManager");
                if (ref != null) {
                    Method getService = bc.getClass().getMethod("getService", ref.getClass());
                    Object pm = getService.invoke(bc, ref);
                    if (pm != null) {
                        Method unget = bc.getClass().getMethod("ungetService", ref.getClass());
                        unget.invoke(bc, ref);
                        debugLog("findPictureManager: found via OSGi IPictureManager");
                        return pm;
                    }
                    Method unget = bc.getClass().getMethod("ungetService", ref.getClass());
                    unget.invoke(bc, ref);
                }
            }
        } catch (Throwable t) {
            StringBuffer sb = new StringBuffer("findPictureManager: OSGi lookup threw ");
            sb.append(t);
            debugLog(sb.toString());
        }
        debugLog("findPictureManager: returning null");
        return null;
    }

    private void logCall(int level, String msg) {
        if (log != null) {
            try {
                Method m = log.getClass().getMethod("log", int.class, String.class);
                m.invoke(log, level, msg);
            } catch (Throwable t) {}
        }
    }

    public void startDSI() {
        debugLog("AATrackProvider.startDSI() entered");
    }

    public void handleNowPlayingData(TrackData trackData, int instanceId) {
        StringBuffer sb = new StringBuffer("handleNowPlayingData called, trackData=");
        sb.append(trackData != null ? "non-null" : "null");
        debugLog(sb.toString());
        if (trackData == null) {
            debugLog("handleNowPlayingData: returning early (null trackData)");
            return;
        }
        if (mediaConnector == null) {
            debugLog("handleNowPlayingData: mediaConnector null, attempting lazy lookup");
            mediaConnector = findMediaConnector();
            StringBuffer sb2 = new StringBuffer("handleNowPlayingData: mediaConnector after lazy lookup=");
            sb2.append(mediaConnector != null ? "non-null" : "null");
            debugLog(sb2.toString());
        }
        if (mediaConnector == null) {
            debugLog("handleNowPlayingData: returning early (no media connector)");
            return;
        }
        String title = trackData.getTitle();
        String artist = trackData.getArtist();
        String album = trackData.getAlbum();
        if (title == null) title = "";
        if (artist == null) artist = "";
        if (album == null) album = "";
        StringBuffer sb3 = new StringBuffer("handleNowPlayingData: title='");
        sb3.append(title);
        sb3.append("' artist='");
        sb3.append(artist);
        sb3.append("' album='");
        sb3.append(album);
        sb3.append("'");
        debugLog(sb3.toString());
        boolean changed = !title.equals(lastTitle) || !artist.equals(lastArtist) || !album.equals(lastAlbum);
        lastTitle = title;
        lastArtist = artist;
        lastAlbum = album;
        if (!changed && lastCoverUrl.length() == 0) {
            debugLog("handleNowPlayingData: no change and no cover url, returning");
            return;
        }
        try {
            Class<?> infoCls = forName("de.audi.atip.interapp.combi.bap.audio.data.CombiBAPCurrentStationInfo");
            if (infoCls == null) {
                debugLog("CombiBAPCurrentStationInfo not found");
                return;
            }
            Object info = infoCls.getDeclaredConstructor().newInstance();
            Method setPrimary = infoCls.getMethod("setPrimaryInformation", String.class, int.class, int.class);
            setPrimary.invoke(info, title, 0, 0);
            Method setSecondary = infoCls.getMethod("setSecondaryInformation", String.class, int.class);
            setSecondary.invoke(info, artist, 0);
            Method setTertiary = infoCls.getMethod("setTertiaryInformation", String.class, int.class);
            setTertiary.invoke(info, album, 0);
            Method setPicture = infoCls.getMethod("setPicture", int.class, String.class);
            setPicture.invoke(info, lastPictureId, lastCoverUrl);
            Method setListRef = infoCls.getMethod("setListRef", int.class);
            setListRef.invoke(info, (int) (System.currentTimeMillis() & 0x7FFFFFFF));
            Method getListRef = infoCls.getMethod("getListRef");
            lastListRef = (Integer) getListRef.invoke(info);
            Method updateCurrentStation = mediaConnector.getClass().getMethod("updateCurrentStation", infoCls);
            updateCurrentStation.invoke(mediaConnector, info);
            logCall(100000, "track updated");
            StringBuffer sb4 = new StringBuffer("handleNowPlayingData: mediaConnector.updateCurrentStation(info) called, listRef=");
            sb4.append(lastListRef);
            debugLog(sb4.toString());
        } catch (Throwable t) {
            logCall(1000000, "handleNowPlayingData failed");
            StringBuffer sb5 = new StringBuffer("handleNowPlayingData: mediaConnector.updateCurrentStation threw ");
            sb5.append(t);
            debugLog(sb5.toString());
        }
    }

    public void handleCoverArtUrl(ResourceLocator resourceLocator, int instanceId) {
        StringBuffer sb = new StringBuffer("handleCoverArtUrl called, resourceLocator=");
        sb.append(resourceLocator != null ? "non-null" : "null");
        debugLog(sb.toString());
        if (resourceLocator == null) {
            debugLog("handleCoverArtUrl: returning early (null resourceLocator)");
            return;
        }
        if (mediaConnector == null) {
            debugLog("handleCoverArtUrl: mediaConnector null, attempting lazy lookup");
            mediaConnector = findMediaConnector();
            StringBuffer sb2 = new StringBuffer("handleCoverArtUrl: mediaConnector after lazy lookup=");
            sb2.append(mediaConnector != null ? "non-null" : "null");
            debugLog(sb2.toString());
        }
        if (mediaConnector == null) {
            debugLog("handleCoverArtUrl: returning early (no media connector)");
            return;
        }
        String url = resourceLocator.getUrl();
        if (url == null) url = "";
        boolean changed = !url.equals(lastCoverUrl);
        lastCoverUrl = url;
        lastPictureId = resourceLocator.getId();
        StringBuffer sb3 = new StringBuffer("handleCoverArtUrl: url='");
        sb3.append(url);
        sb3.append("' pictureId=");
        sb3.append(lastPictureId);
        sb3.append(" changed=");
        sb3.append(changed);
        debugLog(sb3.toString());
        if (!changed && lastTitle.length() == 0 && lastArtist.length() == 0) {
            debugLog("handleCoverArtUrl: no change and no track info, returning");
            return;
        }
        try {
            long listRef = lastListRef != 0 ? lastListRef : 1;
            Class<?> infoCls = forName("de.audi.atip.interapp.combi.bap.audio.data.CombiBAPCurrentStationInfo");
            if (infoCls == null) {
                debugLog("CombiBAPCurrentStationInfo not found");
                return;
            }
            Object info = infoCls.getDeclaredConstructor().newInstance();
            Method setPrimary = infoCls.getMethod("setPrimaryInformation", String.class, int.class, int.class);
            setPrimary.invoke(info, lastTitle, 0, 0);
            Method setSecondary = infoCls.getMethod("setSecondaryInformation", String.class, int.class);
            setSecondary.invoke(info, lastArtist, 0);
            Method setTertiary = infoCls.getMethod("setTertiaryInformation", String.class, int.class);
            setTertiary.invoke(info, lastAlbum, 0);
            Method setPicture = infoCls.getMethod("setPicture", int.class, String.class);
            setPicture.invoke(info, lastPictureId, lastCoverUrl);
            Method setListRef = infoCls.getMethod("setListRef", int.class);
            setListRef.invoke(info, (int) (System.currentTimeMillis() & 0x7FFFFFFF));
            Method getListRef = infoCls.getMethod("getListRef");
            lastListRef = (Integer) getListRef.invoke(info);
            Method updateCurrentStation = mediaConnector.getClass().getMethod("updateCurrentStation", infoCls);
            updateCurrentStation.invoke(mediaConnector, info);
            logCall(100000, "cover art updated via updateCurrentStation");
            StringBuffer sb4 = new StringBuffer("handleCoverArtUrl: mediaConnector.updateCurrentStation(info) called with cover art, listRef=");
            sb4.append(lastListRef);
            debugLog(sb4.toString());
        } catch (Throwable t) {
            logCall(1000000, "handleCoverArtUrl failed");
            StringBuffer sb5 = new StringBuffer("handleCoverArtUrl: mediaConnector.updateCurrentStation threw ");
            sb5.append(t);
            debugLog(sb5.toString());
            try {
                if (pictureManager == null) {
                    pictureManager = findPictureManager();
                }
                if (pictureManager != null) {
                    long fbListRef = lastListRef != 0 ? lastListRef : 1;
                    Method m = pictureManager.getClass().getMethod("responseCoverArt", long.class, int.class, ResourceLocator.class, boolean.class);
                    m.invoke(pictureManager, fbListRef, SOURCE_TYPE_BT_STREAM, resourceLocator, true);
                    debugLog("handleCoverArtUrl: fallback pictureManager.responseCoverArt called");
                }
            } catch (Throwable t2) {
                StringBuffer sb6 = new StringBuffer("handleCoverArtUrl: fallback pictureManager.responseCoverArt also threw ");
                sb6.append(t2);
                debugLog(sb6.toString());
            }
        }
    }

    private static void debugLog(String msg) {
        try {
            SimpleDateFormat sdf = new SimpleDateFormat("HH:mm:ss.SSS");
            StringBuffer sb = new StringBuffer();
            sb.append(sdf.format(new Date()));
            sb.append(" AATrackProvider: ");
            sb.append(msg);
            FileWriter fw = new FileWriter("/tmp/aacoverart.log", true);
            PrintWriter pw = new PrintWriter(fw);
            pw.println(sb.toString());
            pw.close();
        } catch (Throwable t) {}
    }

    private static class StubLogChannel {
        public StubLogChannel() {}
    }
}
