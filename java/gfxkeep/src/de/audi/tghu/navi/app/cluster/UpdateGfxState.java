package de.audi.tghu.navi.app.cluster;

import de.audi.tghu.navi.app.eventbus.IEvent;

/**
 * mib-cluster-map replacement of the stock event class (AU57x, K3663 lsd.jxe
 * 44688282 bytes): same name, same members. It is created for every cockpit
 * graphics report (DSIKOMOHandler.updateGfxState publishes it,
 * GfxStreamController reads getGfxState()), the first time about 20 s after
 * start-up, which is where local.clustermap.GfxKeep starts its cockpit map
 * view watcher. The state goes through GfxKeep.filter, which passes it on
 * unchanged except for a 0 while the CarPlay map is being swapped.
 */
public class UpdateGfxState implements IEvent {
    private final int gfxState;

    public UpdateGfxState(int n) {
        this.gfxState = local.clustermap.GfxKeep.filter(n);
    }

    public int getGfxState() {
        return this.gfxState;
    }
}
