# Settings

**Most owners never change anything.** The installer recognises your car and
uses the values other owners of the same car have already tested. This page
is for when something on your cockpit isn't quite right.

## Why there are settings at all

One installer covers VW, SEAT, Skoda and Audi head units, and the cars it
draws into are not alike:

- **The cockpit windows differ.** The map window is 800×480 on most VW
  cockpits, 1010×376 on SEAT, Skoda and some VWs, 1440×455 on the Audi A3, A4,
  Q2 and Q5, and 800×298 on the A6/A7. Different dials sit around it.
- **The phones decide how they draw.** Android Auto and CarPlay choose their
  text size, cards and layout from what the car tells them about the screen.
  Those numbers have to be tuned per cockpit, by eye, on the road.
- **Waze and Google Maps behave differently**, and so do iPhones and Android
  phones.
- **Some fixes only suit some cars.** A change that cures one car can break
  another (the turn-arrows jar works on SEAT but blanks the map on VW), so
  those changes ship switched off.
- **Some features are new.** They stay off until owners have tested them on
  that car. Once a car is tested, the setting becomes that car's `auto`
  value in the next release.

So most settings ship as `auto` (the installer fills in your car's tested
value) or switched off.

## How to change a setting

1. On the SD card, open `ClusterMap/gal_dualscreen.conf` in a plain text
   editor. The file is grouped into the same sections as this page.
2. **A line that starts with `#` is switched off.** To use one, delete the `#`
   at the very start of the line and set the value. Keep only one active line
   per setting.
   ```ini
   #CLUSTERMAP_CARPLAY_CARD_POSITION=left    <- off: no effect
   CLUSTERMAP_CARPLAY_CARD_POSITION=top      <- on
   ```
3. Save, put the card back, **install again**, then reboot. Editing the file
   alone changes nothing on the unit.
4. `ClusterMap/update_result.txt` on the card says what the installer used.

