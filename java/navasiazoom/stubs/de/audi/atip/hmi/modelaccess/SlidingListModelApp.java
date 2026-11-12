package de.audi.atip.hmi.modelaccess;

import de.audi.atip.hmi.model.HMIModel;
import de.audi.atip.hmi.model.SlidingListModelListener;

public interface SlidingListModelApp extends HMIModel {
    void setListListener(SlidingListModelListener l);
}
