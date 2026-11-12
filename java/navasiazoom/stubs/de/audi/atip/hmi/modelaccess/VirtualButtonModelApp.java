package de.audi.atip.hmi.modelaccess;

import de.audi.atip.hmi.model.VirtualButtonListener;

public interface VirtualButtonModelApp extends RangeModelApp {
    void setVirtualButtonListener(VirtualButtonListener l);
}
