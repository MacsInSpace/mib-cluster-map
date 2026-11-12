# harman-f/mhi2_altscreen_carplay: CarPlay cluster-stream hook

Unmodified copy of `src/native/altscreen111-gen2/` from
https://github.com/harman-f/mhi2_altscreen_carplay at commit `47b1dcc30d25c01bd32b7f35a03380803aeea64e`
(GPL-3.0, see LICENSE). `build_local.sh` builds it, together with
`carplay/carplay_launcher.c`, into `libcarplay_cluster.so`.

It is preloaded into `dio_manager` and targets the CarPlay library
`libairplay.so` with SHA-256
`193a4fd9101ec2aa05e7159cfa307b96500810d379ca74a194f172adc13a46b5`
(Skoda MU1440; byte-identical on VW MU1367). It checks the stock function
prologues before hooking and leaves CarPlay stock on a mismatch.

This is harman-f's development source, which is newer than their
vehicle-tested binary of 2026-09-27 (SHA-256 `094e3f1a…`); the source of
that exact binary is not published.

This project uses only its cluster-stream output (H.264 on 127.0.0.1:19820),
not harman-f's direct MOST bridge. To update: copy the directory again and
change the commit above.

## Local changes

All marked `mib-cluster-map` in `libaltscreen111_gen2.c`:

- The car's day/night reaches the cluster: `AirPlayReceiverSessionSetNightMode`
  is interposed and the value repeated with the cluster's uuid, as
  luka-dev/mib2q-carplay-rgi (GPL-3.0) does. This replaces beta14's removal of
  the cluster's `nightMode`, which did not change the picture on a car (#10).
- With the navigation query on and no manoeuvre layout set, the URL leaves
  `maneuverLayout` out instead of sending it empty.
- `ALTSCREEN111_ZOOM_FACTOR` (installer: `CLUSTERMAP_CARPLAY_ZOOM`), off by
  default: adds `zoomFactor` to the cluster display, as the SEAT MU1409 port
  by RandomGenerated543/seat-cupra-mu1409-carplay (GPL-3.0) does.
- Steering-wheel zoom (`gen2_process_wheel_zoom`): roller steps from the HMI
  (`ClusterMapWheelZoom.jar`, loopback UDP 19822, `MZ01` and a signed count)
  become `changeMapZoomLevel` commands for the cluster display while the
  stream is up, as aberbic/Audi-MHI2-Virtual-Cockpit-Altscreen-CarPlay-AndroidAuto
  (GPL-3.0) does on MU1438. See docs/CarPlay.md.
- Hide the iPhone's route from the car (`modes_without_phone_route`, marker
  file `carplay_hide_nav`, installer: `CLUSTERMAP_CARPLAY_HIDE_NAV=1`), off by
  default: the stock library gets a copy of `modesChanged` in which nobody
  owns turn-by-turn, so the cockpit is not switched away from the map when a
  route starts (#10). Written for mib-cluster-map; not car-tested.
