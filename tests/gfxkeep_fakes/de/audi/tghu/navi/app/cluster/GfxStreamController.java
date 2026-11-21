package de.audi.tghu.navi.app.cluster;

import de.audi.tghu.navi.app.Calls;

public class GfxStreamController {
    private int current = 3;
    private static final String[] NAMES = {"WAITING", "RGI", "MAP", "KDK", "COMPASS"};

    public void switchViewMode(int n) {
        current = n;
        Calls.LOG.append("switch(").append(n).append(") ");
    }

    public final String printGfxStreamStatus() {
        return "\n---GfxStreamStatus---\ngfxAvailable = true\ncurrentViewMode = " + NAMES[current] + "\n";
    }
}
