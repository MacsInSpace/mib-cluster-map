package de.audi.atip.sysapp;

import de.audi.atip.hmi.modelaccess.ButtonModelApp;
import de.audi.atip.hmi.modelaccess.ChoiceModelApp;

public interface ISysApp {
    ChoiceModelApp getChoiceModelApp(int id);

    ButtonModelApp getButtonModelApp(int id);
}
