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
                Method getSR = bc.getClass().getMethod("getServiceReference", new Class[]{String.class});
                Object ref = getSR.invoke(bc, new Object[]{"de.audi.atip.base.IFrameworkAccess"});
                if (ref != null) {
                    Method getService = bc.getClass().getMethod("getService", new Class[]{ref.getClass()});
                    Object fa = getService.invoke(bc, new Object[]{ref});
                    if (fa != null) {
                        Method getLC = fa.getClass().getMethod("getLogChannel", new Class[]{String.class});
                        Object lc = getLC.invoke(fa, new Object[]{"AATrackProvider"});
                        Method unget = bc.getClass().getMethod("ungetService", new Class[]{ref.getClass()});
                        unget.invoke(bc, new Object[]{ref});
                        return lc;
                    }
                    Method unget = bc.getClass().getMethod("ungetService", new Class[]{ref.getClass()});
                    unget.invoke(bc, new Object[]{ref});
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
                    Method getLC = fa.getClass().getMethod("getLogChannel", new Class[]{String.class});
                    return getLC.invoke(fa, new Object[]{"AATrackProvider"});
                }
            }
        } catch (Throwable t) {
            StringBuffer sb = new StringBuffer("getLogChannel: static instance lookup threw ");
            sb.append(t);
            debugLog(sb.toString());
        }
        return null;
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
            ClassLoader tccl = Thread.currentThread().getContextClassLoader();
            Class<?> fuCls;
            if (tccl != null) {
                try {
                    fuCls = Class.forName("org.osgi.framework.FrameworkUtil", true, tccl);
                } catch (ClassNotFoundException e) {
                    fuCls = forName("org.osgi.framework.FrameworkUtil");
                }
            } else {
                fuCls = forName("org.osgi.framework.FrameworkUtil");
            }
            if (fuCls == null) {
                debugLog("AATrackProvider.getBundleContext: FrameworkUtil not found");
                return null;
            }
            Method getBundle = fuCls.getMethod("getBundle", new Class[]{Class.class});
            Class<?> appCls = AAJavaBridge.getAppClass();
            Class<?> osgiCls = null;
            if (appCls != null) {
                osgiCls = appCls;
            } else {
                osgiCls = forName("de.audi.app.combi.bap.app.audio.CombiModuleAudio");
            }
            if (osgiCls == null) {
                osgiCls = AATrackProvider.class;
            }
            Object bundle = getBundle.invoke(null, new Object[]{osgiCls});
            if (bundle != null) {
                Method getBC = bundle.getClass().getMethod("getBundleContext", new Class[0]);
                Object bc2 = getBC.invoke(bundle, new Object[0]);
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
        // First: direct AAJavaBridge references (discovered by AndroidAuto2ListenerDistributor BFS walker)
        Object tmc = AAJavaBridge.getTerminalModeConnector();
        if (tmc != null) {
            debugLog("findMediaConnector: found terminalModeConnector via AAJavaBridge");
            return tmc;
        }
        Object mc = AAJavaBridge.getMediaConnector();
        if (mc != null) {
            debugLog("findMediaConnector: found mediaConnector via AAJavaBridge");
            return mc;
        }
        // Second: use CombiModule captured by AppConnectorMedia constructor (bootclasspath override)
        Object combiModule = AAJavaBridge.getCombiModule();
        if (combiModule != null) {
            try {
                Object terminalModeService = combiModule.getClass().getMethod(
                    "getTerminalModeService", new Class[0]).invoke(combiModule, new Object[0]);
                if (terminalModeService != null) {
                    debugLog("findMediaConnector: found AppConnectorTerminalMode via CombiModule.getTerminalModeService()");
                    return terminalModeService;
                }
            } catch (Throwable t) {
                StringBuffer sb = new StringBuffer("findMediaConnector: getTerminalModeService threw ");
                sb.append(t);
                debugLog(sb.toString());
            }
            try {
                Object mediaService = combiModule.getClass().getMethod(
                    "getMediaService", new Class[0]).invoke(combiModule, new Object[0]);
                if (mediaService != null && "de.audi.app.combi.bap.app.audio.AppConnectorMedia".equals(mediaService.getClass().getName())) {
                    debugLog("findMediaConnector: found AppConnectorMedia via CombiModule.getMediaService()");
                    return mediaService;
                }
            } catch (Throwable t) {
                StringBuffer sb = new StringBuffer("findMediaConnector: getMediaService threw ");
                sb.append(t);
                debugLog(sb.toString());
            }
        }

        // Then: OSGi lookup (existing code path)
        try {
            Object bc = getBundleContext();
            if (bc != null) {
                Method getSR = bc.getClass().getMethod("getServiceReference", new Class[]{String.class});
                Object ref = getSR.invoke(bc, new Object[]{"de.audi.atip.interapp.combi.bap.audio.CombiBAPServiceMedia"});
                if (ref != null) {
                    Method getService = bc.getClass().getMethod("getService", new Class[]{ref.getClass()});
                    Object svc = getService.invoke(bc, new Object[]{ref});
                    if (svc != null && "de.audi.app.combi.bap.app.audio.AppConnectorMedia".equals(svc.getClass().getName())) {
                        Method unget = bc.getClass().getMethod("ungetService", new Class[]{ref.getClass()});
                        unget.invoke(bc, new Object[]{ref});
                        debugLog("findMediaConnector: found via OSGi CombiBAPServiceMedia");
                        return svc;
                    }
                    if (svc != null) {
                        Method unget = bc.getClass().getMethod("ungetService", new Class[]{ref.getClass()});
                        unget.invoke(bc, new Object[]{ref});
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
                Method getMediaService = cls.getMethod("getMediaService", new Class[0]);
                Object mod = findStaticInstance(cls);
                if (mod != null) {
                    Object svc = getMediaService.invoke(mod, new Object[0]);
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
        ClassLoader tccl = Thread.currentThread().getContextClassLoader();
        if (tccl != null) {
            try {
                return Class.forName(name, true, tccl);
            } catch (ClassNotFoundException e) {
                // fall through to appClassLoader
            }
        }
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
        // First: direct AAJavaBridge reference (discovered by AndroidAuto2ListenerDistributor BFS walker)
        Object pm = AAJavaBridge.getPictureManager();
        if (pm != null) {
            debugLog("findPictureManager: found pictureManager via AAJavaBridge");
            return pm;
        }
        // Second: use CombiModule to get IPictureManager directly (no OSGi needed)
        Object combiModule = AAJavaBridge.getCombiModule();
        if (combiModule != null) {
            try {
                pictureManager = combiModule.getClass().getMethod(
                    "getPictureManager", new Class[0]).invoke(combiModule, new Object[0]);
                if (pictureManager != null) {
                    debugLog("findPictureManager: found via CombiModule.getPictureManager()");
                    return pictureManager;
                }
            } catch (Throwable t) {
                StringBuffer sb = new StringBuffer("findPictureManager: CombiModule.getPictureManager threw ");
                sb.append(t);
                debugLog(sb.toString());
            }
        }

        // Then: mediaConnector.getPictureManager() (existing code path)
        if (mediaConnector != null) {
            try {
                Method m = mediaConnector.getClass().getMethod("getPictureManager", new Class[0]);
                pm = m.invoke(mediaConnector, new Object[0]);
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
                Method getSR = bc.getClass().getMethod("getServiceReference", new Class[]{String.class});
                Object ref = getSR.invoke(bc, new Object[]{"de.audi.app.combi.bap.app.kombipictures.IPictureManager"});
                if (ref != null) {
                    Method getService = bc.getClass().getMethod("getService", new Class[]{ref.getClass()});
                    pm = getService.invoke(bc, new Object[]{ref});
                    if (pm != null) {
                        Method unget = bc.getClass().getMethod("ungetService", new Class[]{ref.getClass()});
                        unget.invoke(bc, new Object[]{ref});
                        debugLog("findPictureManager: found via OSGi IPictureManager");
                        return pm;
                    }
                    Method unget = bc.getClass().getMethod("ungetService", new Class[]{ref.getClass()});
                    unget.invoke(bc, new Object[]{ref});
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
                Method m = log.getClass().getMethod("log", new Class[]{int.class, String.class});
                m.invoke(log, new Object[]{new Integer(level), msg});
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
        StringBuffer sbt = new StringBuffer("handleNowPlayingData: trackData.toString()=");
        sbt.append(trackData.toString());
        debugLog(sbt.toString());
        try {
            java.lang.reflect.Method[] methods = trackData.getClass().getMethods();
            StringBuffer sbm = new StringBuffer("handleNowPlayingData: trackData getters=");
            for (int i = 0; i < methods.length; i++) {
                java.lang.reflect.Method m = methods[i];
                String mn = m.getName();
                if ((mn.startsWith("getCover") || mn.startsWith("getPicture") || mn.startsWith("getArt") || mn.startsWith("getTitle") || mn.startsWith("getArtist") || mn.startsWith("getAlbum"))
                    && m.getParameterTypes().length == 0) {
                    try {
                        Object v = m.invoke(trackData, new Object[0]);
                        sbm.append(mn);
                        sbm.append("=");
                        sbm.append(v != null ? v : "null");
                        sbm.append(";");
                    } catch (Throwable t) {
                        sbm.append(mn);
                        sbm.append("=<invoke threw>;");
                    }
                }
            }
            debugLog(sbm.toString());
        } catch (Throwable t) {
            StringBuffer sbx = new StringBuffer("handleNowPlayingData: trackData getter reflection threw ");
            sbx.append(t);
            debugLog(sbx.toString());
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
        // Inspect TrackData for embedded cover art ResourceLocator
        Object embeddedCoverLocator = null;
        try {
            java.lang.reflect.Method[] methods = trackData.getClass().getMethods();
            for (int i = 0; i < methods.length; i++) {
                java.lang.reflect.Method m = methods[i];
                String mn = m.getName();
                if ((mn.startsWith("getCover") || mn.startsWith("getPicture") || mn.startsWith("getArt"))
                    && m.getParameterTypes().length == 0) {
                    Object v = m.invoke(trackData, new Object[0]);
                    if (v != null && "org.dsi.ifc.global.ResourceLocator".equals(v.getClass().getName())) {
                        embeddedCoverLocator = v;
                        break;
                    }
                }
            }
        } catch (Throwable t) {
            StringBuffer sbx = new StringBuffer("handleNowPlayingData: TrackData cover art reflection threw ");
            sbx.append(t);
            debugLog(sbx.toString());
        }
        if (embeddedCoverLocator != null) {
            try {
                java.lang.reflect.Method getUrl = embeddedCoverLocator.getClass().getMethod("getUrl", new Class[0]);
                java.lang.reflect.Method getId = embeddedCoverLocator.getClass().getMethod("getId", new Class[0]);
                String ecUrl = (String) getUrl.invoke(embeddedCoverLocator, new Object[0]);
                int ecId = ((Integer) getId.invoke(embeddedCoverLocator, new Object[0])).intValue();
                if (ecUrl != null && !ecUrl.equals(lastCoverUrl)) {
                    lastCoverUrl = ecUrl;
                    lastPictureId = ecId;
                    StringBuffer sbc = new StringBuffer("handleNowPlayingData: embedded cover art url='");
                    sbc.append(ecUrl);
                    sbc.append("' pictureId=");
                    sbc.append(ecId);
                    debugLog(sbc.toString());
                }
            } catch (Throwable t) {
                StringBuffer sbx = new StringBuffer("handleNowPlayingData: embedded cover locator read threw ");
                sbx.append(t);
                debugLog(sbx.toString());
            }
        }
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
            Method setPrimary = infoCls.getMethod("setPrimaryInformation", new Class[]{String.class, int.class, int.class});
            setPrimary.invoke(info, new Object[]{title, new Integer(0), new Integer(0)});
            Method setSecondary = infoCls.getMethod("setSecondaryInformation", new Class[]{String.class, int.class});
            setSecondary.invoke(info, new Object[]{artist, new Integer(0)});
            Method setTertiary = infoCls.getMethod("setTertiaryInformation", new Class[]{String.class, int.class});
            setTertiary.invoke(info, new Object[]{album, new Integer(0)});
            Method setPicture = infoCls.getMethod("setPicture", new Class[]{int.class, String.class});
            setPicture.invoke(info, new Object[]{new Integer(lastPictureId), lastCoverUrl});
            Method setListRef = infoCls.getMethod("setListRef", new Class[]{int.class});
            setListRef.invoke(info, new Object[]{new Integer((int) (System.currentTimeMillis() & 0x7FFFFFFF))});
            Method getListRef = infoCls.getMethod("getListRef", new Class[0]);
            lastListRef = ((Integer) getListRef.invoke(info, new Object[0])).intValue();

            // Send updateCurrentStation to AppConnectorTerminalMode (active audio app during Android Auto)
            Object combiModule = AAJavaBridge.getCombiModule();
            Object terminalModeService = null;
            Object pictureManager = null;
            if (combiModule != null) {
                try {
                    terminalModeService = combiModule.getClass().getMethod(
                        "getTerminalModeService", new Class[0]).invoke(combiModule, new Object[0]);
                } catch (Throwable t) {
                    StringBuffer sbx = new StringBuffer("handleNowPlayingData: getTerminalModeService threw ");
                    sbx.append(t);
                    debugLog(sbx.toString());
                }
                try {
                pictureManager = combiModule.getClass().getMethod(
                        "getPictureManager", new Class[0]).invoke(combiModule, new Object[0]);
                } catch (Throwable t) {
                    StringBuffer sbx = new StringBuffer("handleNowPlayingData: getPictureManager threw ");
                    sbx.append(t);
                    debugLog(sbx.toString());
                }
            }
            if (terminalModeService != null) {
                try {
                    Method updateCurrentStation = terminalModeService.getClass().getMethod(
                        "updateCurrentStation", new Class[]{infoCls});
                    updateCurrentStation.invoke(terminalModeService, new Object[]{info});
                    StringBuffer sb4 = new StringBuffer("handleNowPlayingData: AppConnectorTerminalMode.updateCurrentStation(info) called, listRef=");
                    sb4.append(lastListRef);
                    debugLog(sb4.toString());
                } catch (Throwable t) {
                    StringBuffer sbx = new StringBuffer("handleNowPlayingData: terminalModeService.updateCurrentStation threw ");
                    sbx.append(t);
                    debugLog(sbx.toString());
                }
            }
            if (pictureManager != null && lastCoverUrl != null && lastCoverUrl.length() > 0) {
                try {
                    // Build ResourceLocator for cover art
                    Class<?> locatorCls = forName("org.dsi.ifc.global.ResourceLocator");
                    Object coverLocator = locatorCls.getDeclaredConstructor(
                        new Class[]{int.class, String.class}).newInstance(new Object[]{new Integer(lastPictureId), lastCoverUrl});
                    Method responseStationArt = pictureManager.getClass().getMethod(
                        "responseStationArt", new Class[]{long.class, int.class, locatorCls, boolean.class});
                    responseStationArt.invoke(pictureManager, new Object[]{
                        new Long(lastListRef), new Integer(SOURCE_TYPE_BT_STREAM), coverLocator, new Boolean(true)});
                    StringBuffer sb5 = new StringBuffer("handleNowPlayingData: IPictureManager.responseStationArt called, listRef=");
                    sb5.append(lastListRef);
                    debugLog(sb5.toString());
                    try {
                        Method responseCoverArt = pictureManager.getClass().getMethod(
                            "responseCoverArt", new Class[]{long.class, int.class, locatorCls, boolean.class});
                        responseCoverArt.invoke(pictureManager, new Object[]{
                            new Long(lastListRef), new Integer(SOURCE_TYPE_BT_STREAM), coverLocator, new Boolean(false)});
                        StringBuffer sb5b = new StringBuffer("handleNowPlayingData: IPictureManager.responseCoverArt called, listRef=");
                        sb5b.append(lastListRef);
                        debugLog(sb5b.toString());
                    } catch (Throwable t) {
                        StringBuffer sbx = new StringBuffer("handleNowPlayingData: responseCoverArt threw ");
                        sbx.append(t);
                        debugLog(sbx.toString());
                    }
                } catch (Throwable t) {
                    StringBuffer sbx = new StringBuffer("handleNowPlayingData: responseStationArt threw ");
                    sbx.append(t);
                    debugLog(sbx.toString());
                }
            }
            logCall(100000, "track updated");
        } catch (Throwable t) {
            logCall(1000000, "handleNowPlayingData failed");
            StringBuffer sb5 = new StringBuffer("handleNowPlayingData: threw ");
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
            Method setPrimary = infoCls.getMethod("setPrimaryInformation", new Class[]{String.class, int.class, int.class});
            setPrimary.invoke(info, new Object[]{lastTitle, new Integer(0), new Integer(0)});
            Method setSecondary = infoCls.getMethod("setSecondaryInformation", new Class[]{String.class, int.class});
            setSecondary.invoke(info, new Object[]{lastArtist, new Integer(0)});
            Method setTertiary = infoCls.getMethod("setTertiaryInformation", new Class[]{String.class, int.class});
            setTertiary.invoke(info, new Object[]{lastAlbum, new Integer(0)});
            Method setPicture = infoCls.getMethod("setPicture", new Class[]{int.class, String.class});
            setPicture.invoke(info, new Object[]{new Integer(lastPictureId), lastCoverUrl});
            Method setListRef = infoCls.getMethod("setListRef", new Class[]{int.class});
            setListRef.invoke(info, new Object[]{new Integer((int) (System.currentTimeMillis() & 0x7FFFFFFF))});
            Method getListRef = infoCls.getMethod("getListRef", new Class[0]);
            lastListRef = ((Integer) getListRef.invoke(info, new Object[0])).intValue();

            // Send updateCurrentStation to AppConnectorTerminalMode (active audio app during Android Auto)
            Object combiModule = AAJavaBridge.getCombiModule();
            Object terminalModeService = null;
            Object pictureManager2 = null;
            if (combiModule != null) {
                try {
                    terminalModeService = combiModule.getClass().getMethod(
                        "getTerminalModeService", new Class[0]).invoke(combiModule, new Object[0]);
                } catch (Throwable t) {
                    StringBuffer sbx = new StringBuffer("handleCoverArtUrl: getTerminalModeService threw ");
                    sbx.append(t);
                    debugLog(sbx.toString());
                }
                try {
                    pictureManager2 = combiModule.getClass().getMethod(
                        "getPictureManager", new Class[0]).invoke(combiModule, new Object[0]);
                } catch (Throwable t) {
                    StringBuffer sbx = new StringBuffer("handleCoverArtUrl: getPictureManager threw ");
                    sbx.append(t);
                    debugLog(sbx.toString());
                }
            }
            if (terminalModeService != null) {
                try {
                    Method updateCurrentStation = terminalModeService.getClass().getMethod(
                        "updateCurrentStation", new Class[]{infoCls});
                    updateCurrentStation.invoke(terminalModeService, new Object[]{info});
                    StringBuffer sb6 = new StringBuffer("handleCoverArtUrl: AppConnectorTerminalMode.updateCurrentStation(info) called, listRef=");
                    sb6.append(lastListRef);
                    debugLog(sb6.toString());
                } catch (Throwable t) {
                    StringBuffer sbx = new StringBuffer("handleCoverArtUrl: terminalModeService.updateCurrentStation threw ");
                    sbx.append(t);
                    debugLog(sbx.toString());
                }
            }
            if (pictureManager2 != null && lastCoverUrl != null && lastCoverUrl.length() > 0) {
                try {
                    Class<?> locatorCls = forName("org.dsi.ifc.global.ResourceLocator");
                    Object coverLocator = locatorCls.getDeclaredConstructor(
                        new Class[]{int.class, String.class}).newInstance(new Object[]{new Integer(lastPictureId), lastCoverUrl});
                    Method responseStationArt = pictureManager2.getClass().getMethod(
                        "responseStationArt", new Class[]{long.class, int.class, locatorCls, boolean.class});
                    responseStationArt.invoke(pictureManager2, new Object[]{
                        new Long(lastListRef), new Integer(SOURCE_TYPE_BT_STREAM), coverLocator, new Boolean(true)});
                    StringBuffer sb7 = new StringBuffer("handleCoverArtUrl: IPictureManager.responseStationArt called, listRef=");
                    sb7.append(lastListRef);
                    debugLog(sb7.toString());
                    try {
                        Method responseCoverArt = pictureManager2.getClass().getMethod(
                            "responseCoverArt", new Class[]{long.class, int.class, locatorCls, boolean.class});
                        responseCoverArt.invoke(pictureManager2, new Object[]{
                            new Long(lastListRef), new Integer(SOURCE_TYPE_BT_STREAM), coverLocator, new Boolean(false)});
                        StringBuffer sb7b = new StringBuffer("handleCoverArtUrl: IPictureManager.responseCoverArt called, listRef=");
                        sb7b.append(lastListRef);
                        debugLog(sb7b.toString());
                    } catch (Throwable t) {
                        StringBuffer sbx = new StringBuffer("handleCoverArtUrl: responseCoverArt threw ");
                        sbx.append(t);
                        debugLog(sbx.toString());
                    }
                } catch (Throwable t) {
                    StringBuffer sbx = new StringBuffer("handleCoverArtUrl: responseStationArt threw ");
                    sbx.append(t);
                    debugLog(sbx.toString());
                }
            }
            logCall(100000, "cover art updated via updateCurrentStation");
        } catch (Throwable t) {
            logCall(1000000, "handleCoverArtUrl failed");
            StringBuffer sb5 = new StringBuffer("handleCoverArtUrl: threw ");
            sb5.append(t);
            debugLog(sb5.toString());
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
}
