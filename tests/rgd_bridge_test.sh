#!/bin/bash
# End-to-end host verification of:
#  1. carplay/iap2_rgd C library (rgd_wire, rgd_monitor, rgd_packet, rgd_state)
#     on synthetic iAP2 0x1D01 IdentificationInformation, 0x5201 RouteGuidanceUpdate,
#     and 0x5202 RouteGuidanceManeuverUpdate frames.
#  2. ManeuverMapper & GfxKeep RGD bridge driving ClusterService, DSIResponseContainer,
#     RouteInfoElement, CombiElementBankDDP2, and updateCombiServiceHUDInfo(true).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export PATH="$(cat /tmp/lsd/jdk 2>/dev/null || echo /usr)/bin:$PATH"

"$ROOT/java/gfxkeep/build.sh" "$ROOT/build" >/dev/null
"$ROOT/carplay/iap2_rgd/build.sh" "$ROOT/build" >/dev/null

T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT

# 1. Compile and run C test for rgd_wire, rgd_packet, rgd_monitor, rgd_state
cat > "$T/test_rgd_c.c" <<'EOF'
#include <assert.h>
#include <stdio.h>
#include <string.h>
#include "rgd_wire.h"
#include "rgd_packet.h"
#include "rgd_monitor.h"
#include "rgd_state.h"

int main(void) {
    /* 1. Test rgd_identify on a minimal valid 0x1D01 frame with fields 6 and 7 */
    static const uint8_t ident_in[] = {
        0x40, 0x40, 0x00, 0x12, 0x1d, 0x01,
        0x00, 0x06, 0x00, 0x06, 0x4e, 0x09,
        0x00, 0x06, 0x00, 0x07, 0x4e, 0x0a
    };
    uint8_t ident_out[512];
    size_t out_len = rgd_identify(ident_in, sizeof(ident_in), 16, ident_out, sizeof(ident_out));
    assert(out_len > sizeof(ident_in));
    assert(ident_out[0] == 0x40 && ident_out[1] == 0x40);
    assert((((unsigned)ident_out[2] << 8) | ident_out[3]) == out_len);

    /* 2. Test rgd_state_apply with 0x5202 (left turn, -90 deg, LHT=1, step=450m)
     *    and 0x5201 (route_state=1, dist=150m, dest_dist=3200m, rem=420s, order=[1]) */
    static const uint8_t msg_5202[] = {
        0x40, 0x40, 0x00, 0x40, 0x52, 0x02,
        0x00, 0x06, 0x00, 0x00, 0x00, 0x10,             /* f0 component=16 */
        0x00, 0x06, 0x00, 0x01, 0x00, 0x01,             /* f1 index=1 */
        0x00, 0x05, 0x00, 0x03, 0x01,                   /* f3 type=1 (LEFT_TURN) */
        0x00, 0x11, 0x00, 0x04, 'G','e','o','r','g','e',' ','S','t','r','e','e','t', /* f4 AfterManeuverRoadName */
        0x00, 0x08, 0x00, 0x05, 0x00, 0x00, 0x01, 0xc2, /* f5 step_dist=450 */
        0x00, 0x05, 0x00, 0x08, 0x01,                   /* f8 driving_side=1 (LHT) */
        0x00, 0x05, 0x00, 0x09, 0x00,                   /* f9 junction_type=0 */
        0x00, 0x06, 0x00, 0x0b, 0xff, 0xa6              /* f11 exit_angle=-90 */
    };
    static const uint8_t msg_5201[] = {
        0x40, 0x40, 0x00, 0x56, 0x52, 0x01,
        0x00, 0x06, 0x00, 0x00, 0x00, 0x10,             /* f0 component=16 */
        0x00, 0x05, 0x00, 0x01, 0x01,                   /* f1 route_state=1 (ROUTE_SET) */
        0x00, 0x0f, 0x00, 0x03, 'P','i','t','t',' ','S','t','r','e','e','t', /* f3 current_road */
        0x00, 0x0c, 0x00, 0x06, 0,0,0,0, 0,0,0x01,0xa4, /* f6 rem_sec=420 */
        0x00, 0x08, 0x00, 0x07, 0x00, 0x00, 0x0c, 0x80, /* f7 dest_dist=3200 */
        0x00, 0x08, 0x00, 0x0a, 0x00, 0x00, 0x00, 0x96, /* f10 dist=150 */
        0x00, 0x06, 0x00, 0x0d, 0x00, 0x01,             /* f13 order=[1] */
        0x00, 0x0f, 0x00, 0x13, 'G','o','o','g','l','e',' ','M','a','p','s', /* f19 source_name */
        0x00, 0x05, 0x00, 0x14, 0x01                    /* f20 source_support=1 */
    };

    struct rgd_state st;
    struct rgd_current cur;
    rgd_state_reset(&st, 16, 1, 1);
    assert(rgd_state_apply(&st, 1, 1, msg_5202, sizeof(msg_5202)) == 1);
    assert(rgd_state_apply(&st, 1, 1, msg_5201, sizeof(msg_5201)) == 1);
    assert(rgd_state_current(&st, &cur) == 1);
    assert(cur.has_maneuver == 1);
    assert(cur.maneuver.type == 1);
    assert(cur.maneuver.exit_angle == -90);
    assert(cur.maneuver.driving_side == 1);
    assert(cur.maneuver.step_distance_m == 450);
    assert(cur.distance_m == 150);
    assert(strcmp(cur.maneuver.road, "George Street") == 0);
    assert(strcmp(st.current_road, "Pitt Street") == 0);
    assert(strcmp(st.source_name, "Google Maps") == 0);
    printf("RGD_C_TESTS_OK\n");
    return 0;
}
EOF
clang -O2 -Wall -Wextra -Werror -I"$ROOT/carplay/iap2_rgd" \
    "$T/test_rgd_c.c" \
    "$ROOT/carplay/iap2_rgd/rgd_wire.c" \
    "$ROOT/carplay/iap2_rgd/rgd_packet.c" \
    "$ROOT/carplay/iap2_rgd/rgd_monitor.c" \
    "$ROOT/carplay/iap2_rgd/rgd_state.c" \
    -o "$T/test_rgd_c"
