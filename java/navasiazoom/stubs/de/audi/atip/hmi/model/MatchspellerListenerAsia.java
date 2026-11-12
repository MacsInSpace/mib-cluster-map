package de.audi.atip.hmi.model;

public interface MatchspellerListenerAsia extends MatchSpellerListener {
    void nonAlphaNumTPCharsChanged(int a, int b, String c);

    void inputModeTPChanged(int a, int b, int c);

    void getValidHanziCharsWindow(int a, int b, int c, int d);

    void addSpellerStroke(int a, String b, String c, int d);
}
