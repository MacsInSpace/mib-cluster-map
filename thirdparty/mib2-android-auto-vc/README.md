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

## VCAndroidAutoMusic.jar

The music-only build of the same fork (branch `feature/music-only`, commit
`a2413b8`, `make music`), sha256 `685199faa928255ec6a880b1ff89ab4a08a72ea69543c1f628fde1a54549807a`. It shows the
track playing (title, artist, cover) on the cockpit's media screen and
nothing else. With CarPlay it shows title, artist and album: the stock
CarPlay code never asks for them, so the jar subscribes to the iPhone's
now-playing data itself (listen only, nothing is sent to the phone). It leaves out the navigation overrides and never changes the
navigation focus, so the phone's map stays on the cockpit when a route
starts. Installed beside the map with `CLUSTERMAP_MUSIC_INFO=1`; never
together with VCAndroidAuto.jar, which carries the same classes. Not yet
car-tested.

## VCAndroidAutoTurns.jar

The full jar with the cockpit view left alone (branch `feature/turns-with-map`,
commit `c953676`, `make turns`), sha256 `5456cb688496dd2b0b10229f61fa370c6bcb1f984709552014af0942af23a754`.
It differs from a full build of the same commit in two classes only: Variant
and ActiveRgType. The full jar answers ActiveRgType with 0, the cockpit's
arrow view, whenever Android Auto guides, and on VW that view replaces the
phone's map. This build lets the stock logic answer instead (the map while
the cockpit shows one, otherwise the driver's own choice), while the turn
data still goes out. It also carries the track info of
VCAndroidAutoMusic.jar. Installed with `CLUSTERMAP_TURN_INFO=1`; never
together with the other two jars. Not yet car-tested.
