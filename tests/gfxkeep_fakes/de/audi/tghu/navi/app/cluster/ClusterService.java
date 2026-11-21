package de.audi.tghu.navi.app.cluster;

public final class ClusterService {
    private final ClusterViewMode viewMode = new ClusterViewMode();

    public ClusterViewMode getClusterViewMode() {
        return viewMode;
    }
}
