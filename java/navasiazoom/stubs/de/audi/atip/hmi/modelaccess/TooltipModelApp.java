package de.audi.atip.hmi.modelaccess;

import de.audi.atip.hmi.model.HMIModel;
import de.audi.atip.hmi.model.TooltipListener;

public interface TooltipModelApp extends HMIModel {
    void setListener(TooltipListener l);
}
