# VCAndroidAuto.jar

Release binary v0.1.5-beta4 of
[MacsInSpace/mib2-android-auto-vc](https://github.com/MacsInSpace/mib2-android-auto-vc),
the maintained fork of
[adi961/mib2-android-auto-vc](https://github.com/adi961/mib2-android-auto-vc),
MIT licensed (see `LICENSE` beside this file).

sha256 `3f407362b2e639df615e0070d3fe7de93175179c4da80a857afb4ec20579e435`

It shows Android Auto turn arrows, distance and track information on the
cluster. It cannot be active together with the cluster map, so the package
offers it only as an alternative ("Switch to turn-by-turn arrows").

Changes from adi961's 0.1.4: one jar for VW and SEAT (0.1.4 lost music and
arrows on SEAT), the arrows come back after the car sleeps, and the jar
writes its log to `/tmp/VCAndroidAuto.log`, which green menu "Save logs to
SD" collects, and it tells the cluster when the turn pictogram changes, which
0.1.4 did not. For a fuller log, put a file named `MIBLogger` containing
`DEBUG` in the top folder of the SD card.
