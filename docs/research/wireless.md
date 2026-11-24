# Native wireless Android Auto and CarPlay: not planned

Short version: the Harman MIB2 High's Wi-Fi only works on 2.4 GHz, so the
project won't make the unit itself do wireless Android Auto or CarPlay. For
wireless, use an adapter made for it (AAWireless, Motorola MA1, Carlinkit and
similar). The cockpit map works with those, because the car sees them as a
phone on a cable ([CarPlay](../CarPlay.md#wireless-adapters) for the CarPlay
map's limits).

The groundwork code (a Save logs probe and a bench test of `gal` over Wi-Fi)
is kept in the tag `archive/wireless`.

## What was tested

On the owner's Golf (`MHI2_ER_VWG13_P4521_2`), 2026-11-24, over SSH and with
the results written to the SD card. The scripts are in
[wireless_tests](wireless_tests/).

| Test | Result |
|---|---|
| What the Wi-Fi is | Marvell SD8787 Wi-Fi and Bluetooth chip, firmware 14.44.35.p233. The hotspot (`uap0`) runs WPA2 on 2.4 GHz channel 11, with only channels 1, 6 and 11 set up |
| Scan from the car (`wifi_test_1.sh`) | Seven networks heard, all 2.4 GHz (2412 to 2462 MHz), none on 5 GHz, in a driveway where 5 GHz home networks are normal |
| Hotspot on 5 GHz with the car's Wi-Fi client **off** (`wifi_test_5ghz.sh`) | On channel 11 the hotspot starts at once. Channel 36 (5 GHz) is accepted as a setting, but starting the hotspot never answers, it stays stopped, and the driver logs no start. Channel 11 back: starts at once |
| Hotspot and client together | Both run at once on one radio (the car stayed on a phone's hotspot while its own hotspot was up), so they share a channel |

Conclusion: the chip family can do 5 GHz, but this module can't, so it's the
hardware. Newer firmware (linux-firmware has W14.68.35.p66) can't add a radio
it doesn't have. Swapping it would also put Bluetooth at risk, which runs on
the same chip.

## Why that ends it

- **Android Auto:** the stock `gal` only speaks USB (`gal::CUsbdiTransport`).
  Wireless would need our own network transport inside the hook, a Bluetooth
  service inside `btstack` for the handshake, and a 2.4 GHz link. Google is
  phasing 2.4 GHz out for wireless Android Auto, and 2.4 GHz Wi-Fi interferes
  with Bluetooth on a shared chip (see the
  [aa-proxy-rs](https://github.com/aa-proxy/aa-proxy-rs) notes).
- **CarPlay:** VW's iPhone driver has the Wi-Fi handoff code
  (`RequestAccessoryWiFiConfigurationInformation`) but turns it off ("Wifi
  Feature not supported"). Turning it back on would also run on 2.4 GHz only.
- **A USB Wi-Fi stick in the car:** the unit has no USB Wi-Fi drivers (only
  wired USB Ethernet: ASIX, SMSC, ECM/NCM) and no `hostapd`.

## Things learned on the way

- `uaputl sys_cfg_scan_channels`, though it only reads, made the Wi-Fi
  driver fail and reset the chip. The car's client link came back by itself;
  the hotspot stayed off until the MMI was restarted.
- The unit's `grep` can't search binary files, and there is no `strings`,
  `od`, `hexdump`, `date` or `timeout`. Look for strings in a binary on a
  computer, against a copy of the same file size.
- Over SSH through the car's Wi-Fi, any Wi-Fi test can cut the link. Run it
  detached (`sh -c "sh test.sh </dev/null >/dev/null 2>&1 &"`), put a time
  limit on each `uaputl` call, and write the output to the SD card.
- Nothing `uaputl` changes is saved: an MMI restart puts the stock Wi-Fi back.
