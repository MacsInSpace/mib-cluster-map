package de.audi.atip.hmi.modelaccess;

import de.audi.atip.hmi.model.ButtonListener;
import de.audi.atip.hmi.model.HMIModel;

public interface ButtonModelApp extends HMIModel {
    void setButtonListener(ButtonListener l);

    void setPressed(boolean b);

    boolean getPressed();

    void setStatus(int s);
}
