#!/usr/bin/env python3
"""Wireless bench test, laptop end (experiments/wireless_bench/README.md).

The phone on this laptop's USB, the laptop on the car's hotspot: the phone
thinks it is plugged into a car, and every byte goes to the car's gal over
Wi-Fi. Proves gal's side of wireless Android Auto without Bluetooth.

    python3 aa_usb_relay.py [car address, default 10.173.189.1] [port, default 5288]

Needs libusb and pyusb:  brew install libusb; python3 -m pip install pyusb
"""
import socket
import sys
import threading
import time

import usb.core
import usb.util

GOOGLE = 0x18D1
AOA_PIDS = (0x2D00, 0x2D01)
# What a head unit says it is when it asks the phone for accessory mode.
AOA_STRINGS = ("Android", "Android Auto", "Android Auto", "2.0.1",
               "https://developer.android.com/auto/index.html", "HU-AAAAAA001")


def find_aoa():
    for pid in AOA_PIDS:
        d = usb.core.find(idVendor=GOOGLE, idProduct=pid)
        if d is not None:
            return d
    return None


def to_accessory_mode():
    """Ask the first Android phone found to switch to accessory mode."""
    for d in usb.core.find(find_all=True):
        if d.bDeviceClass == 9:      # hubs
            continue
        try:
            ver = d.ctrl_transfer(0xC0, 51, 0, 0, 2)
        except usb.core.USBError:
            continue
        v = ver[0] | (ver[1] << 8)
        if v < 1:
            continue
        print(f"phone {d.idVendor:04x}:{d.idProduct:04x}, accessory protocol {v}")
        for i, s in enumerate(AOA_STRINGS):
            d.ctrl_transfer(0x40, 52, 0, i, s.encode() + b"\0")
        d.ctrl_transfer(0x40, 53, 0, 0, None)
        return True
    return False


def open_phone():
    d = find_aoa()
    if d is None:
        if not to_accessory_mode():
            sys.exit("no Android phone found on USB (unlocked, cable in, USB debugging not needed)")
        for _ in range(50):
            time.sleep(0.2)
            d = find_aoa()
            if d is not None:
                break
        if d is None:
            sys.exit("the phone did not come back in accessory mode")
    try:
        d.set_configuration()
    except usb.core.USBError:
        pass   # already configured
    intf = d.get_active_configuration()[(0, 0)]
    ep_in = usb.util.find_descriptor(intf, custom_match=lambda e: usb.util.endpoint_direction(e.bEndpointAddress) == usb.util.ENDPOINT_IN)
    ep_out = usb.util.find_descriptor(intf, custom_match=lambda e: usb.util.endpoint_direction(e.bEndpointAddress) == usb.util.ENDPOINT_OUT)
    usb.util.claim_interface(d, intf)
    print(f"phone in accessory mode ({d.idProduct:04x}), endpoints {ep_in.bEndpointAddress:#x} in, {ep_out.bEndpointAddress:#x} out")
    return d, ep_in, ep_out


def main():
    host = sys.argv[1] if len(sys.argv) > 1 else "10.173.189.1"
    port = int(sys.argv[2]) if len(sys.argv) > 2 else 5288
    d, ep_in, ep_out = open_phone()
    s = socket.create_connection((host, port), timeout=10)
    s.settimeout(None)
    s.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
    print(f"connected to the car at {host}:{port}; relaying (Ctrl-C to stop)")
    stop = threading.Event()
    count = {"car": 0, "phone": 0}

    def car_to_phone():
        try:
            while not stop.is_set():
                b = s.recv(16384)
                if not b:
                    print("the car closed the connection")
                    break
                ep_out.write(b, timeout=5000)
                count["car"] += len(b)
        except Exception as e:  # noqa: BLE001 - report and stop either way
            print(f"car -> phone stopped: {e}")
        stop.set()

    def phone_to_car():
        try:
            while not stop.is_set():
                try:
                    b = ep_in.read(16384, timeout=1000)
                except usb.core.USBTimeoutError:
                    continue
                s.sendall(bytes(b))
                count["phone"] += len(b)
        except Exception as e:  # noqa: BLE001
            print(f"phone -> car stopped: {e}")
        stop.set()

    threads = [threading.Thread(target=car_to_phone, daemon=True), threading.Thread(target=phone_to_car, daemon=True)]
    for t in threads:
        t.start()
    try:
        last = time.time()
        while not stop.is_set():
            time.sleep(0.5)
            if time.time() - last >= 5:
                last = time.time()
                print(f"  car -> phone {count['car']} bytes, phone -> car {count['phone']} bytes")
    except KeyboardInterrupt:
        pass
    stop.set()
    s.close()
    usb.util.dispose_resources(d)
    print(f"done: car -> phone {count['car']} bytes, phone -> car {count['phone']} bytes")


if __name__ == "__main__":
    main()
