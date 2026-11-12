package de.audi.atip.log;

public abstract class LogChannel {
    public final boolean log(int level, int msg) {
        return false;
    }

    public final boolean log(int level, int msg, long a) {
        return false;
    }
}