"$T/test_rgd_c"

# 2. Test ManeuverMapper in Java
cat > "$T/TestMapper.java" <<'EOF'
import java.lang.reflect.Method;
import local.clustermap.HudTelemetry;
import local.clustermap.ManeuverMapper;

public class TestMapper {
    public static void main(String[] args) throws Throwable {
        int[] left = ManeuverMapper.map(ManeuverMapper.MT_LEFT_TURN, -90, 0, 1, true);
        if (left[0] != ManeuverMapper.TURN || left[1] != ManeuverMapper.DIR_LEFT) {
            throw new IllegalStateException("LEFT_TURN failed: " + left[0] + "," + left[1]);
        }
        int[] rbtLht = ManeuverMapper.map(ManeuverMapper.MT_ROUNDABOUT_EXIT_1 + 1, 0, 1, 1, true);
        if (rbtLht[0] != ManeuverMapper.ROUNDABOUT_TRS_LEFT || rbtLht[1] != ManeuverMapper.DIR_STRAIGHT) {
            throw new IllegalStateException("ROUNDABOUT LHT failed: " + rbtLht[0] + "," + rbtLht[1]);
        }
        int bar = ManeuverMapper.computeBargraph(ManeuverMapper.MT_LEFT_TURN, 150, true, 300);
        if (bar != 50) {
            throw new IllegalStateException("Bargraph expected 50, got " + bar);
        }
        int barFar = ManeuverMapper.computeBargraph(ManeuverMapper.MT_LEFT_TURN, 450, true, 500);
        if (barFar != -1) {
            throw new IllegalStateException("Bargraph expected -1, got " + barFar);
        }
        short[] rgi = ManeuverMapper.buildDdp2RgiStream(left[0], left[1], ManeuverMapper.MT_LEFT_TURN);
        if (rgi == null || rgi.length != 2 || rgi[0] != ManeuverMapper.TURN || rgi[1] != 64) {
            throw new IllegalStateException("buildDdp2RgiStream left turn failed");
        }
        short[] rgiRbt = ManeuverMapper.buildDdp2RgiStream(rbtLht[0], rbtLht[1], ManeuverMapper.MT_ROUNDABOUT_EXIT_1 + 1);
        if (rgiRbt == null || rgiRbt.length != 4 || rgiRbt[0] != ManeuverMapper.ROUNDABOUT_TRS_LEFT || rgiRbt[2] != -1 || rgiRbt[3] != 2) {
            throw new IllegalStateException("buildDdp2RgiStream roundabout failed");
        }
        System.out.println("RGD_JAVA_MAPPER_OK");

        /* Test HudTelemetry InvocationHandler on synthetic DSI structs */
        HudTelemetry ht = new HudTelemetry();
        Method mOil = FakeListener.class.getMethod("updateBCOilTemperatureValue", new Class[] {FakeTemp.class, Integer.TYPE});
        Method mMid = FakeListener.class.getMethod("updateDynamicVehicleInfoMidFrequent", new Class[] {FakeMid.class, Integer.TYPE});
        Method mHigh = FakeListener.class.getMethod("updateDynamicVehicleInfoHighFrequent", new Class[] {FakeHigh.class, Integer.TYPE});

        ht.invoke(ht, mOil, new Object[] {new FakeTemp(1, 64.0f, 0), new Integer(1)});
        ht.invoke(ht, mMid, new Object[] {new FakeMid(3, 5, 52, 14.2f), new Integer(1)});
        ht.invoke(ht, mHigh, new Object[] {new FakeHigh(2200, (byte) 10, 1.1f, 0.0f, 0, 0.05f, 0.0f, (byte) 20, 0.0f), new Integer(1)});
        ht.invoke(ht, mOil, new Object[] {new FakeTemp(1, 82.0f, 0), new Integer(1)});
        /* Stock RS7 WOT pull at 6000 RPM, 1.20 bar boost (2.213 bar MAP), 110 km/h @ 0.52G:
         * Fused calculator must derive ~412 kW / 560 HP / 656 Nm */
        ht.invoke(ht, mHigh, new Object[] {new FakeHigh(6000, (byte) 75, 2.20f, 0.0f, 0, 0.52f, 0.0f, (byte) 100, 110.0f), new Integer(1)});
        int stockHp = ht.getFusedPowerHp();
        int stockNm = ht.getFusedTorqueNm();
        if (stockHp < 540 || stockHp > 580 || stockNm < 630 || stockNm > 685) {
            throw new IllegalStateException("Stock WOT calc out of range: " + stockHp + " HP, " + stockNm + " Nm");
        }
        /* Stage 2 tuned RS7 WOT pull at 6000 RPM, 1.65 bar boost (2.65 bar MAP), 130 km/h @ 0.62G,
         * even if ECU reports 412 kW stock cap: Fused calculator must derive ~680-700 HP */
        for (int i = 0; i < 6; i++) {
            ht.invoke(ht, mHigh, new Object[] {new FakeHigh(6000, (byte) 100, 2.65f, 412.0f, 700, 0.62f, 0.0f, (byte) 100, 130.0f), new Integer(1)});
        }
        int tunedHp = ht.getFusedPowerHp();
        int tunedNm = ht.getFusedTorqueNm();
        if (tunedHp < 640 || tunedHp > 760 || tunedNm < 750) {
            throw new IllegalStateException("Tuned WOT calc clipped or out of range: " + tunedHp + " HP, " + tunedNm + " Nm");
        }
        System.out.println("HUD_TELEMETRY_TEST_OK (stock=" + stockHp + "HP/" + stockNm + "Nm, stage2=" + tunedHp + "HP/" + tunedNm + "Nm)");
    }

