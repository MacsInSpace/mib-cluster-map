package de.audi.atip.hmi.modelaccess;

import de.audi.atip.hmi.model.HMIModel;
import de.audi.atip.hmi.model.MatchSpellerListener;

public interface MatchspellerModelAsiaApp extends HMIModel {
    void setMaxLength(int n);

    void setSpellerListener(MatchSpellerListener l);

    void setStatus(int s);
}
