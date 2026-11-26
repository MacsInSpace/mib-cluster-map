# Features

What has been asked for, and where each request stands. Before asking for a
feature, find it here; link to its line (each one has its own link) instead
of opening a new request.

- [Available](#available): in a release. Most are off until you switch them on.
- [On the to-do list](#on-the-to-do-list): wanted and planned, no date.
- [Being looked at](#being-looked-at): asked recently, not decided yet.
- [Not possible](#not-possible): the phone or the car doesn't provide it, so
  no change here can add it.
- [Not planned](#not-planned): ~~struck through~~. Outside what this
  project does (the phone's map on the cockpit). If one is picked up later,
  it moves to the to-do list.

Car support is a separate question: see
[Is my car supported?](FAQ.md#supported). Settings are explained on the
[Settings](Settings.md) page.

## Available

| Feature | Cars | How | Issues |
|---|---|---|---|
| <a id="aa-map"></a>Android Auto map on the cockpit | Supported trains | On by itself | |
| <a id="carplay-map"></a>CarPlay map on the cockpit | [CarPlay cars](FAQ.md#carplay-cars) | On by itself where the iPhone library is known | |
| <a id="map-off"></a>Cockpit map off/on without uninstalling | All | Green menu `ClusterMapOptions` > Cluster map OFF / ON, or `GAL_DUALSCREEN_ENABLE=0` | #101 |
| <a id="carplay-off"></a>CarPlay stays stock (for a wireless adapter) | All | `CLUSTERMAP_CARPLAY=0` | #196, #207 |
| <a id="keep-map-on-route"></a>The map stays when a route starts | Most trains by itself | `CLUSTERMAP_ADD_NAVIGNORE=1` elsewhere | [FAQ](FAQ.md#map-goes-on-route) |
| <a id="day-night"></a>Day/night following the headlights, or forced | All (Waze stays dark) | `GAL_SECONDARY_UI_THEME`, green menu `ClusterMapPicture` | #16 |
| <a id="music-vw"></a>Track info on the cockpit's media page | VW, SEAT, Skoda, VW `K3342` | `CLUSTERMAP_MUSIC_INFO=1` | #18, #62 |
| <a id="music-a3"></a>Android Auto cover art and track info | Audi A3 8V `P5089` | `CLUSTERMAP_AU37X_COVER=1` | #195 |
| <a id="turn-info"></a>Android Auto turn arrow, distance and road name in the dials (and on a factory HUD) | VW, SEAT, Skoda | `CLUSTERMAP_TURN_INFO=1` | #119, discussion #197 |
| <a id="arrows-only"></a>Turn arrows only, without the map | Trains where the arrows jar fits | Green menu: switch to turn-by-turn arrows | #3 |
| <a id="sharper-map"></a>Sharper map (whole frame, 720p, 1080p) | Larger cockpits | `CLUSTERMAP_FULL_FRAME`, `CLUSTERMAP_720P`, `CLUSTERMAP_1080P` | [FAQ](FAQ.md#hd-decoder) |
| <a id="hw-decoder"></a>Hardware video decoder | On by itself on `P4521`, `K4525`, A3 8V; others after the check | Green menu `ClusterMapOptions` | #125 |
| <a id="carplay-scale"></a>Smaller CarPlay text, more map | CarPlay cars | `CLUSTERMAP_CARPLAY_SCALE=130` | #146, discussion #193 |
| <a id="carplay-zoom"></a>Steering-wheel zoom of the CarPlay map | Audi A6/A7 C7.5 `K3663`, `K1006_2`; trial on `K3341` | On by itself; `CLUSTERMAP_CARPLAY_WHEEL_ZOOM=1` on `K3341` | #156, #171 |
| <a id="view-insets"></a>Different insets per cockpit view | Cars with several views (A3 8V, SEAT large dials) | `GAL_SECONDARY_LARGE_INSETS`, `_SPORT_INSETS`, green menu `ClusterMapSupport` 7-9 | #183, #211 |
| <a id="primary-dpi"></a>Centre-screen size for Android Auto | All | `GAL_PRIMARY_DPI` | #71 |

## On the to-do list

| Feature | Cars | Notes | Issues |
|---|---|---|---|
| <a id="todo-audi-music"></a>Android Auto track info on the Audi cockpit | Audi | Next for the music add-on | #182 |
| <a id="todo-map-switch"></a>Switch between the phone's map and the car's map without the green menu (steering wheel or car menu) | All | The buttons differ per car; the green-menu switch came first | #183, #23, discussion #153, discussion #166 |
| <a id="todo-follow-view"></a>Follow the cockpit's own view button for the per-view insets | Cars with several views | Being worked out per car | #183, #205 |
| <a id="todo-k3342-carplay-track"></a>CarPlay track info that refreshes by itself | VW `K3342` | The title changes only when you go back into the media page | #62 |
| <a id="todo-k3342-music"></a>Android Auto track title with the turn-info build | VW `K3342` | Cover shows, title missing on one car | #65 |
| <a id="todo-carplay-hud"></a>CarPlay turn arrows on the factory HUD and in the dials | VW, Audi | Leads in PR #180 | #179 |
| <a id="todo-carplay-cover"></a>CarPlay cover art on the cockpit | All | The car's CarPlay service passes on title, artist and album only | #19, #162 |

## Being looked at

Asked recently; the answer is in the issue when there is one.

| Request | Issues |
|---|---|
| <a id="look-aa-audi-hud"></a>Android Auto turn arrows on the Audi A6/A7 factory HUD and cluster | #215 |
| <a id="look-waze-roundabout"></a>Waze roundabouts shown as a U-turn on the VW HUD | #216 |
| <a id="look-roundabout-no-map"></a>Wrong roundabout arrows on a cockpit without map view (Google Maps) | discussion #221 |
| <a id="look-svm"></a>"Fix SVM" (clear the software-version fault) in the green menu | #214 |
| <a id="look-roller-presets"></a>Steering-wheel roller to step through map presets | #205 |
| <a id="look-touchpad"></a>MMI touchpad as a cursor in Google Maps | #107 |

## Not possible

The cockpit shows the picture the phone draws for a second screen. These
depend on the phone, the app or the car, not on this project.

| Request | Why | Issues |
|---|---|---|
| <a id="np-speed-limit"></a>Speed limit from Google Maps or Waze | Android Auto doesn't send it to the car. The cockpit's own sign comes from the car's camera (VCDS coding) | #32, #132, #159 |
| <a id="np-alerts"></a>Speed cameras, police, hazards, traffic bubbles | The apps leave them out of the cockpit picture | #57, #98, #133, discussion #199, discussion #202 |
| <a id="np-waze-day"></a>Waze in day colours on the cockpit | Waze always draws it dark (reported to Waze) | #129, #20, discussion #199 |
| <a id="np-aa-zoom"></a>Zooming the Android Auto map | Android Auto has no zoom for the cockpit map | #63, #96, #116, #136 |
| <a id="np-layers"></a>Satellite view, Google Maps' arrival time, Waze's second manoeuvre on the cockpit | The app chooses what the cockpit picture contains | #63, #154, #175, discussion #202 |
| <a id="np-turn-card"></a>Hiding the app's own turn card on the map | Drawn by the app | #219 |
| <a id="np-other-apps"></a>A map from Yanosik, Mapy.com, 2GIS, Yandex Navi | These apps send only their icon | #120, #167, #185 |
| <a id="np-two-apps"></a>One app on the cockpit and another on the centre screen | Android Auto gives the cockpit to the navigation app in front | #107, #116 |
| <a id="np-carplay-home"></a>CarPlay or Android Auto home screen or video on the cockpit | Only the map picture is sent there | discussion #135, #76 |
| <a id="np-street-label"></a>Hiding the Audi cockpit's own street-name label | Drawn by the cockpit over the map window; no way found so far | #126, #178 |
| <a id="np-left-dial"></a>Choosing what the left dial shows (song, arrival time) | Chosen by the cockpit's own menu | #45, #44 |
| <a id="np-lvds-box"></a>The map with an LVDS CarPlay box (AUTOABC) or a Carlinkit T-box | The head unit has no phone session | #55, discussion #172 |

## Not planned

| Request | Notes | Issues |
|---|---|---|
| <a id="no-data-bar"></a>~~Speed, oil temperature or other car data drawn over the map~~ | | #187 |
| <a id="no-rear-camera"></a>~~Rear camera or drive modes on the cockpit~~ | The camera is a hardware video layer on the centre screen | #147 |
| <a id="no-car-model"></a>~~3D car model, cockpit colours, other Audi coding~~ | See [Toprr's database](https://github.com/Toprr/audi-a6-a7-c7-mib2-high-diy-info-database-carplay-cockpit-overlay-vehicle-data-3d-car-model-kzb-mods) | #210 |
| <a id="no-guidance-extras"></a>~~Arrival time, remaining distance and lanes in the car's own guidance~~ | Needs a guidance jar per firmware; maybe later | #119 |
| <a id="no-analogue-arrows"></a>~~CarPlay arrows on the small display between analogue dials~~ | No map window there; see chrzanowy/mhi2-aid-carplay | #46 |
| <a id="no-overview"></a>~~Centre screen leaving route overview when the cockpit leaves map view~~ | Reopens with a Save logs from a current release | #48 |
| <a id="no-other-platforms"></a>~~MIB2 Standard, Delphi, TechniSat, MIB3, MH2P~~ | Different platforms; see [the FAQ](FAQ.md#other-units) | #87, #88, #117, #138 |
| <a id="no-tt"></a>~~Audi TT 8S `P5098`~~ | No map window to replace; Tristar10's audi-tt-8s-altscreen covers the US TT | #99 |
| <a id="no-video"></a>~~Video on the driver's display~~ | | #76, #103 |