**Your changes are kept.** Each install remembers the lines you changed and
puts them back at the next install (even from a new release's fresh file),
unless you change that line again on the new card. `update_result.txt` lists
what was kept. `CLUSTERMAP_KEEP_SETTINGS=0` installs only what the card says:
use it once if a setting from an older release keeps coming back. Settings
from before v1.1.1-beta19 are not carried over. Uninstall forgets them.

**The green menu** (hold MENU > `Testmode` > `Green Developer Menu` >
`ClusterMap`) has switches for the common ones, with no SD card needed:

| Screen | Switches |
|---|---|
| `ClusterMapPicture` | Sharper map (`CLUSTERMAP_FULL_FRAME`), light / dark / headlights (`GAL_SECONDARY_UI_THEME`) |
| `ClusterMapOptions` | Hardware decoder (`GAL_PLAYER_DECODER`), keep the phone's map, cluster map off/on (`GAL_DUALSCREEN_ENABLE`) |
| `ClusterMapSupport` | Turn arrows, hardware decoder check, performance figures in the log |

Click a setting below to open it.

- [1. Map on/off and day/night](#1-map-onoff-and-daynight)
- [2. Android Auto map: size and position](#2-android-auto-map-size-and-position)
- [3. Picture and decoder](#3-picture-and-decoder)
- [4. Android Auto extras: turn info, music, keeping the map during a route](#4-android-auto-extras-turn-info-music-keeping-the-map-during-a-route)
- [5. CarPlay map](#5-carplay-map)
- [6. Audi A6/A7 C7.5 CarPlay extras](#6-audi-a6a7-c75-carplay-extras)
- [7. Logs](#7-logs)
- [8. Porting and developer settings](#8-porting-and-developer-settings)
- [Values owners have settled on](Install.md#settings-owners-have-settled-on)

## 1. Map on/off and day/night

<details>
<summary><code>GAL_DUALSCREEN_ENABLE</code>: the cockpit map on or off (shipped: <code>1</code>)</summary>

`0` leaves everything installed but switches the cockpit map off: Android
Auto works as before, with no map in the cockpit. Use it to compare with
stock without uninstalling, or if a wireless Android Auto adapter stops
working with the map (#101). Also in the green menu: `ClusterMapOptions` >
Cluster map OFF / ON (reboot after).

</details>

<details>
<summary><code>CLUSTERMAP_CARPLAY</code>: the CarPlay map on or off (shipped: on)</summary>

`0` installs the Android Auto map only and leaves CarPlay completely stock.
Use it if a **wireless CarPlay adapter** stops working, drops, or loses the
cockpit map with the CarPlay map installed (#55, #56, #196, #207). Some
adapters work fine with it: a Carlinkit 5.0, and an Ottocast Mini Pico on a
VW `K3342` (#58).

</details>

<details>
<summary><code>GAL_SECONDARY_UI_THEME</code>: day/night (shipped: <code>0</code>, follows the headlights)</summary>

`0` follows the headlights like the centre screen, `1` is always light, `2`
always dark. Google Maps follows it. **Waze always draws its cockpit map
dark**, whatever is set (a Waze bug, reported to Google). `1` or `2` uses two
bytes of the insets message, so fewer insets can go above 127. Also in the
green menu: `ClusterMapPicture`.

</details>

<details>
<summary><code>CLUSTERMAP_SPLASH</code>: start-up splash (shipped: <code>1</code>)</summary>

When the cockpit switches to the phone's map it shows the project's mark for
about 2.5 s, then fades into the map. Not shown with Audi's direct hardware
decoder. `0` turns it off.

</details>

## 2. Android Auto map: size and position

These change **Android Auto only**. CarPlay has its own in section 5.
Start from the [values owners have settled on](Install.md#settings-owners-have-settled-on)
for your car.

<details>
<summary><code>GAL_SECONDARY_DPI</code>: map text and card size (shipped: <code>auto</code>)</summary>

Lower draws the map's text, icons and cards smaller, so more map shows.
Higher draws them larger. Below about 140, Google Maps changes from two
cards to one in the middle. `auto` is what owners settled on for your make:
SEAT 125, Skoda 125, VW 138, Audi A4 B9 140, the A3 8V with 1080p 160,
otherwise 125. A number here is kept as it is. Not used by CarPlay.

</details>

<details>
<summary><code>GAL_SECONDARY_INSETS</code>: keeping buttons and cards clear of the dials (shipped: <code>auto</code>)</summary>

Four numbers, **top, bottom, left, right**: how far from each edge the phone
keeps its buttons, cards and the car. Change it when the arrival time, the
turn card or the car hides behind a dial or warning light. The phone keeps
the car near the middle of the space left over, so to move the car **down**,
raise the first number or lower the second, in steps of 10 (#96). Raising
the second number moves it up.

`auto` is SEAT `105,127,127,127`, Skoda `40,127,127,127`, VW `52,82,127,127`,
and `40,40,127,127` otherwise. On 800×480 at most three of the four can be
above 127 (only one with `GAL_SECONDARY_UI_THEME` 1 or 2); larger ones are cut
to 127.

With **Sharper map** on a 1440×455 Audi, a top or bottom inset of 114 or less
comes out as 0 (#96): use a larger value, or `CLUSTERMAP_FULL_FRAME=0`. The
installer says so when it happens. Without its own CarPlay insets, CarPlay
uses these too.

</details>

<details>
<summary><code>GAL_SECONDARY_LARGE_INSETS</code>, <code>_SPORT_INSETS</code>, <code>_DEFAULT_VIEW</code>: insets per cockpit view (shipped: off)</summary>

Some cockpits show the map in differently shaped spaces: an A3 8V has
Classic, Large and Sport views, and a SEAT has standard and large dials
(#211). One set of insets can't keep the card and car clear of the dials in
all of them. Set `GAL_SECONDARY_LARGE_INSETS` and/or
`GAL_SECONDARY_SPORT_INSETS` (four numbers, as `GAL_SECONDARY_INSETS`, which
becomes the Classic view), and `GAL_SECONDARY_DEFAULT_VIEW` for the view at
start. Then green menu > `ClusterMapSupport` > **7**, **8** or **9** tells
the cluster map which view is showing, and the phone redraws with that
view's insets straight away. By kashavsehra (#183), car-tested on his A3.
The cockpit's own view button isn't followed yet: that part is being worked
on per car.

</details>

<details>
<summary><code>CLUSTERMAP_FULL_FRAME</code>: Sharper map (shipped: <code>auto</code>)</summary>

On a wide window the phone normally leaves margins, and only part of the
picture carries map. `1` has the phone draw on the whole frame with wide
pixels instead: more detail, same layout. From AMDFX60's fork, car-tested on
his Skoda Superb. `auto` is 1 where owners settled on it (VW 1010×376) and 0
elsewhere. Also in the green menu: `ClusterMapPicture` > Sharper map.

</details>

<details>
<summary><code>CLUSTERMAP_720P</code>, <code>CLUSTERMAP_1080P</code>: sharpest map (shipped: <code>0</code>, <code>auto</code>)</summary>

The phone sends a 1280×720 or 1920×1080 picture and the player keeps the
cockpit window's pixels 1:1. Only worth it on a window larger than 800×480,
and it costs processor time. Use one or the other; both take precedence over
`CLUSTERMAP_FULL_FRAME`.

- **1080p** needs the hardware decoder (`GAL_PLAYER_DECODER=hw`). `auto` is 1
  on the Audi A3/S3/RS3 8V `P5089` (with DPI 160 and insets `50,100,75,75`),
  and 0 elsewhere.
- **720p on VW, Skoda and SEAT is always decoded in software**, even with
  `GAL_PLAYER_DECODER=hw` (see `GAL_PLAYER_HW_HD`). That is heavy work for the
  unit, and the 1010×376 cockpits gain little from it.

</details>

<details>
<summary><code>CLUSTERMAP_HD_RECOVERY</code>: when 720p/1080p decoding fails (shipped: <code>nextboot</code>)</summary>

Every mode first retries once. On a second failure: `stock` goes back to the
car's own map until the next reboot; `nextboot` does that and starts the
next boot one size smaller (1080p > 720p > 800×480); `restart` restarts
Android Auto straight away one size smaller (the centre screen is without it
for about 15 s). The smaller size is kept until the next install. Not
car-tested yet.

</details>

<details>
<summary><code>GAL_CROP_TOP</code>, <code>GAL_CROP_BOTTOM</code>: manual crop (shipped: off)</summary>

Crop rows from the top and bottom of Android Auto's 800×480 picture and
stretch the rest to the window. For a 1440×455 window, 15 and 10 leave
exactly 455 rows. Remove the `#` from both lines. Tested on an Audi A3 8V
(#85).

</details>

<details>
<summary><code>GAL_PLAYER_WINDOW</code>: the cockpit window's size (shipped: off)</summary>

Only if `update_result.txt` says the cluster map window was not listed and
the installer guessed wrong. It assumes 1010×376 on SEAT and Skoda and
800×480 on VW, but some VW cockpits are 1010×376 (#52). Example:
`GAL_PLAYER_WINDOW=1010x376`.

</details>

<details>
<summary><code>GAL_PRIMARY_DPI</code>: Android Auto on the centre screen (shipped: off)</summary>

Not the cockpit: the **centre screen**. Lower shows smaller text and more on
screen, higher larger, 60 to 400. The unit's own value is 213. The same as
aawireless's DPI setting, which its passthrough mode loses. Reconnect the
phone after installing. Car-tested in #71.

</details>

## 3. Picture and decoder

<details>
<summary><code>GAL_PLAYER_DECODER</code>: hardware or software decoding (shipped: <code>auto</code>)</summary>

- `hw` uses the unit's own video decoder, at about a third of the processor
  time. It is car-tested on the Golf `P4521` and the Audi A3 8V `P5089`.
- `sw` decodes on the processor. It works everywhere.
- `auto` is `hw` on the trains where owners have tested it, and `sw` on every
  other.

On any other car, run the green menu's **Hardware decoder check**
(`ClusterMapSupport`) first: it says `usable` or `not usable` and changes
nothing. If `hw` won't open, the player uses software; if it fails while
decoding, it stays off until the next reboot. Also a green menu switch:
`ClusterMapOptions`. `update_result.txt` says which one it chose.

</details>

<details>
<summary><code>GAL_PLAYER_HW_HD</code>: hardware decoding for 720p/1080p on VW, Skoda, SEAT (shipped: off)</summary>

On VW, Skoda and SEAT the unit's decoder is used for the 800×480 picture
only; 720p and 1080p are decoded in software. At 720p it blacked out a
Skoda's centre screen each time Android Auto came back to it (#145). `1` uses
it for them anyway (not recommended). Audi's direct path is not affected.
`update_result.txt` says when this applies ("decoded in SOFTWARE on this
car").

</details>

<details>
<summary><code>GAL_PLAYER_NVSS_OUTPUT</code>: the decoder's output (shipped: 1, line off)</summary>

Which output the unit's decoder draws to when it draws straight to the
cockpit. With the line off the player uses 1, which is car-tested for Audi
hardware decoding with 1080p. If the cluster stays black with `hw`, try `0`.
On Skoda, output 1 reports as 0×0.

</details>

<details>
<summary><code>GAL_ACK_EVERY_FRAME</code>: cockpit map lagging the centre screen (shipped: off)</summary>

If the cockpit map runs a second or more behind (most with 720p), `1` makes
the player acknowledge every picture so the phone never runs ahead of the
decoder. AMDFX60's Skoda fork went from about 2 s to 34-308 ms. Not yet
car-tested in this project.

</details>

<details>
<summary><code>GAL_PLAYER_PRIORITY_CAP</code>: centre screen black after leaving a menu (shipped: <code>auto</code>)</summary>

On a Skoda `P4526`, a busy cockpit player sometimes left the centre screen
black after leaving the green menu or the radio (#125). `12` keeps the
player below the display driver, which made it rare. `auto` uses 12 on the
trains where it was needed; `0` is off. Try 12 if your centre screen goes
black that way.

</details>

<details>
<summary><code>GAL_PLAYER_PRIORITY</code>, <code>GAL_PLAYER_NEON</code>, <code>GAL_PLAYER_REASSERT</code>, <code>GAL_PLAYER_COLOR</code>: rarely needed</summary>

- `GAL_PLAYER_PRIORITY=12`: raises the player a little if the map stutters
  when the unit is busy. Never lowers it. Not car-tested.
- `GAL_PLAYER_NEON=0`: decodes without the processor's NEON instructions, as
  up to v1.2.3 (slower). The player does this by itself after a crash; set it
  only if the map keeps dropping back to the car's own.
- `GAL_PLAYER_REASSERT=1`: if the phone's map shows for a moment and then the
  car's own map comes back while the phone is still connected (#105), the
  player switches back to the phone's picture, at most ten times a session.
  Not car-tested.
- `GAL_PLAYER_COLOR=old`: the colours as before v1.2.1 (greyer blacks), to
  compare.

</details>

## 4. Android Auto extras: turn info, music, keeping the map during a route

Use at most one of `CLUSTERMAP_KEEP_ARROWS`, `CLUSTERMAP_TURN_INFO` and
`CLUSTERMAP_MUSIC_INFO`. Each of these installs or removes a small Java
add-on, so **install again and reboot** after changing them; uninstall
removes them.

<details>
<summary><code>CLUSTERMAP_ADD_NAVIGNORE</code>: the map goes when a route starts (shipped: <code>0</code>)</summary>

Without the NavActiveIgnore patch, the cockpit drops the map as soon as the
phone starts a route ("navigation on mobile device is active"). The
installer adds it by itself on most supported trains; `update_result.txt`
says whether it did. `1` adds it on the others, with a backup, and uninstall
removes it. It edits the script that starts the centre screen, so check
that SSH works first.

**VW `K3342` with an iPhone: leave it at 0.** With it loaded, CarPlay stops
connecting there (#62, #106, #111). Use `CLUSTERMAP_CARPLAY_HIDE_NAV` for
CarPlay instead.

</details>

<details>
<summary><code>CLUSTERMAP_TURN_INFO</code>: turn arrow and distance in the dials, with the map (shipped: off)</summary>

`1` sends Android Auto's turn info to the cockpit while keeping the map: the
cockpit draws its own arrow and distance beside it. Includes the music info
below. Tested on a Golf R `P4521` (arrow in the right dial, road name above
the map; a second car also shows it on the head-up display). If the cockpit
switches to its arrow view instead, press OK to go back and tell us.

</details>

<details>
<summary><code>CLUSTERMAP_TURN_TEXT</code>: when the road name shows (shipped: <code>auto</code>)</summary>

With `CLUSTERMAP_TURN_INFO=1`. `auto` sends the road name only while the
cockpit is not showing the map (Google's card already shows it there),
`always` every time, `never` arrow and distance only.

</details>

<details>
<summary><code>CLUSTERMAP_MUSIC_INFO</code>: track info on the media screen (shipped: off)</summary>

`1` shows the track playing (title, artist, cover) on the cockpit's media
screen, with the map. With CarPlay it shows title, artist and album instead
of "Apple CarPlay". Sends no turn data, so the map stays up on a route. On
VW, SEAT and Skoda trains and VW `K3342`; `update_result.txt` says whether it
was added.

</details>

<details>
<summary><code>CLUSTERMAP_KEEP_ARROWS</code>: the full turn-arrows jar (shipped: <code>0</code>)</summary>

`1` keeps the original turn-arrows jar with the map (map, arrows and music
together). Works on SEAT. **Leave it at 0 on VW**: the map has gone blank
when a route starts, and a Golf cockpit switched to its own arrow view and
stayed there. `CLUSTERMAP_TURN_INFO` is the safer way to get arrows.

</details>

<details>
<summary><code>CLUSTERMAP_AU37X_COVER</code>: cover art on the Audi A3 8V (shipped: off)</summary>

Audi A3 8V `P5089` only: `1` shows Android Auto's cover art, title, artist,
album and playback time on the cockpit's media tab. By kashavsehra (#195),
car-tested on his A3. Added only on the exact interface build it was made
for.

</details>

## 5. CarPlay map

CarPlay ignores the Android Auto DPI. **Install again, then plug the iPhone
in again** after changing any of these.

<details>
<summary><code>CLUSTERMAP_CARPLAY_SCALE</code>: smaller text and icons, more map (shipped: 100)</summary>

The iPhone sizes its text and icons from the screen's size in millimetres;
this declares it larger. Above 100: smaller text and icons, more map. Below
100: larger. 70 to 200; try 130, then 160. The picture stays the window's
own size, so it costs nothing. **This is the one to use first.**

</details>

<details>
<summary><code>CLUSTERMAP_CARPLAY_FRAME_SCALE</code>: the older way to fit more (shipped: off)</summary>

The iPhone draws a larger picture and the player shrinks it into the window,
100 to 200. Replaces `CLUSTERMAP_CARPLAY_SCALE` when set. **It costs
decoding time**: on a SEAT 1010×376 window, 160 made the iPhone send 1616×600,
the player fell behind, and the map jumped every few seconds (Discussion
#193). Prefer `CLUSTERMAP_CARPLAY_SCALE`, and keep this one low if you use it.

</details>

<details>
<summary><code>CLUSTERMAP_CARPLAY_INSETS</code>: keeping CarPlay's card and arrival line clear (shipped: off)</summary>

Top, bottom, left, right, like `GAL_SECONDARY_INSETS`, but for CarPlay only,
and each may go above 127. Unset, CarPlay uses `GAL_SECONDARY_INSETS`. If the
arrival time is cut off at the bottom, raise the second number in small
steps. Too large and the iPhone drops the arrival line altogether. Example
from an A6: `40,80,140,127` (#200).

</details>

<details>
<summary><code>CLUSTERMAP_CARPLAY_VIEW</code>, <code>_CARD_POSITION</code>, <code>_SPEEDLIMIT</code>, <code>_COMPASS</code>, <code>_ETA</code>: what CarPlay shows</summary>

- `VIEW`: `full` (map and card), `map` (map only) or `card` (card only).
- `CARD_POSITION`: `left`, `right` or `top`, or `iphone` to let the iPhone
  decide. The turn arrow is inside the card, so it moves with it. On SEAT
  the installer uses `top`, which keeps the car centred during a route
  (#19).
- `SPEEDLIMIT`, `COMPASS`, `ETA`: `yes` or `no`.

Unset, the iPhone decides.

</details>

<details>
<summary><code>CLUSTERMAP_CARPLAY_HIDE_NAV</code>: the CarPlay map goes when a route starts (shipped: auto per car)</summary>

If the cockpit leaves the CarPlay map when the iPhone starts a route, `1`
stops the car being told the iPhone is navigating. The car's own navigation
is then not stopped by an iPhone route either. Car-tested on a VW `K3342`
(#111). On by itself on VW Discover Pro 8 in (`VWG11`) and some Audi A6/A7
trains; `0` turns it off there. Reboot after installing.

</details>

<details>
<summary><code>CLUSTERMAP_CARPLAY_ZOOM</code>: zoom factor hint (shipped: off)</summary>

Tells the iPhone the cockpit's zoom factor, 50 to 200 (another project's
SEAT port sends 70). Below 100 may show more map; what changes is up to
iOS and the app. Not car-tested here.

</details>

<details>
<summary><code>CLUSTERMAP_CARPLAY_TRIAL</code>: CarPlay on an untested library (shipped: off)</summary>

Lets the CarPlay map install on a `libairplay.so` build it isn't accepted on
yet, given as its size in bytes. Use it only when asked in an issue, as a
test you can undo: on an Audi `K3346` one build gave a black centre screen.
`update_result.txt` says when the CarPlay map was not installed and which
library you have. See [CarPlay](CarPlay.md).

</details>

## 6. Audi A6/A7 C7.5 CarPlay extras

These patch the centre screen's navigation, so they go on only on the exact
interface build they were made for. Reboot after installing.

<details>
<summary><code>CLUSTERMAP_CARPLAY_WHEEL_ZOOM</code>: the steering-wheel roller zooms CarPlay (shipped: <code>auto</code>)</summary>

A6/A7 C7.5 `K3663` and the Chinese `K1006_2`: the roller zooms the CarPlay
map on the cockpit, as it zooms the car's own map. `reverse` if it zooms
the wrong way round, `0` to leave the roller to the car's map. Zooming in
not working on some cars is being looked at (#171).

**US A6/A7 `K3341`:** checked against that interface build, but not car-tested
yet, so it goes on only when you ask: `1` (or `reverse`). `update_result.txt`
says so.

</details>

<details>
<summary><code>CLUSTERMAP_CARPLAY_WHEEL_ZOOM_ID</code>: roller id (Chinese A6/A7, shipped: 82137)</summary>

Chinese A6/A7 C7.5 (`K1006_2`) only. Change it only if
`carplay/clustermap-wheelzoom.log` in Save logs shows the roller with
another id.

</details>

<details>
<summary><code>CLUSTERMAP_CARPLAY_GFX_KEEP</code>: put the cockpit's nav tab in map view (shipped: off)</summary>

`K3663` only: while the CarPlay map is up, the cockpit's nav tab is put in
map view (from compass or the route map) and put back afterwards. By
coffee-coco (#170), car-tested on one RS7.

</details>

## 7. Logs

<details>
<summary><code>GAL_DUALSCREEN_DEBUG</code>, <code>GAL_FIX_STREAM_TIMING</code>, <code>GAL_PLAYER_STATS</code>, <code>GAL_HOOK_LOG_MAX_MB</code>: full trace</summary>

Shipped 0, 0, 0 and 1. For a bug report when asked: set 1, 1, 1 and 10,
then install again. The logs live in the unit's memory and are lost at
reboot: take green menu > `ClusterMap` > **Save logs** before switching
off. Read them before posting: the system log can contain phone names and
Bluetooth addresses.

</details>

## 8. Porting and developer settings

<details>
<summary><code>GAL_PROFILE_TRIAL</code>: a firmware without a built-in profile</summary>

A line we give you in an issue when your firmware's Android Auto program
isn't recognised yet. Paste it exactly, starting at the beginning of the
line with no `#`. See [Development](Development.md#adding-a-firmware).

</details>

<details>
<summary>Section 9 of the file: leave as shipped</summary>

The last section of `gal_dualscreen.conf` wires the hook and player
together: display ids and contexts, the stream size the installer writes
itself, the Android Auto protocol version, and test switches. Changing them
can leave the cockpit blank. `GAL_VC_CONTEXT` is the one owners have needed:
70 on VW, SEAT and Skoda; the installer sets the right one on Audi by itself.
See [Development](Development.md).

</details>
