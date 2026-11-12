package de.audi.atip.base;

import de.audi.atip.hmi.HMIService;
import de.audi.atip.sysapp.ISysApp;

public interface IFrameworkAccess {
    HMIService getHMIService();

    boolean isVW();

    ISysApp getSysApp();
}
