package de.audi.atip.hmi.modelaccess;

import de.audi.atip.hmi.model.ChoiceListener;

public interface ChoiceModelApp extends ButtonModelApp {
    void setChoiceListener(ChoiceListener l);

    void setValue(int v);

    int getValue();

    void forceUpdate(boolean b);
}
