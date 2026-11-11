package de.audi.tghu.navi.app.map;

/* Stand-in with the stock access: the class and these methods package-private
 * or protected, as in lsd.jxe. */
class CtxShown {
    int requested;
    final MVRequestControl control = new MVRequestControl();

    float[] getZoomList() {
        return new float[] {10, 25, 50, 100, 200};
    }

    int getRequestedZoomListIndex() {
        return requested;
    }

    MVRequestControl getMVRequestControl() {
        return control;
    }

    protected void setMagnificationDisplay(int n) {
        Calls.LOG.append("setMagnificationDisplay(").append(n).append(") ");
    }

    protected void setZoomIndexOnMap(int n) {
        Calls.LOG.append("setZoomIndexOnMap(").append(n).append(") ");
        requested = n;
    }
}
