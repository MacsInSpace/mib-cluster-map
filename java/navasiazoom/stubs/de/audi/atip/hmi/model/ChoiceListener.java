package de.audi.atip.hmi.model;

public interface ChoiceListener extends ButtonListener {
    void itemSelected(int a, int b, int c, int d);
}
