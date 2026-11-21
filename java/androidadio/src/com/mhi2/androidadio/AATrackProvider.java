package com.mhi2.androidadio;

import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.FileWriter;
import java.io.PrintWriter;
import java.lang.reflect.InvocationHandler;
import java.lang.reflect.Method;
import java.lang.reflect.Proxy;
import java.text.SimpleDateFormat;
import java.util.Date;
import java.util.zip.CRC32;
import org.dsi.ifc.androidauto2.TrackData;
import org.dsi.ifc.global.ResourceLocator;

public class AATrackProvider {
    private static AATrackProvider instance;
    private Object log;
    private Object terminalModeService;
    private Object combiModule;
    private Object pictureManager;
    private Object mediaConnector;
    private String lastTitle;
    private String lastArtist;
    private String lastAlbum;
    private String lastCoverUrl;
    private long lastDurationMs;
    private boolean sentWithoutCover;
    // Non-zero 16-bit listRef (1..65534) used in responseCoverArt() so the
    // Virtual Cockpit matches cover art to its requestPicture() entry.
    private long lastListRef;
    // Which cover art file is currently active: "/tmp/gal_albumArt_1.png" / "_2.png".
    // Set by normalizeCoverArtUrl().
    private String currentCoverPath;
    // Non-zero CRC32-derived pictureId (31-bit, >0). 0 means "no picture" to
    // Audi's PictureManager, so we always force >= 1.
    private int currentPicId;
    // Live ActiveSource_Status.sourceType from BAP Function 16.
    private int currentSourceType;
    // Instance fields read by IPictureProvider proxy so it always serves the
    // latest track's cover art (registered once, not per-track).
    private Object currentPictureManager;
    private boolean pictureProviderRegistered;

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
        lastListRef = 0;
        currentCoverPath = "";
        currentPicId = 0;
        currentSourceType = 21;
        currentPictureManager = null;
        pictureProviderRegistered = false;
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
        Object cm = AAJavaBridge.getCombiModule();
        if (cm != null) {
            try {
                Object service = cm.getClass().getMethod(
                    "getTerminalModeService", new Class[0]).invoke(cm, new Object[0]);
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

    private Object findPictureManager() {
        Object pm = AAJavaBridge.getPictureManager();
        if (pm != null) {
            debugLog("findPictureManager: found pictureManager via AAJavaBridge");
            return pm;
        }
        Object cm = AAJavaBridge.getCombiModule();
        if (cm != null) {
            try {
                pictureManager = cm.getClass().getMethod(
                    "getPictureManager", new Class[0]).invoke(cm, new Object[0]);
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

    private String normalizeCoverArtUrl(String url) {
        // Use /tmp/gal_albumArt_1.png / _2.png directly (raw filesystem path,
        // already 256x256 written by gal / DSIAndroidAuto2). Strip "file://"
        // prefix if present.
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
            File f = new File(chosen);
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
                // Audi MHI2's DSIKombiPictureServer reads cover art from
                // /var/app/icab/tmp/37/coverart.png (not /tmp/). Copy the PNG
                // there atomically when /var/app/icab/tmp exists, otherwise
                // fall back to the /tmp path.
                String destPath = chosen;
                File icabTmp = new File("/var/app/icab/tmp");
                if (icabTmp.exists()) {
                    File destDir = new File(icabTmp, "37");
                    destDir.mkdirs();
                    File destTmp = new File(destDir, "aa_cover.tmp");
                    File dest = new File(destDir, "aa_cover.png");
                    FileOutputStream fos = new FileOutputStream(destTmp);
                    FileInputStream src = new FileInputStream(f);
                    byte[] cbuf = new byte[8192];
                    int cn;
                    while ((cn = src.read(cbuf)) > 0) {
                        fos.write(cbuf, 0, cn);
                    }
                    src.close();
                    fos.close();
                    if (destTmp.renameTo(dest)) {
                        destPath = dest.getAbsolutePath();
                        StringBuffer sbd = new StringBuffer("normalizeCoverArtUrl: copied to ");
                        sbd.append(destPath);
                        sbd.append(" exists=");
                        sbd.append(dest.exists());
                        sbd.append(" size=");
                        sbd.append(dest.length());
                        debugLog(sbd.toString());
                    } else {
                        StringBuffer sbd = new StringBuffer("normalizeCoverArtUrl: renameTo failed, falling back to ");
                        sbd.append(chosen);
                        debugLog(sbd.toString());
                    }
                }
                currentCoverPath = destPath;
                StringBuffer sb = new StringBuffer("normalizeCoverArtUrl: chosen=");
                sb.append(chosen);
                sb.append(" size=");
                sb.append(f.length());
                sb.append(" picId=");
                sb.append(picId);
                sb.append(" coverPath=");
                sb.append(destPath);
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
        return currentCoverPath;
    }

    private int readSourceType() {
        int sourceType = 21;
        try {
            Object cm = AAJavaBridge.getCombiModule();
            if (cm == null) {
                combiModule = null;
                return sourceType;
            }
            combiModule = cm;
            Object func16 = cm.getClass().getMethod(
                "getBAPFunctionPropertyFSG", new Class[]{int.class}).invoke(cm, new Object[]{new Integer(16)});
            if (func16 != null) {
                Object status = func16.getClass().getMethod("getLastStatus", new Class[0]).invoke(func16, new Object[0]);
                if (status != null) {
                    java.lang.reflect.Field stField = status.getClass().getField("sourceType");
                    sourceType = stField.getInt(status);
                    StringBuffer sbst = new StringBuffer("readSourceType: activeSource.sourceType=");
                    sbst.append(sourceType);
                    debugLog(sbst.toString());
                }
            }
        } catch (Throwable t) {
            StringBuffer sbx = new StringBuffer("readSourceType: threw ");
            sbx.append(t);
            debugLog(sbx.toString());
        }
        currentSourceType = sourceType;
        return sourceType;
    }

    private void sendCurrentStation(Object info, int effectivePicId, String coverPath, long listRef) throws Exception {
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
            // Non-zero 16-bit listRef triggers VC requestPicture(bapEntryID=listRef, instanceId=0)
            setListRef.invoke(info, new Object[]{new Integer((int) listRef)});
            StringBuffer sb = new StringBuffer("sendCurrentStation: setPicture picId=");
            sb.append(effectivePicId);
            sb.append(" path=");
            sb.append(coverPath);
            sb.append(" listRef=");
            sb.append(listRef);
            debugLog(sb.toString());
        }
        // Proactively push cover art to IPictureManager so the VC's MOST picture
        // request resolves immediately. responseCoverArt(long, int, ResourceLocator, boolean).
        if (coverPath != null && coverPath.length() > 0 && effectivePicId != 0 && pictureManager != null) {
            try {
                Method rc = null;
                java.lang.reflect.Method[] allMethods = pictureManager.getClass().getMethods();
                for (int i = 0; i < allMethods.length; i++) {
                    java.lang.reflect.Method m = allMethods[i];
                    if ("responseCoverArt".equals(m.getName())
                        && m.getParameterTypes().length == 4) {
                        rc = m;
                        break;
                    }
                }
                if (rc != null) {
                    rc.setAccessible(true);
                    Class<?> locatorCls = forName("org.dsi.ifc.global.ResourceLocator");
                    Object locator = locatorCls.getDeclaredConstructor(
                        new Class[]{int.class, String.class}).newInstance(new Object[]{new Integer(effectivePicId), coverPath});
                    // Respond under sourceType (e.g. 39) so PictureManagerEvo caches by source type.
                    // stationArt = false, matching AppConnectorMedia.CoverArtProvider.requestPicture.
                    rc.invoke(pictureManager, new Object[]{new Long(listRef), new Integer(currentSourceType), locator, new Boolean(false)});
                    StringBuffer sbp = new StringBuffer("sendCurrentStation: proactive IPictureManager.responseCoverArt(listRef=");
                    sbp.append(listRef);
                    sbp.append(", sourceType=");
                    sbp.append(currentSourceType);
                    sbp.append(")");
                    debugLog(sbp.toString());
                    // Also respond under instanceId=0 so whichever key PictureManagerEvo
                    // expects matches.
                    rc.invoke(pictureManager, new Object[]{new Long(listRef), new Integer(0), locator, new Boolean(false)});
                    StringBuffer sbp2 = new StringBuffer("sendCurrentStation: proactive IPictureManager.responseCoverArt(listRef=");
                    sbp2.append(listRef);
                    sbp2.append(", instanceId=0)");
                    debugLog(sbp2.toString());
                    // Also push 65535L (PictureManagerEvo's sentinel for "no specific entry")
                    // under both sourceType and instanceId=0, so a pending requestPicture(65535)
                    // is matched even when listRef differs.
                    rc.invoke(pictureManager, new Object[]{new Long(65535L), new Integer(currentSourceType), locator, new Boolean(false)});
                    StringBuffer sbp3 = new StringBuffer("sendCurrentStation: proactive IPictureManager.responseCoverArt(65535L, sourceType=");
                    sbp3.append(currentSourceType);
                    sbp3.append(")");
                    debugLog(sbp3.toString());
                    rc.invoke(pictureManager, new Object[]{new Long(65535L), new Integer(0), locator, new Boolean(false)});
                    StringBuffer sbp4 = new StringBuffer("sendCurrentStation: proactive IPictureManager.responseCoverArt(65535L, instanceId=0)");
                    debugLog(sbp4.toString());
                } else {
                    debugLog("sendCurrentStation: responseCoverArt not found on PictureManager");
                }
            } catch (Throwable t) {
                StringBuffer sbx = new StringBuffer("sendCurrentStation: proactive responseCoverArt threw ");
                sbx.append(t);
                debugLog(sbx.toString());
            }
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
        if (pictureManager == null) {
            pictureManager = findPictureManager();
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
                String ecUrl = (String) getUrl.invoke(embeddedCoverLocator, new Object[0]);
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
        coverUrl = normalizeCoverArtUrl(lastCoverUrl);
        // Read live activeSource.sourceType from BAP Function 16
        readSourceType();
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
            // Generate non-zero 16-bit listRef when cover art is present.
            long listRef = 0;
            if (coverUrl != null && coverUrl.length() > 0 && currentPicId != 0) {
                listRef = ((System.currentTimeMillis() & 0x7FFFFFFFL) % 65533L) + 1;
                lastListRef = listRef;
                StringBuffer sbw = new StringBuffer("handleNowPlayingData: generated listRef=");
                sbw.append(listRef);
                debugLog(sbw.toString());
            } else if (coverUrl != null && coverUrl.length() > 0 && currentPicId == 0) {
                sentWithoutCover = true;
            } else {
                sentWithoutCover = false;
            }
            sendCurrentStation(info, effectivePicId(coverUrl), coverUrl, listRef);
        } catch (Throwable t) {
            StringBuffer sbx = new StringBuffer("handleNowPlayingData: threw ");
            sbx.append(t);
            debugLog(sbx.toString());
        }
        logCall(1000000, "handleNowPlayingData completed");
    }

    private int effectivePicId(String coverUrl) {
        if (coverUrl != null && coverUrl.length() > 0 && currentPicId != 0) {
            if (sentWithoutCover) {
                int ep = currentPicId + 1;
                if (ep == 0) ep = 1;
                sentWithoutCover = false;
                StringBuffer sbw = new StringBuffer("effectivePicId: late cover art, ep=");
                sbw.append(ep);
                debugLog(sbw.toString());
                return ep;
            }
            return currentPicId;
        }
        return 0;
    }

    public void handleCoverArtUrl(ResourceLocator resourceLocator, int instanceId) {
        StringBuffer sb = new StringBuffer("handleCoverArtUrl called, resourceLocator=");
        sb.append(resourceLocator != null ? "non-null" : "null");
        debugLog(sb.toString());
        if (resourceLocator == null) {
            debugLog("handleCoverArtUrl: returning early (null resourceLocator)");
            return;
        }
        if (pictureManager == null) {
            pictureManager = findPictureManager();
        }
        String url = resourceLocator.getUrl();
        if (url == null) url = "";
        boolean changed = !url.equals(lastCoverUrl);
        lastCoverUrl = url;
        String coverPath = normalizeCoverArtUrl(lastCoverUrl);
        // Read live activeSource.sourceType from BAP Function 16
        readSourceType();
        StringBuffer sb3 = new StringBuffer("handleCoverArtUrl: url='");
        sb3.append(url);
        sb3.append("' picId=");
        sb3.append(currentPicId);
        sb3.append(" sourceType=");
        sb3.append(currentSourceType);
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
            // Generate non-zero 16-bit listRef when cover art changed.
            long listRef = 0;
            if (changed && currentPicId != 0) {
                listRef = ((System.currentTimeMillis() & 0x7FFFFFFFL) % 65533L) + 1;
                lastListRef = listRef;
                sentWithoutCover = false;
                StringBuffer sbw = new StringBuffer("handleCoverArtUrl: cover art changed, listRef=");
                sbw.append(listRef);
                debugLog(sbw.toString());
            } else if (!changed && currentPicId != 0) {
                listRef = lastListRef > 0 && lastListRef < 65535 ? lastListRef : 1;
            }
            sendCurrentStation(info, effectivePicId(coverPath), coverPath, listRef);
            // Register IPictureProvider proxy once (AbstractPictureManager.requestCoverArt
            // looks up pictureProviders by type 0 hardcoded).
            if (pictureManager != null && !pictureProviderRegistered) {
                try {
                    Class<?> ipcCls = forName("de.audi.app.combi.bap.app.kombipictures.IPictureProvider");
                    ClassLoader cl = ipcCls.getClassLoader();
                    final Object pmRef = pictureManager;
                    Object proxy = Proxy.newProxyInstance(cl, new Class[]{ipcCls}, new InvocationHandler() {
                        public Object invoke(Object proxy, Method method, Object[] args) throws Throwable {
                            String mn = method.getName();
                            if ("requestPicture".equals(mn)) {
                                long bapEntryID2 = 0;
                                int instanceId2 = 255;
                                if (args != null && args.length >= 1 && args[0] instanceof Long) {
                                    bapEntryID2 = ((Long) args[0]).longValue();
                                }
                                if (args != null && args.length >= 2 && args[1] instanceof Integer) {
                                    instanceId2 = ((Integer) args[1]).intValue();
                                }
                                // Read latest instance fields dynamically (not stale finals)
                                Object pm2 = pmRef;
                                int st2 = currentSourceType;
                                String cv2 = currentCoverPath;
                                int pid2 = currentPicId;
                                StringBuffer sbp = new StringBuffer("IPictureProvider.proxy.requestPicture bapEntryID=");
                                sbp.append(bapEntryID2);
                                sbp.append(" instanceId=");
                                sbp.append(instanceId2);
                                sbp.append(" sourceType=");
                                sbp.append(st2);
                                sbp.append(" picId=");
                                sbp.append(pid2);
                                debugLog(sbp.toString());
                                if (pm2 != null) {
                                    try {
                                        Class<?> locatorCls3 = forName("org.dsi.ifc.global.ResourceLocator");
                                        Object locator3 = locatorCls3.getDeclaredConstructor(
                                            new Class[]{int.class, String.class}).newInstance(new Object[]{new Integer(pid2), cv2});
                                        Method rc2 = null;
                                        java.lang.reflect.Method[] pmMethods = pm2.getClass().getMethods();
                                        for (int i = 0; i < pmMethods.length; i++) {
                                            java.lang.reflect.Method m = pmMethods[i];
                                            if ("responseCoverArt".equals(m.getName())
                                                && m.getParameterTypes().length == 4) {
                                                rc2 = m;
                                                break;
                                            }
                                        }
                                        if (rc2 != null) {
                                            rc2.setAccessible(true);
                                            // Pass bapEntryID2 verbatim (e.g. 65535) — matching
                                            // AppConnectorMedia.CoverArtProvider.requestPicture,
                                            // so PictureManagerEvo matches the response to its
                                            // pending request. stationArt = false.
                                            rc2.invoke(pm2, new Object[]{new Long(bapEntryID2), new Integer(st2), locator3, new Boolean(false)});
                                            StringBuffer sb2 = new StringBuffer("IPictureProvider.proxy.responseCoverArt called bapEntryID=");
                                            sb2.append(bapEntryID2);
                                            sb2.append(" sourceType=");
                                            sb2.append(st2);
                                            debugLog(sb2.toString());
                                            if (instanceId2 != st2) {
                                                rc2.invoke(pm2, new Object[]{new Long(bapEntryID2), new Integer(instanceId2), locator3, new Boolean(false)});
                                                StringBuffer sb3 = new StringBuffer("IPictureProvider.proxy.responseCoverArt called bapEntryID=");
                                                sb3.append(bapEntryID2);
                                                sb3.append(" instanceId=");
                                                sb3.append(instanceId2);
                                                debugLog(sb3.toString());
                                            }
                                        }
                                    } catch (Throwable t) {
                                        StringBuffer sbx = new StringBuffer("IPictureProvider.proxy.responseCoverArt threw ");
                                        sbx.append(t);
                                        debugLog(sbx.toString());
                                    }
                                }
                            }
                            return null;
                        }
                    });
                    Method reg = pictureManager.getClass().getMethod(
                        "registerPictureProvider", new Class[]{int.class, ipcCls});
                    reg.setAccessible(true);
                    reg.invoke(pictureManager, new Object[]{new Integer(0), proxy});
                    reg.invoke(pictureManager, new Object[]{new Integer(currentSourceType), proxy});
                    pictureProviderRegistered = true;
                    StringBuffer sbReg = new StringBuffer("AATrackProvider: IPictureProvider proxy registered with type=0 and type=");
                    sbReg.append(currentSourceType);
                    debugLog(sbReg.toString());
                } catch (Throwable t) {
                    StringBuffer sbx = new StringBuffer("AATrackProvider: registerPictureProviderProxy threw ");
                    sbx.append(t);
                    debugLog(sbx.toString());
                }
            }
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
