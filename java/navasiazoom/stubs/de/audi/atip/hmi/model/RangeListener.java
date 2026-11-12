package de.audi.atip.hmi.model;

public interface RangeListener extends ButtonListener {
    void decrement(int a, int b, int c);

    void increment(int a, int b, int c);
}
