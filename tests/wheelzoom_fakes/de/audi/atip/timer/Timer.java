package de.audi.atip.timer;

public class Timer {
    /* As the stock Timer: a delay of 0 or less is refused (setDelay). */
    public Timer(String name, long delay, boolean once, TimerListener listener) {
        if (name == null || listener == null || delay <= 0L) {
            throw new IllegalArgumentException();
        }
    }

    /* As the stock Timer: queues it; the test fires it by hand. */
    public void start() {
    }

    public boolean cancel() {
        return true;
    }
}
