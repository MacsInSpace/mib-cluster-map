package de.audi.atip.hmi.model;

public interface VirtualButtonListener extends RangeListener {
    void touchPadPositionMoved(int a, int b, int c, int d, int e, int f);

    void stickN(int a, int b);

    void stickNW(int a, int b);

    void stickW(int a, int b);

    void stickSW(int a, int b);

    void stickS(int a, int b);

    void stickSE(int a, int b);

    void stickE(int a, int b);

    void stickNE(int a, int b);

    void stickIdle(int a, int b);
}
