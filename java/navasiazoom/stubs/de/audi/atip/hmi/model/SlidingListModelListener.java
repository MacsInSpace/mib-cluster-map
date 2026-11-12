package de.audi.atip.hmi.model;

public interface SlidingListModelListener extends AbstractListModelListener {
    void requestRowsAfter(int a, ListRow b, int c, int d);

    void requestRowsBefore(int a, ListRow b, int c, int d);
}
