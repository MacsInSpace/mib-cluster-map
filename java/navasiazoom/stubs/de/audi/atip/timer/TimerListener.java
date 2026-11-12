package de.audi.atip.timer;

public interface TimerListener {
    void fireTimer(Timer timer);

    void cancelTimer(Timer timer);
}
