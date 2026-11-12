package de.audi.atip.hmi.model;

public interface TooltipListener {
    void tooltipDataRequested(int a, int b, int c, boolean d, int e);

    void tooltipDataRequested(int a, int b, ListRow c, boolean d, int e);

    void tooltipVisible(int a, int b, int c);

    void tooltipHidden(int a, int b, int c);
}
