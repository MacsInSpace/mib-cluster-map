package com.mhi2.androidadio;

import java.io.FileInputStream;
import java.io.FileWriter;
import java.io.PrintWriter;
import java.lang.reflect.Method;
import java.text.SimpleDateFormat;
import java.util.Date;
import java.util.zip.CRC32;
import org.dsi.ifc.androidauto2.TrackData;
import org.dsi.ifc.global.ResourceLocator;

public class AATrackProvider {
    private static AATrackProvider instance;
    private Object log;
    private Object terminalModeService;
    private String lastTitle;
    private String lastArtist;
    private String lastAlbum;
    private String lastCoverUrl;
    private long lastDurationMs;
    private boolean sentWithoutCover;
    // Which cover art file is currently active: "/tmp/gal_albumArt_1.png" / "_2.png".
    // Set by normalizeCoverArtUrl().
    private String currentCoverPath;
    // Non-zero CRC32-derived pictureId (31-bit, >0). 0 means "no picture" to
    // Audi's PictureManager, so we always force >= 1.
    private int currentPicId;

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
        lastDurationMs = 0;
        sentWithoutCover = false;
        currentCoverPath = "";
        currentPicId = 0;
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

    private static Object findStaticInstance(Class<?> cls) throws Exception {
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

    private Object findTerminalModeService() {
        // First: direct AAJavaBridge references (discovered by AndroidAuto2ListenerDistributor BFS walker)
        Object tms = AAJavaBridge.getTerminalModeConnector();
        if (tms != null) {
            debugLog("findTerminalModeService: found terminalModeConnector via AAJavaBridge");
            return tms;
        }
        // Second: use CombiModule captured by AppConnectorMedia constructor (bootclasspath override)
        Object combiModule = AAJavaBridge.getCombiModule();
        if (combiModule != null) {
            try {
                Object service = combiModule.getClass().getMethod(
                    "getTerminalModeService", new Class[0]).invoke(combiModule, new Object[0]);
                if (service != null) {
                    debugLog("findTerminalModeService: found AppConnectorTerminalMode via CombiModule.getTerminalModeService()");
                    return service;
                }
            } catch (Throwable t) {
                StringBuffer sb = new StringBuffer("findTerminalModeService: getTerminalModeService threw ");
                sb.append(t);
                debugLog(sb.toString());
            }
        }
        debugLog("findTerminalModeService: returning null");
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

    private String normalizeCoverArtUrl(String url) {
        // Use /tmp/gal_albumArt_1.png / _2.png directly (already 256x256
        // written by gal / DSIAndroidAuto2). Strip "file://" prefix if present.
        String chosen = "";
        if (url != null) {
            chosen = url;
            if (chosen.startsWith("file://")) {
                chosen = chosen.substring(7);
            }
        }
        currentCoverPath = chosen;
        currentPicId = 0;
        try {
            java.io.File f = new java.io.File(chosen);
            if (f.exists() && f.length() > 0) {
                // Compute CRC32 of file content -> non-zero 31-bit pictureId.
                // Audi's PictureManager treats pictureId <= 0 as "no picture".
                CRC32 crc32 = new CRC32();
                FileInputStream fis = new FileInputStream(f);
                byte[] buf = new byte[8192];
                int n;
                while ((n = fis.read(buf)) > 0) {
                    crc32.update(buf, 0, n);
                }
                fis.close();
                long crcVal = crc32.getValue();
                int picId = (int)(crcVal & 0x7FFFFFFFL);
                if (picId == 0) picId = 1;
                currentPicId = picId;
                StringBuffer sb = new StringBuffer("normalizeCoverArtUrl: chosen=");
                sb.append(chosen);
                sb.append(" size=");
                sb.append(f.length());
                sb.append(" picId=");
                sb.append(picId);
                debugLog(sb.toString());
            } else {
                StringBuffer sbnf = new StringBuffer("normalizeCoverArtUrl: file does not exist or empty: ");
                sbnf.append(chosen);
                debugLog(sbnf.toString());
            }
        } catch (Throwable t) {
            StringBuffer sb = new StringBuffer("normalizeCoverArtUrl: threw ");
            sb.append(t);
            debugLog(sb.toString());
        }
        return chosen;
    }

    private void sendCurrentStation(Object info, int effectivePicId, String coverPath) throws Exception {
        Class<?> infoCls = info.getClass();
        Method setListRef = infoCls.getMethod("setListRef", new Class[]{int.class});
        // Virtual Cockpit rejects non-zero listRef! Must be 0.
        setListRef.invoke(info, new Object[]{new Integer(0)});
        Method setListAbsPos = infoCls.getMethod("setListAbsolutePosition", new Class[]{int.class});
        setListAbsPos.invoke(info, new Object[]{new Integer(0)});
        // Set cover art when we have a non-zero pictureId
        if (coverPath != null && coverPath.length() > 0 && effectivePicId != 0) {
            Method setPicture = infoCls.getMethod("setPicture", new Class[]{int.class, String.class});
            setPicture.invoke(info, new Object[]{new Integer(effectivePicId), coverPath});
            StringBuffer sb = new StringBuffer("sendCurrentStation: setPicture picId=");
            sb.append(effectivePicId);
            sb.append(" path=");
            sb.append(coverPath);
            debugLog(sb.toString());
        }
        // Invoke terminalModeService.updateCurrentStation(info)
        Object tms = terminalModeService;
        if (tms == null) {
            tms = findTerminalModeService();
            terminalModeService = tms;
        }
        if (tms != null) {
            Class<?> tmsCls = tms.getClass();
            Method ucs = null;
            Class<?> scan = tmsCls;
            while (scan != null && ucs == null) {
                try {
                    ucs = scan.getDeclaredMethod("updateCurrentStation", new Class[]{infoCls});
                } catch (NoSuchMethodException e) {
                    scan = scan.getSuperclass();
                }
            }
            if (ucs != null) {
                ucs.setAccessible(true);
                ucs.invoke(tms, new Object[]{info});
                StringBuffer sb = new StringBuffer("sendCurrentStation: terminalModeService.updateCurrentStation(info) called");
                debugLog(sb.toString());
            } else {
                debugLog("sendCurrentStation: updateCurrentStation method not found");
            }
            // Invoke terminalModeService.updateActiveInfoState(0)
            Method uais = null;
            Class<?> scan2 = tmsCls;
            while (scan2 != null && uais == null) {
                try {
                    uais = scan2.getDeclaredMethod("updateActiveInfoState", new Class[]{int.class});
                } catch (NoSuchMethodException e) {
                    scan2 = scan2.getSuperclass();
                }
            }
            if (uais != null) {
                uais.setAccessible(true);
                uais.invoke(tms, new Object[]{new Integer(0)});
                StringBuffer sb2 = new StringBuffer("sendCurrentStation: terminalModeService.updateActiveInfoState(0) called");
                debugLog(sb2.toString());
            } else {
                debugLog("sendCurrentStation: updateActiveInfoState method not found");
            }
        } else {
            debugLog("sendCurrentStation: no terminalModeService");
        }
    }

    public void handleNowPlayingData(TrackData trackData, int instanceId) {
        StringBuffer sb = new StringBuffer("handleNowPlayingData called, trackData=");
        sb.append(trackData != null ? "non-null" : "null");
        debugLog(sb.toString());
        if (trackData == null) {
            debugLog("handleNowPlayingData: returning early (null trackData)");
            return;
        }
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
        String title = trackData.getTitle();
        String artist = trackData.getArtist();
        String album = trackData.getAlbum();
        long durationMs = 0;
        try {
            java.lang.reflect.Method getDuration = trackData.getClass().getMethod("getDuration", new Class[0]);
            Object dur = getDuration.invoke(trackData, new Object[0]);
            if (dur instanceof Integer) {
                durationMs = ((Integer) dur).intValue();
            } else if (dur instanceof Long) {
                durationMs = ((Long) dur).longValue();
            }
        } catch (Throwable t) {
            StringBuffer sbx = new StringBuffer("handleNowPlayingData: getDuration threw ");
            sbx.append(t);
            debugLog(sbx.toString());
        }
        lastDurationMs = durationMs;
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
        String coverUrl = "";
        if (embeddedCoverLocator != null) {
            try {
                java.lang.reflect.Method getUrl = embeddedCoverLocator.getClass().getMethod("getUrl", new Class[0]);
                java.lang.reflect.Method getId = embeddedCoverLocator.getClass().getMethod("getId", new Class[0]);
                String ecUrl = (String) getUrl.invoke(embeddedCoverLocator, new Object[0]);
                int ecId = ((Integer) getId.invoke(embeddedCoverLocator, new Object[0])).intValue();
                if (ecUrl != null && !ecUrl.equals(lastCoverUrl)) {
                    lastCoverUrl = ecUrl;
                }
                StringBuffer sbc = new StringBuffer("handleNowPlayingData: embedded cover art url='");
                sbc.append(ecUrl);
                sbc.append("' picId=");
                sbc.append(currentPicId);
                debugLog(sbc.toString());
            } catch (Throwable t) {
                StringBuffer sbx = new StringBuffer("handleNowPlayingData: embedded cover locator read threw ");
                sbx.append(t);
                debugLog(sbx.toString());
            }
        }
        coverUrl = lastCoverUrl;
        // Always refresh currentPicId from lastCoverUrl (may have been set by handleCoverArtUrl)
        normalizeCoverArtUrl(lastCoverUrl);
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
        try {
            Class<?> infoCls = forName("de.audi.atip.interapp.combi.bap.audio.data.CombiBAPCurrentStationInfo");
            if (infoCls == null) {
                debugLog("CombiBAPCurrentStationInfo not found");
                return;
            }
            Object info = infoCls.getDeclaredConstructor().newInstance();
            // TerminalModeBapCombi pattern: pType=6 for title, sType=73 for artist, tType=74 for album
            int pType = title.length() > 0 ? 6 : 0;
            Method setPrimary = infoCls.getMethod("setPrimaryInformation", new Class[]{String.class, int.class, int.class});
            setPrimary.invoke(info, new Object[]{title, new Integer(pType), new Integer(0)});
            int sType = artist.length() > 0 ? 73 : 0;
            Method setSecondary = infoCls.getMethod("setSecondaryInformation", new Class[]{String.class, int.class});
            setSecondary.invoke(info, new Object[]{artist, new Integer(sType)});
            int tType = album.length() > 0 ? 74 : 0;
            Method setTertiary = infoCls.getMethod("setTertiaryInformation", new Class[]{String.class, int.class});
            setTertiary.invoke(info, new Object[]{album, new Integer(tType)});
            // Virtual Cockpit rejects non-zero listRef! Must be 0.
            // Virtual Cockpit rejects non-zero listAbsolutePosition! Must be 0.
            int effectivePicId = currentPicId;
            if (coverUrl != null && coverUrl.length() > 0 && currentPicId != 0) {
                if (sentWithoutCover) {
                    // Cover art arrived after track text was already sent without it.
                    // Force a picture refresh by using picId + 1 (or 1 if picId+1 == 0).
                    effectivePicId = currentPicId + 1;
                    if (effectivePicId == 0) effectivePicId = 1;
                    StringBuffer sbw = new StringBuffer("handleNowPlayingData: late cover art, sentWithoutCover=true, effectivePicId=");
                    sbw.append(effectivePicId);
                    debugLog(sbw.toString());
                    sentWithoutCover = false;
                }
            } else if (coverUrl != null && coverUrl.length() > 0 && currentPicId == 0) {
                // Cover art URL present but no valid picId -> send without cover
                sentWithoutCover = true;
            } else {
                sentWithoutCover = false;
            }
            sendCurrentStation(info, effectivePicId, coverUrl);
        } catch (Throwable t) {
            StringBuffer sbx = new StringBuffer("handleNowPlayingData: threw ");
            sbx.append(t);
            debugLog(sbx.toString());
        }
        logCall(1000000, "handleNowPlayingData completed");
    }

    public void handleCoverArtUrl(ResourceLocator resourceLocator, int instanceId) {
        StringBuffer sb = new StringBuffer("handleCoverArtUrl called, resourceLocator=");
        sb.append(resourceLocator != null ? "non-null" : "null");
        debugLog(sb.toString());
        if (resourceLocator == null) {
            debugLog("handleCoverArtUrl: returning early (null resourceLocator)");
            return;
        }
        String url = resourceLocator.getUrl();
        if (url == null) url = "";
        boolean changed = !url.equals(lastCoverUrl);
        lastCoverUrl = url;
        normalizeCoverArtUrl(lastCoverUrl);
        StringBuffer sb3 = new StringBuffer("handleCoverArtUrl: url='");
        sb3.append(url);
        sb3.append("' picId=");
        sb3.append(currentPicId);
        sb3.append(" changed=");
        sb3.append(changed);
        debugLog(sb3.toString());
        if (!changed && lastTitle.length() == 0 && lastArtist.length() == 0) {
            debugLog("handleCoverArtUrl: no change and no track info, returning");
            return;
        }
        try {
            Class<?> infoCls = forName("de.audi.atip.interapp.combi.bap.audio.data.CombiBAPCurrentStationInfo");
            if (infoCls == null) {
                debugLog("CombiBAPCurrentStationInfo not found");
                return;
            }
            Object info = infoCls.getDeclaredConstructor().newInstance();
            int pType = lastTitle.length() > 0 ? 6 : 0;
            Method setPrimary = infoCls.getMethod("setPrimaryInformation", new Class[]{String.class, int.class, int.class});
            setPrimary.invoke(info, new Object[]{lastTitle, new Integer(pType), new Integer(0)});
            int sType = lastArtist.length() > 0 ? 73 : 0;
            Method setSecondary = infoCls.getMethod("setSecondaryInformation", new Class[]{String.class, int.class});
            setSecondary.invoke(info, new Object[]{lastArtist, new Integer(sType)});
            int tType = lastAlbum.length() > 0 ? 74 : 0;
            Method setTertiary = infoCls.getMethod("setTertiaryInformation", new Class[]{String.class, int.class});
            setTertiary.invoke(info, new Object[]{lastAlbum, new Integer(tType)});
            // Virtual Cockpit rejects non-zero listRef! Must be 0.
            Method setListRef = infoCls.getMethod("setListRef", new Class[]{int.class});
            setListRef.invoke(info, new Object[]{new Integer(0)});
            Method setListAbsPos = infoCls.getMethod("setListAbsolutePosition", new Class[]{int.class});
            setListAbsPos.invoke(info, new Object[]{new Integer(0)});
            int effectivePicId = currentPicId;
            if (changed && currentPicId != 0) {
                // Cover art arrived after track text was already sent without it.
                // Force a picture refresh by using picId + 1 (or 1 if picId+1 == 0).
                effectivePicId = currentPicId + 1;
                if (effectivePicId == 0) effectivePicId = 1;
                sentWithoutCover = false;
                StringBuffer sbw = new StringBuffer("handleCoverArtUrl: cover art changed, effectivePicId=");
                sbw.append(effectivePicId);
                debugLog(sbw.toString());
            } else if (!changed && currentPicId != 0) {
                effectivePicId = currentPicId;
            }
            sendCurrentStation(info, effectivePicId, lastCoverUrl);
        } catch (Throwable t) {
            StringBuffer sbx = new StringBuffer("handleCoverArtUrl: threw ");
            sbx.append(t);
            debugLog(sbx.toString());
        }
        logCall(1000000, "handleCoverArtUrl completed");
    }

    public void handlePlayPosition(int position, int instanceId) {
        if (terminalModeService == null) {
            Object tms = findTerminalModeService();
            terminalModeService = tms;
        }
        if (terminalModeService != null) {
            try {
                Class<?> playPositionCls = forName("de.audi.atip.interapp.combi.bap.audio.data.PlayPosition");
                if (playPositionCls != null) {
                    Class<?> builderCls = forName("de.audi.atip.interapp.combi.bap.audio.data.PlayPosition$Builder");
                    Object builder = builderCls.getDeclaredConstructor().newInstance();
                    Class<?> timeStampCls = forName("de.audi.atip.interapp.bap.data.TimeStamp");
                    Object elapsed = timeStampCls.getMethod("getInstanceFromSeconds", new Class[]{int.class}).invoke(null, new Object[]{new Integer(position / 1000)});
                    Object totalSecs = timeStampCls.getMethod("getInstanceFromSeconds", new Class[]{int.class}).invoke(null, new Object[]{new Integer((int) (lastDurationMs / 1000))});
                    Method setTimePosition = builderCls.getMethod("setTimePosition", new Class[]{timeStampCls});
                    Method setTotalPlayTime = builderCls.getMethod("setTotalPlayTime", new Class[]{timeStampCls});
                    Method setVariableBitRate = builderCls.getMethod("setVariableBitRate", new Class[]{boolean.class});
                    Method build = builderCls.getMethod("build", new Class[0]);
                    setTimePosition.invoke(builder, new Object[]{elapsed});
                    setTotalPlayTime.invoke(builder, new Object[]{totalSecs});
                    setVariableBitRate.invoke(builder, new Object[]{new Boolean(false)});
                    Object playPos = build.invoke(builder, new Object[0]);
                    Method updatePlayPosition = terminalModeService.getClass().getMethod("updatePlayPosition", new Class[]{playPositionCls});
                    updatePlayPosition.setAccessible(true);
                    updatePlayPosition.invoke(terminalModeService, new Object[]{playPos});
                    StringBuffer sbpp = new StringBuffer("handlePlayPosition: PlayPosition(");
                    sbpp.append(position / 1000);
                    sbpp.append("/");
                    sbpp.append(lastDurationMs / 1000);
                    sbpp.append(") sent to terminalModeService.updatePlayPosition");
                    debugLog(sbpp.toString());
                }
            } catch (Throwable t) {
                StringBuffer sbx = new StringBuffer("handlePlayPosition: terminalModeService.updatePlayPosition threw ");
                sbx.append(t);
                debugLog(sbx.toString());
            }
        }
    }

    private void debugLog(String msg) {
        StringBuffer sb = new StringBuffer("[AATrackProvider] ");
        sb.append(msg);
        System.out.println(sb.toString());
        logCall(100000, msg);
    }
}
