package de.audi.atip.timer;

public class Timer {
    /* As the stock Timer: a delay of 0 or less is refused (setDelay). */
    public Timer(String name, long delay, boolean once, TimerListener listener) {
        if (name == null || listener == null || delay <= 0L) {
            throw new IllegalArgumentException();
        }
    }

    public boolean cancel() {
        return true;
    }
}
