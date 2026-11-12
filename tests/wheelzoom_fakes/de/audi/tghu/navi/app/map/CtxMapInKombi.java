package de.audi.tghu.navi.app.map;

class CtxMapInKombi extends CtxShown {
    protected void setZoomIndexOnMap(int n) {
        Calls.LOG.append("kombi:");
        super.setZoomIndexOnMap(n);
    }
}