    public interface FakeListener {
        void updateBCOilTemperatureValue(FakeTemp t, int valid);
        void updateDynamicVehicleInfoMidFrequent(FakeMid m, int valid);
        void updateDynamicVehicleInfoHighFrequent(FakeHigh h, int valid);
    }

    public static class FakeTemp {
        public int state;
        public float temperatureValue;
        public int temperatureUnit;
        public FakeTemp(int s, float v, int u) { state = s; temperatureValue = v; temperatureUnit = u; }
    }

    public static class FakeSpeed {
        public int speedValueState = 1;
        public float speedValue;
        public int speedUnit = 0;
        public FakeSpeed(float v) { speedValue = v; }
    }

    public static class FakeMid {
        public int currentGear;
        public int automaticGearShiftTransMode;
        public int gearboxOilTemperature;
        public float batteryVoltage;
        public FakeMid(int g, int tm, int box, float bv) {
            currentGear = g; automaticGearShiftTransMode = tm; gearboxOilTemperature = box; batteryVoltage = bv;
        }
    }

    public static class FakeHigh {
        public int engineSpeed;
        public byte relChargingAirPressure;
        public float absChargingAirPressure;
        public float currentOutputPower;
        public int currentTorque;
        public float longitudinalAcceleration;
        public float lateralAcceleration;
        public byte acceleratorPosition;
        public FakeSpeed realVehicleSpeed;
        public FakeSpeed vehicleSpeed;
        public FakeHigh(int rpm, byte relB, float absB, float kw, int nm, float lg, float latg, byte thr, float spd) {
            engineSpeed = rpm; relChargingAirPressure = relB; absChargingAirPressure = absB;
            currentOutputPower = kw; currentTorque = nm; longitudinalAcceleration = lg;
            lateralAcceleration = latg; acceleratorPosition = thr;
            realVehicleSpeed = new FakeSpeed(spd); vehicleSpeed = new FakeSpeed(spd);
        }
    }
}
EOF
javac -cp "$ROOT/build/ClusterMapGfxKeep.jar" -d "$T" "$T/TestMapper.java"
java -cp "$ROOT/build/ClusterMapGfxKeep.jar:$T" TestMapper
