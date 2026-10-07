# Navigation status messages and the connection loop

Local field notes, not from upstream. Measured on a VW Golf 7.5, Discover Pro,
`MHI2_ER_VWG13_P4521` (MU1367), October 2026.

## The short version

Once the head unit advertises a cluster display, Google Maps stops sending the
two legacy navigation messages and sends two newer ones instead. The stock 2018
receiver does not know them and answers each with an "unexpected message"
reply. The phone treats that reply as a protocol error and resets the USB link.
The result is a connection loop: the Android Auto logo appears, the cluster map
shows for a moment, the phone disconnects, and it starts again about every
17 seconds.

The hook now drops that reply, which stops the loop.

## The messages

All four travel on the navigation status service. Its service id is assigned by
`gal` at start-up, and it was 12 on this unit and on the Audi units the
MHI2Q projects tested. Do not hardcode 12: read it from the
`event=service.class ... class=_ZTV24NavigationStatusEndpoint` log line.

| Message id | Name | When it is sent | Known to the stock receiver |
|---|---|---|---|
| `0x8003` | NavigationStatus | once, when guidance starts or stops | yes |
| `0x8004` | NavigationNextTurnEvent | legacy turn information | yes |
| `0x8005` | NavigationNextTurnDistanceEvent | legacy distance to the turn | yes |
| `0x8006` | NavigationState | about once a second during guidance | **no** |
| `0x8007` | NavigationCurrentPosition | about once a second during guidance | **no** |

Names for `0x8006` and `0x8007` come from the protocol definitions used by the
`aa-proxy-rs` project, as cited in `kamgurgul/mib2q-carplay`
(`aa_hook/aa_navxlate.c`). They were not decoded independently here.

Sizes seen on the car, including the two-byte id: `0x8003` 4 bytes, `0x8006`
73 or 89 bytes, `0x8007` 37 or 42 bytes.

Message ids `0x8006` and `0x8007` also exist on the media services with a
different meaning, so anything that handles them must check the channel.

## What the log looks like

Before the fix, every session ended within half a second of the first message
on the navigation channel, and `gal` logged no shutdown lines:

```text
event=aap.inbound.first channel=12 role=other ...
(nothing further from this gal; a new gal starts ~13 s later)
```

With the fix, the reply is dropped and the session continues:

```text
event=aap.msg channel=12 class=_ZTV24NavigationStatusEndpoint msg_id=0x8006 bytes=89 n=2
event=aap.unexpected channel=12 class=_ZTV24NavigationStatusEndpoint last_msg_id=0x8006 total=1 action=suppressed fix=suppress_unexpected
```

## The fix and its switch

`src/video_sink_hook.c` interposes `MessageRouter::sendUnexpectedMessage`. While
the cluster sink is registered, the reply is logged and not sent.

| Setting | Default | Effect |
|---|---|---|
| `GAL_FIX_SUPPRESS_UNEXPECTED` | on | `0` sends the reply as stock does. Use only to reproduce the loop. |

Set it in `gal_dualscreen.conf`, not in the supervisor environment.

## Known consequence: no turn data for the Java side

The newer messages are ignored, not translated. The stock Java interface gets
`0x8003` (guidance active) but never the turn or distance events. Anything that
draws turn arrows from them, such as `VCAndroidAuto.jar`, has nothing to show.

`kamgurgul/mib2q-carplay` solves this by rewriting `0x8006` to `0x8004` and
`0x8007` to `0x8005` in place before `gal` routes them. That translator has not
been ported here. It is the place to start if turn arrows are wanted beside the
cluster map.

## Checklist when a friend's car loops

1. Collect logs with `collect_logs.sh`.
2. Find the navigation service id in the `event=service.class` lines.
3. Look for `event=aap.unexpected`. If the lines say `action=sent`, the
   suppression is off or the cluster sink did not register.
4. If there are no `aap.unexpected` lines at all and the session still drops,
   the cause is something else. Note the last `event=aap.msg` line before the
   log goes quiet: it names the service and message that preceded the drop.
