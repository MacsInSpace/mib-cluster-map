# VCAndroidAuto.jar

Release binary v0.1.5-beta1 of
[MacsInSpace/mib2-android-auto-vc](https://github.com/MacsInSpace/mib2-android-auto-vc),
the maintained fork of
[adi961/mib2-android-auto-vc](https://github.com/adi961/mib2-android-auto-vc),
MIT licensed (see `LICENSE` beside this file).

sha256 `23362aba59e27e7f71dfa2956d5b8db4309dd3386bfc6e2c2c5c90d3ed9bf45a`

It shows Android Auto turn arrows, distance and track information on the
cluster. It cannot be active together with the cluster map, so the package
offers it only as an alternative ("Switch to turn-by-turn arrows").

Changes from adi961's 0.1.4: the arrows come back after the car sleeps, and
the jar writes its log to `/tmp/VCAndroidAuto.log`, which green menu
"Save logs to SD" collects.
