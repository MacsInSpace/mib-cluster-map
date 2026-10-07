# Cluster map zoom: what was tried and why it is not implemented

Local field notes, not from upstream. VW Golf 7.5, `MHI2_ER_VWG13_P4521`
(MU1367), Google Maps via Android Auto on a Pixel, October 2026.

## Conclusion

No input was found that makes Android Auto zoom the map it draws for the
cluster. Zoom is therefore not implemented. The cluster map zooms by itself as
Google Maps decides (speed and distance to the next turn).

## What the cluster offers

In map view the VW cluster shows "zoom with up/down, OK to reset". Those
presses go from the cluster to the head unit, which normally redraws its own
map at a new scale. With the phone's video on the cluster, nothing redraws, so
the presses have no visible effect. They are not passed to the phone.

## Experiments

A test harness in the hook (`GAL_INPUT_INJECT=1`, requests written to
`/tmp/gal_inject`, script `scripts/experiments/zoom_test.sh`) sent input
reports to the phone. Field numbers for the report were read from the unit's
own `libautoreceiver.so`.

| Input sent | Channel | Result |
|---|---|---|
| Rotary controller (65536), +1 and -1 | cluster input | no reaction |
| Rotary +1 with display id 1 in the report | cluster input | no reaction |
| DPAD centre (23) | cluster input | no reaction |
| DPAD up (19), down (20) | cluster input | no reaction (not in the bound key list) |
| Zoom in (168), zoom out (169) | cluster input | no reaction (not in the bound key list) |
| Rotary +1 and -1 | main input | a focus highlight moves across the **centre** screen |
| Rotary +1 with display id 1 | main input | same as above; the display id is ignored |
| Pinch zoom by hand on the centre-screen map | touch | centre map zooms, cluster map does not follow |

Run both with and without an active route. The session stayed healthy
throughout.

## What was learned about the input services

- The phone sends a KeyBindingRequest (`0x8002`) on the cluster input channel
  listing exactly the keycodes the head unit advertised for the cluster:
  `80 02 0a 04 17 80 80 04`, that is 23 and 65536. Upstream left this
  unanswered. The hook now replies `80 03 08 00` (status 0). Answering it did
  not make the cluster react to input, and did no harm.
- On the main input channel the phone binds keycodes 1 to 6, 19 to 23, 84, 85,
  87, 88, 126, 127 and 65536 to 65540.
- The advertised cluster key list is limited to 5 bytes of packed values by
  the 15-byte inline string it is injected into (`GAL_CLUSTER_KEYCODES`).
- The main and cluster maps are independent views. Zooming one does not move
  the other.

## Consistent with other sources

- `kamgurgul/mib2q-carplay` reached the same result on Audi units: "Android
  Auto has no zoom command for the cluster display and ignores rotary input
  there."
- Google's Android for Cars documentation describes cluster displays as
  non-interactive.
- The upstream author of this project states that an unpublished jar,
  `VCAndroidAuto_mapmode.jar`, zooms the cluster map from the steering wheel.
  How it does so is not documented and could not be reproduced here.

## Not verified

One observation from the car was not pinned down: a zoom level indicator drawn
inside Google Maps appeared to change during testing while the map itself did
not. It was not established which screen or which input this referred to.

## If someone wants to continue

1. Ask the upstream author how the mapmode jar delivers zoom.
2. Try other advertised key sets with `GAL_CLUSTER_KEYCODES` and the harness.
   Only keys the phone binds can have any effect; check the
   `event=cluster.input.binding` log line.
3. A purely local alternative, deliberately not built: crop and enlarge the
   picture in `stream-player`. It magnifies the existing image, so it shows
   less area with softer labels and cannot zoom out. It would also need a Java
   patch to catch the steering-wheel presses.
