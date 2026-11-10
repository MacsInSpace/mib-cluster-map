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

The music-only build of the same fork (commit `610b15d`, `make music`),
sha256 `a1c0443943e29aa808db6fbfbbbb67333ad951d538003a4d195454e006956227`. It shows the
track playing (title, artist, cover) on the cockpit's media screen and
nothing else. With CarPlay it shows title, artist and album: the stock
CarPlay code never asks for them, so the jar subscribes to the iPhone's
now-playing data itself (listen only, nothing is sent to the phone). It leaves out the navigation overrides and never changes the
navigation focus, so the phone's map stays on the cockpit when a route
starts. Installed beside the map with `CLUSTERMAP_MUSIC_INFO=1`; never
together with VCAndroidAuto.jar, which carries the same classes. Android Auto track info
car-tested on the Golf as part of VCAndroidAutoTurns.jar; CarPlay track info
not yet car-tested.

## VCAndroidAutoTurns.jar

The full jar with the cockpit view left alone (commit `610b15d`,
`make turns`), sha256 `bec87512880fb4621613429c516e460d9a67c85530a33df707d02229146c7d6b`.
It differs from a full build of the same commit in two classes only: Variant
and ActiveRgType. The full jar answers ActiveRgType with 0, the cockpit's
arrow view, whenever Android Auto guides, and on VW that view replaces the
phone's map. This build lets the stock logic answer instead (the map while
the cockpit shows one, otherwise the driver's own choice), while the turn
data still goes out. It also carries the track info of
VCAndroidAutoMusic.jar. Installed with `CLUSTERMAP_TURN_INFO=1`; never
together with the other two jars. Car-tested on a Golf R (P4521) at commit
`c953676`: the phone's map stayed on the cockpit, with the road name above it
and the turn arrow in the right dial; the media screen showed the track and
cover.

From `016d3ff` both builds also clear the cockpit's turn pictogram when the
phone ends its route; at `c953676` the last arrow stayed on screen after the
route ended. That fix is not yet car-tested.

From `971407a` the turns build sends the road name ("towards ...") only while
the cockpit is not showing the map, where Google Maps' card already has it
(`CLUSTERMAP_TURN_TEXT`: auto, always, never). Not yet car-tested.

The clear from `016d3ff` never reached the cockpit: the stock code turns
Android Auto's guiding flag off first, and from then on the cockpit's arrow
function ignores the jar's data (#70). From `72b7c0e` the jar clears the arrow,
distance and road name before the flag goes off, and with no route the arrow
is always sent empty. Not yet car-tested.

The `72b7c0e` clear ran in #70's log, yet the arrow stayed: RG_Status (the
cockpit's "route active") was only sent again on a change in the car's own
navigation, never when Android Auto's guiding flag went off. From `62691dc` it
follows that flag too and logs each change (`RG_Status 0 (phone guiding:
false, ...)`). Not yet car-tested.

From `58e2329` (both builds) the cockpit also gets the iPhone's album cover
with CarPlay, when the media service has no cover of its own. Listen only, as
before. Not yet car-tested.
