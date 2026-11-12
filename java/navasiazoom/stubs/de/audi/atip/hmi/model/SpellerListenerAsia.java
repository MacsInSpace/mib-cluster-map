package de.audi.atip.hmi.model;

public interface SpellerListenerAsia extends SpellerListener {
    void textChanged(int a, String b, String c, int d);

    void textChanged(int a, String b, String c, char d, int e);
}
