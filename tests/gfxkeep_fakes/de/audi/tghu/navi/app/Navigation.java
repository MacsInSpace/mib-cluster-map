package de.audi.tghu.navi.app;

import de.audi.atip.base.IFrameworkAccess;
import de.audi.atip.hmi.modelaccess.ChoiceModelApp;
import de.audi.atip.sysapp.ISysApp;
import de.audi.tghu.navi.app.cluster.ClusterService;
import de.audi.tghu.navi.app.cluster.GfxStreamController;

public final class Navigation {
    private static final Navigation INSTANCE = new Navigation();
    private final GfxStreamController gfx = new GfxStreamController();
    private final ClusterService cluster = new ClusterService();

    public static Navigation getInstance() {
        return INSTANCE;
    }

    /* Anonymous (non-public) implementations, as the unit's framework: the
     * jar must call them through the public interfaces. */
    public static IFrameworkAccess getFramework() {
        return new IFrameworkAccess() {
            public ISysApp getSysApp() {
                return new ISysApp() {
                    public ChoiceModelApp getChoiceModelApp(int id) {
                        if (id != 51) {
                            throw new IllegalArgumentException("model " + id);
                        }
                        return new ChoiceModelApp() {
                            public void setValue(int v) {
                                Calls.view = v;
                                Calls.LOG.append("set(").append(v).append(") ");
                            }

                            public int getValue() {
                                return Calls.view;
                            }
                        };
                    }
                };
            }
        };
    }

    public GfxStreamController getGfxStreamController() {
        return gfx;
    }

    public ClusterService getClusterService() {
        return cluster;
    }
}
