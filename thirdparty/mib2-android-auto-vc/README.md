# VCAndroidAuto.jar

Release binary v0.1.5-beta4 of
[MacsInSpace/mib2-android-auto-vc](https://github.com/MacsInSpace/mib2-android-auto-vc),
the maintained fork of
[adi961/mib2-android-auto-vc](https://github.com/adi961/mib2-android-auto-vc),
MIT licensed (see `LICENSE` beside this file).

Built from fork commit `cfa9389`, sha256
`397b52f266c4e99031a7220ad5c68ea482b19b90664c62ef83d95d2c3f976253`

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

The music-only build of the same fork (commit `cfa9389`, `make music`),
sha256 `28d304ec024b9ab8f758a2db65c98d59271c378a0761f81a98ecb5f8a88e5427`. It shows the
track playing (title, artist, cover) on the cockpit's media screen and
nothing else. With CarPlay it shows title, artist and album: the stock
CarPlay code never asks for them, so the jar subscribes to the iPhone's
now-playing data itself (listen only, nothing is sent to the phone). It leaves out the navigation overrides and never changes the
navigation focus, so the phone's map stays on the cockpit when a route
starts. Installed beside the map with `CLUSTERMAP_MUSIC_INFO=1`; never
together with VCAndroidAuto.jar, which carries the same classes. Android Auto track info
car-tested on the Golf as part of VCAndroidAutoTurns.jar; CarPlay track info
not yet car-tested.

## VCAndroidAutoMusic_K3342.jar

The music-only build for K3342 (`MHI2_ER_VWG11_K3342`), from the fork's
commit `cfa9389` (`make music-k3342`), sha256
`9e85f6f8246d1e4afeb4b6e6f2c6434c43f3b483ce36b49a48a2d86f77b4c053`.
K3342's stock Java is older than the Golf's: no ExBox guidance, no Baidu
CarLife, two station-info fields renamed, and a different smartphone
property id. `variants/k3342.sh` adapts the music sources and the jar is
compiled against K3342's own lsd.jxe (#62), where every stock class, method
and field it uses was found. The installer copies it as
`VCAndroidAutoMusic.jar` on trains marked `infok3342` in profiles.conf.
Not yet car-tested.

## VCAndroidAutoTurns_K3342.jar

The turn-info build for K3342 (fork commit `cfa9389`, `make turns-k3342`),
sha256 `508b9aa7144e50f9a88b12a60d155b6da0d66bb59e62763c76ba64b4859d6f3f`.
The music sources get the same K3342 changes as above; of the six cockpit
classes, four are the same on K3342 as on the Golf, and `variants/k3342.sh`
adapts the other two: K3342's guiding-flag property (1920216832) in RGStatus
and InfoStates, no CarLife listener, and no stage-53 setup acknowledgement in
ActiveRgType (K3342's own class has none). Compiled against K3342's lsd.jxe.
The installer copies it as `VCAndroidAutoTurns.jar` with
`CLUSTERMAP_TURN_INFO=1` on trains marked `infok3342`. Not yet car-tested.

## VCAndroidAutoTurns.jar

The full jar with the cockpit view left alone (commit `cfa9389`,
`make turns`), sha256 `aca59bf09647fcb593110f79731e1bf95ca384875c76aa9138fe6fb50a6ca796`.
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

From `32f4756` (full and turns builds) the arrow on a roundabout points the
right way in left-hand traffic (UK, Ireland, Australia): Android measures the
exit angle in the direction of travel, and clockwise roundabouts had left and
right swapped (#24). Anticlockwise roundabouts are unchanged. Not yet
car-tested.

From `b7af41d` the log (with the MIBLogger file set to DEBUG) also records
each maneuver sent to the cockpit: `maneuver: ...` with its main element and
direction.

Until v1.2.7 an install never replaced a turns, music or arrows jar that was
already loaded, so cars kept the copy from their first install (the owner's
Golf still ran a 6 November build). From v1.2.7 the installer replaces it
when the card's build differs.

From `bf6464a` (all builds) a new turn from the phone more than 3 s after it
handed the navigation back counts as the phone guiding again: on #160's car
the next route brought no new focus request, so turn info stayed off until the
phone reconnected. Not yet car-tested.
