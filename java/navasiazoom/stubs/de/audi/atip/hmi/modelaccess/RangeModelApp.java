package de.audi.atip.hmi.modelaccess;

import de.audi.atip.hmi.model.RangeListener;

public interface RangeModelApp extends ButtonModelApp {
    void setMedialPosition(int p);

    void setRangeListener(RangeListener l);

    void setValue(int v);

    int getValue();
}
