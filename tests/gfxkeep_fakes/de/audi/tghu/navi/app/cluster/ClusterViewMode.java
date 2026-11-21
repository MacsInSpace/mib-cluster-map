package de.audi.tghu.navi.app.cluster;

import de.audi.tghu.navi.app.Calls;

public class ClusterViewMode {
    public final int getNewValidViewMode() {
        int v = Calls.view;
        return v == 4 && Calls.routeActive ? 3 : v;
    }
}
