package de.audi.atip.hmi.modelaccess;

import de.audi.atip.hmi.model.HMIModel;
import de.audi.atip.hmi.model.ListCell;
import de.audi.atip.hmi.model.ListListener;

public interface ListModelApp extends HMIModel {
    ListCell getCell(int row, int column);

    void setListListener(ListListener l);

    void setMaxColumns(int n);

    void setMaxRows(int n);

    void addHint(int h);
}
