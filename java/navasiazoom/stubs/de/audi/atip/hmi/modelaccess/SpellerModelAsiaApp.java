package de.audi.atip.hmi.modelaccess;

import de.audi.atip.hmi.model.HMIModel;
import de.audi.atip.hmi.model.SpellerListener;

public interface SpellerModelAsiaApp extends HMIModel {
    void setSpellerListener(SpellerListener l);
}
