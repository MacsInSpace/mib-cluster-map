package de.audi.tghu.navi.app.map;

/* Stand-in for the cockpit map's magnification (RangeModel -240844800):
 * package-private, as in lsd.jxe. The test sets value. */
public class GUIInterface {
    public static int value = 4;
    public static final int MIN = 0, MAX = 4;

    int getKombiMagnificationValue() {
        return value;
    }

    int getKombiMagnificationMinimum() {
        return MIN;
    }

    int getKombiMagnificationMaximum() {
        return MAX;
    }

    void setKombiMagnification(int n) {
        Calls.LOG.append("setKombiMagnification(").append(n).append(") ");
        value = n;
    }
}
