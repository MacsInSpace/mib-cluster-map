package de.audi.atip.hmi.model;

public interface ListListener {
    void itemReleased(int a, int b, int c, int d);

    void itemSelected(int a, int b, int c, int d);

    void itemFocused(int a, int b, int c, int d);
}
