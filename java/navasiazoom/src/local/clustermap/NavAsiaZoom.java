package local.clustermap;

import java.io.FileInputStream;

/**
 * mib-cluster-map: the cockpit roller and the CarPlay map on the Chinese
 * AU57x (MHI2_CN, Asia navigation).
 *
 * NavAsiaModelListener shows every increment and decrement of the
 * navigation's models here before the stock code passes it on. Each step is
 * logged with its model ID, so a log of the roller turned on the cockpit
 * tells which ID it is. Once that ID is written to ID_FILE, its steps go to
 * the CarPlay map through WheelZoom while CarPlay covers the cockpit; other
 * IDs, and all steps when CarPlay does not, go on to the navigation as before.
 * Java 1.2 class library and language only (the unit's J9).
 */
public final class NavAsiaZoom {
    /* The roller's model ID in decimal, written by the installer from
     * CLUSTERMAP_CARPLAY_WHEEL_ZOOM_ID. Read once; no file: log only. */
    private static final String ID_FILE = "/mnt/app/eso/lib/gal_dualscreen/wheel_zoom_id";
    private static final int UNREAD = -2;
    private static final int NONE = -1;
    private static int rollerId = UNREAD;

    private NavAsiaZoom() {
    }

    /** steps: signed, increment positive. True: CarPlay took it. */
    public static boolean step(int id, int steps) {
        try {
            int roller = rollerId();
            boolean sent = id == roller && WheelZoom.forward(steps);
            WheelZoom.note("model step: ", new StringBuffer(48).append("id=").append(id).append(" steps=").append(steps)
                .append(sent ? " to CarPlay" : roller == NONE ? " (no roller id set)" : "").toString());
            return sent;
        } catch (Throwable t) {
            return false;
        }
    }

    private static synchronized int rollerId() {
        if (rollerId != UNREAD) {
            return rollerId;
        }
        rollerId = NONE;
        FileInputStream in = null;
        try {
            byte[] b = new byte[16];
            in = new FileInputStream(ID_FILE);
            int n = in.read(b);
            int v = 0, digits = 0;
            for (int i = 0; i < n && b[i] >= '0' && b[i] <= '9' && digits < 9; i++, digits++) {
                v = v * 10 + (b[i] - '0');
            }
            if (digits > 0) {
                rollerId = v;
            }
            WheelZoom.note("roller id: ", String.valueOf(rollerId));
        } catch (Throwable t) {
        } finally {
            if (in != null) {
                try {
                    in.close();
                } catch (Throwable ignored) {
                }
            }
        }
        return rollerId;
    }
}
