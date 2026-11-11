package local.clustermap;

import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.net.DatagramPacket;
import java.net.DatagramSocket;
import java.net.InetAddress;

/**
 * mib-cluster-map: the steering-wheel roller zooms the CarPlay map on the
 * AU57x (A6/A7 C7.5, MOST) cockpit.
 *
 * The cockpit sends each roller step to the head unit, where the stock map
 * shown in the cockpit (CtxMapInKombi) hands it to its zoom timer. While the
 * CarPlay map covers that map, the step goes to the CarPlay hook in
 * dio_manager instead, as one 8-byte datagram on loopback UDP 19822:
 * "MZ01" and the signed step count, big-endian -- the format of aberbic's
 * Audi-MHI2-Virtual-Cockpit-Altscreen-CarPlay-AndroidAuto (GPL-3.0). The
 * hook turns it into CarPlay's changeMapZoomLevel for the cluster display.
 *
 * Stock zoom is left alone whenever anything here is not right: no CarPlay
 * stream, no supervisor, a send that fails. Java 1.2 class library and
 * language only (the unit's J9): no StringBuilder, boxing or class literals.
 */
public final class WheelZoom {
    /* Written by the hook: "streaming" while CarPlay sends its cluster video. */
    private static final String STATE = "/tmp/mibr-carplay111.state";
    /* Kept by carplay_cluster.sh while dio_manager lives; gone when it ends,
     * so a state file left behind by a crashed dio_manager does not count. */
    private static final String SUPERVISOR = "/tmp/carplay_cluster.pid";
    /* Touch it to give the roller back to the stock map until the next boot. */
    private static final String OFF = "/tmp/clustermap-wheelzoom-off";
    /* Written by the installer for CLUSTERMAP_CARPLAY_WHEEL_ZOOM=reverse. */
    private static final String REVERSE = "/mnt/app/eso/lib/gal_dualscreen/wheel_zoom_reverse";
    private static final String LOG = "/tmp/clustermap-wheelzoom.log";
    private static final int LOG_MAX = 32768;
    private static final int PORT = 19822;
    private static final int MAX_STEPS = 32;

    private static final Object LOCK = new Object();
    private static DatagramSocket socket;
    private static InetAddress loopback;
    private static boolean announced;

    private WheelZoom() {
    }

    /**
     * Called for every roller step on the cockpit map. True: CarPlay has the
     * cockpit and took the step, so the stock map must not zoom.
     */
    public static boolean forward(int steps) {
        if (steps == 0) {
            return false;
        }
        try {
            if (!carplayOnCockpit()) {
                return false;
            }
            if (new File(REVERSE).exists()) {
                steps = -steps;
            }
            if (steps > MAX_STEPS) {
                steps = MAX_STEPS;
            }
            if (steps < -MAX_STEPS) {
                steps = -MAX_STEPS;
            }
            byte[] b = new byte[8];
            b[0] = (byte) 'M';
            b[1] = (byte) 'Z';
            b[2] = (byte) '0';
            b[3] = (byte) '1';
            b[4] = (byte) (steps >> 24);
            b[5] = (byte) (steps >> 16);
            b[6] = (byte) (steps >> 8);
            b[7] = (byte) steps;
            synchronized (LOCK) {
                if (socket == null) {
                    loopback = InetAddress.getByName("127.0.0.1");
                    socket = new DatagramSocket();
                }
                socket.send(new DatagramPacket(b, 8, loopback, PORT));
            }
            log("to CarPlay: steps=", steps);
            return true;
        } catch (Throwable t) {
            synchronized (LOCK) {
                if (socket != null) {
                    try {
                        socket.close();
                    } catch (Throwable ignored) {
                    }
                    socket = null;
                }
            }
            logText(new StringBuffer("send failed, stock zoom: ").append(String.valueOf(t)).toString());
            return false;
        }
    }

    private static boolean carplayOnCockpit() {
        if (new File(OFF).exists() || !new File(SUPERVISOR).exists()) {
            return false;
        }
        FileInputStream in = null;
        try {
            byte[] b = new byte[16];
            in = new FileInputStream(STATE);
            int n = in.read(b);
            return n >= 9 && new String(b, 0, 9).equals("streaming");
        } catch (Throwable t) {
            return false;
        } finally {
            if (in != null) {
                try {
                    in.close();
                } catch (Throwable ignored) {
                }
            }
        }
    }

    /* For the timer: a stock call that failed, so the cause is on record. */
    public static void note(String what, String detail) {
        logText(new StringBuffer(64).append(System.currentTimeMillis()).append(' ').append(what).append(detail).toString());
    }

    private static void log(String what, int value) {
        StringBuffer s = new StringBuffer(64);
        if (!announced) {
            announced = true;
            s.append("wheel zoom bridge active (mib-cluster-map)\n");
        }
        s.append(System.currentTimeMillis()).append(' ').append(what).append(value);
        logText(s.toString());
    }

    private static void logText(String line) {
        FileOutputStream out = null;
        try {
            File f = new File(LOG);
            out = new FileOutputStream(LOG, f.length() < LOG_MAX);
            out.write(new StringBuffer(line).append('\n').toString().getBytes());
        } catch (Throwable ignored) {
        } finally {
            if (out != null) {
                try {
                    out.close();
                } catch (Throwable ignored) {
                }
            }
        }
    }
}
