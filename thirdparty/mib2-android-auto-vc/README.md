# VCAndroidAuto.jar

Release binary v0.1.5-beta2 of
[MacsInSpace/mib2-android-auto-vc](https://github.com/MacsInSpace/mib2-android-auto-vc),
the maintained fork of
[adi961/mib2-android-auto-vc](https://github.com/adi961/mib2-android-auto-vc),
MIT licensed (see `LICENSE` beside this file).

sha256 `6a94f1a3d76e1383a5d85a7c50d8cbed0084842a74d9da4b96e6bde04700f4ae`

It shows Android Auto turn arrows, distance and track information on the
cluster. It cannot be active together with the cluster map, so the package
offers it only as an alternative ("Switch to turn-by-turn arrows").

Changes from adi961's 0.1.4: one jar for VW and SEAT (0.1.4 lost music and
arrows on SEAT), the arrows come back after the car sleeps, and the jar
writes its log to `/tmp/VCAndroidAuto.log`, which green menu "Save logs to
SD" collects.
