# Wireless bench test (test builds only)

Can the car's own Android Auto program (`gal`) run a phone session over the
car's Wi-Fi instead of the cable? This answers that one question. It is the
middle of wireless Android Auto: the Bluetooth start, which lets a phone go
wireless by itself, comes after and is not here.

```
phone --USB--> laptop (aa_usb_relay.py) --car hotspot, TCP 5288--> gal (bench hook)
```

The phone believes it is plugged into a car. The laptop passes every byte on
to the car over Wi-Fi, and the car's `gal` takes it as a normal phone
connection. If the map appears, `gal`'s side of wireless works unchanged.

**Only for `MHI2_ER_VWG13_P4521` (the owner's Golf).** The hook checks every
address and instruction word first, and on any other `gal` it changes
nothing and says so in its log. Never in a release: `./build_local.sh`
builds it only with the `wireless-bench` target, into its own zip.

## What it changes (in the running gal only)

`wireless_bench.c` has the details and addresses.
- `CUsbdiTransport::init`: a jump to the bench code. A phone on the cable
  still goes to the stock code. Only the made-up bus and device 250/250 use
  the socket.
- `CUsbdiTransport` read, write, stop and destructors: the socket for the
  bench session, stock for everything else.
- `CGALReceiver` job handler: notes the receiver's address, then runs the
  stock handler.
- A listener on the hotspot's own address, port 5288, and the firewall line
  for it (`bench_firewall.sh`, loaded live; a reboot puts the stock rules
  back).

## Steps

1. Build: `./build_local.sh wireless-bench` gives
   `dist/mib-cluster-map_<version>-wireless-bench.zip`. Its settings have
   `GAL_WIRELESS_BENCH=1`.
2. Install it on the Golf like any version. Reboot.
3. Over SSH: `sh <card>/ClusterMap/bench_firewall.sh`. Do this after each
   start-up. `/tmp/wireless_bench.log` should say `listening on
   10.173.189.1:5288`.
4. Laptop: join the car's hotspot. `brew install libusb`,
   `python3 -m pip install pyusb`.
5. Phone on the laptop's USB, unlocked, and no cable in the car.
   `python3 experiments/wireless_bench/aa_usb_relay.py`.
6. Watch the centre screen and the cockpit, then green menu > Save logs.
   `run_logs/N/wireless/wireless_bench.log` has the bench log, and the hook
   and gal logs are beside it.

## Reading the result

| Bench log / screen | Meaning |
|---|---|
| `no match` | not the P4521 gal; nothing patched |
| `receiver not seen yet` | connect again a few seconds later |
| `processConnectGAL returned 0` | gal refused the session start; its log says why (receiverState) |
| `gal never asked for the transport` | the start went another way than found; gal's log |
| `first bytes from the phone`, then the counts grow | the protocol runs over Wi-Fi: **the key result** |
| map on the cockpit, nothing on the centre screen | gal works; the centre screen waits for smartphone_integrator, which never saw a phone (the next thing to solve) |
| Android Auto on both screens | the whole session works over Wi-Fi |

To undo: install the normal version again (or Uninstall). Removing
`GAL_WIRELESS_BENCH=1` from the settings also turns it off.
