package de.audi.atip.hmi.model;

public interface ButtonListener {
    void keyPressed(int a, int b, int c);

    void keyReleased(int a, int b, int c);

    void keyTyped(int a, int b, int c);
}
