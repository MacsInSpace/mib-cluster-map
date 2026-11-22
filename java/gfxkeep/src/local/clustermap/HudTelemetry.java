package local.clustermap;

import java.lang.reflect.Field;
import java.lang.reflect.InvocationHandler;
import java.lang.reflect.Method;
import java.lang.reflect.Proxy;
import java.util.Hashtable;

/**
 * Live RS7 C7.5 (AU57x, 4.0 TFSI V8 + ZF 8HP90 + quattro) Performance Telemetry
 * & Auto-Timer for the Factory Windshield HUD.
 *
 * Power (kW / PS / HP) & Torque (Nm) Engine (bTres-grade + Slope-Compensated Virtual Dyno):
 *  Fuses three real-time sources so it works whether or not the C7.5 gateway
 *  populates B9-style Sport Display DSI fields, and never clips at the stock
 *  412 kW / 700 Nm factory ceiling on Stage 1/2/3 tuned RS7s:
 *
 *  1. Slope-Compensated Road-Load & Inertial Virtual Dyno (SAE J2263):
 *     - Vehicle mass m = 2030 kg (1955 kg curb + driver), per-gear rotational
 *       inertia factor e_i for ZF 8HP90 gears 1..8 (1.22 .. 1.02).
 *     - Combines wheel-speed derivative (dv/dt) with the ESP longitudinal
 *       accelerometer (a_sensor = dv/dt + g*sin(theta)), which automatically
 *       includes road slope gravity force m*g*sin(theta) uphill or downhill
 *       (with auto-detection of m/s^2 vs G sensor units).
 *     - Ambient-temperature-corrected air density rho(T_amb) * 0.5 * Cd * A * v^2
 *       (RS7 Cd = 0.30, A = 2.31 m^2 -> CdA = 0.693 m^2) + speed-dependent
 *       rolling resistance for 275/30 R21 tires.
 *     - ZF 8HP90 + permanent quattro drivetrain loss model (12% mesh loss +
 *       RPM-proportional hydraulic pump parasitic loss).
 *
 *  2. 4.0 TFSI Twin-Turbo V8 Thermodynamic Air-Mass Model:
 *     - Uses manifold absolute pressure (MAP = 1.013 + boost_bar), ambient air
 *       density correction, throttle/load factor, and the 3993 cc 4.0 TFSI V8
 *       volumetric & thermal efficiency curve across 1500..6800 RPM.
 *     - Accurately models both stock (1.20 bar -> 700 Nm / 412 kW / 560 PS) and
 *       tuned Stage 1/2/3 boost levels (1.50..2.20+ bar -> 700..850+ PS) without
 *       clipping at the stock ECU MDNORM torque cap.
 *
 *  3. Direct ECU DSI currentOutputPower / currentTorque (when populated and not
 *     clipped below the thermodynamic/virtual-dyno measurement), with exact
 *     shaft identity P_kW = (Torque_Nm * RPM) / 9549.2968.
 *
 * Java 1.2 compatible (class version 46, no StackMapTable, no autoboxing).
 */
public final class HudTelemetry implements InvocationHandler {
    private static final int WARM_OIL_C = 80;
    private static final long RESULT_HOLD_MS = 12000L;
    private static final long READY_HOLD_MS = 6000L;
    private static final long CONNECT_RETRY_MS = 10000L;
    private static final long LOG_INTERVAL_MS = 30000L;

    /* C7.5 RS7 4.0 TFSI + ZF 8HP90 physical constants */
    private static final float RS7_MASS_KG = 2030.0f;
    private static final float RS7_CDA = 0.693f; /* Cd 0.30 * A 2.31 m^2 */
    private static final float RS7_CRR0 = 0.0115f;
    private static final float RS7_CRR2 = 0.0000055f;
    private static final float GRAVITY = 9.80665f;
    private static final float QUATTRO_MESH_EFF = 0.88f;
    private static final float QUATTRO_PUMP_LOSS_KW = 10.5f;
    private static final float TIRE_CIRC_M = 2.185f; /* 275/30 R21 */
    private static final float FINAL_DRIVE = 3.076f;

    /* ZF 8HP90 gear ratios (1st..8th) and rotational inertia factors e_i */
    private static final float[] GEAR_RATIOS = {
        0.0f, 4.714f, 3.143f, 2.106f, 1.667f, 1.285f, 1.000f, 0.839f, 0.667f
    };
    private static final float[] GEAR_INERTIA = {
        1.06f, 1.22f, 1.12f, 1.07f, 1.05f, 1.04f, 1.03f, 1.025f, 1.02f
    };

    private boolean vehicleStatesBound;
    private boolean carKombiBound;
    private boolean viewOptionsLogged;
    private boolean midViewOptionsLogged;
    private boolean bcViewOptionsLogged;
    private boolean dcViewOptionsLogged;
    private long lastConnectAttempt;
    private long lastTelemetryLog;

    /* High-frequency telemetry */
    private volatile boolean highFreqKnown;
    private volatile boolean canSpeedActive;
    private volatile int rpm = -1;
    private volatile int relBoostPct = -1;
    private volatile float absBoostBar = -1.0f;
    private volatile float maxBoostBar = 0.0f;
    private volatile int rawEcuPowerKw = -1;
    private volatile int rawEcuTorqueNm = -1;
    private volatile float longAccelRaw = 0.0f;
    private volatile float latAccelRaw = 0.0f;
    private volatile int throttlePct = -1;
    private volatile float speedKmh = 0.0f;
    private volatile boolean speedKnown;

    /* Fused bTres-grade computed outputs */
    private volatile int fusedPowerKw = 0;
    private volatile int fusedPowerHp = 0;
    private volatile int fusedTorqueNm = 0;
    private volatile int peakPowerHp = 0;
    private volatile int peakTorqueNm = 0;
    private float smoothedPowerKw = 0.0f;
    private float smoothedKinAccelMs2 = 0.0f;
    private long lastPhysicsMs;
    private float lastPhysicsSpeedMs;
    private boolean accelSensorIsMs2;

    /* Mid-frequency telemetry */
    private volatile boolean midFreqKnown;
    private volatile int gear = 0;
    private volatile int transMode = 0;
    private volatile int gearboxOilC = -999;
    private volatile float batteryV = 0.0f;
    private volatile boolean kickDown;
    private volatile boolean braking;

    /* Kombi temperatures */
    private volatile boolean oilTempKnown;
    private volatile int oilTempC = -999;
    private volatile boolean coolantTempKnown;
    private volatile int coolantTempC = -999;
    private volatile boolean outsideTempKnown;
    private volatile int outsideTempC = 20;

    /* Warmup transition state */
    private boolean sawColdOil;
    private long oilReadyUntil;

    /* 0-100 and 100-200 auto-timer state */
    private boolean armed0to100;
    private boolean running0to100;
    private long start0to100Ms;
    private float peakBoostDuringRun;
    private float peakGDuringRun;
    private int peakHpDuringRun;
    private int peakNmDuringRun;
    private int last0to100Centis = -1;
    private boolean running100to200;
    private long start100to200Ms;
    private int last100to200Centis = -1;
    private long showResultUntil;
    private float prevSpeedKmh;
    private long prevSpeedMs;

    /* Last pushed HUD state to avoid redundant DDP2 traffic */
    private boolean hudActive;
    private String lastTopText = "";
    private String lastMainText = "";
    private int lastBar = -2;
    private long lastHudPush;

    public HudTelemetry() {
    }

    public Object invoke(Object proxy, Method method, Object[] args) throws Throwable {
        String name = method.getName();
        if (name.equals("equals")) {
            boolean eq = args != null && args.length == 1 && proxy == args[0];
            return new Boolean(eq);
        }
        if (name.equals("hashCode")) {
            return new Integer(System.identityHashCode(proxy));
        }
        if (name.equals("toString")) {
            return "ClusterMapHudTelemetry";
        }
        if (args == null || args.length < 2) {
            return null;
        }
        Object lastArg = args[args.length - 1];
        if (lastArg instanceof Integer) {
            int valid = ((Integer) lastArg).intValue();
            if ((valid & 1) != 1) {
                return null;
            }
        }
        Object payload = args[0];
        if (payload == null) {
            return null;
        }
        try {
            if (name.equals("updateDynamicVehicleInfoHighFrequent")) {
                onHighFrequent(payload);
            } else if (name.equals("updateDynamicVehicleInfoMidFrequent")) {
                onMidFrequent(payload);
            } else if (name.equals("updateSemiStaticVehicleData")) {
                onSemiStatic(payload);
            } else if (name.equals("updateDynamicVehicleInfoHighFrequentViewOptions")) {
                onHighFreqViewOptions(payload);
            } else if (name.equals("updateDynamicVehicleInfoMidFrequentViewOptions")) {
                onMidFreqViewOptions(payload);
            } else if (name.equals("updateBCViewOptions")) {
                onBcViewOptions(payload);
            } else if (name.equals("updateDCViewOptions")) {
                onDcViewOptions(payload);
            } else if (name.equals("updateBCOilTemperatureValue")) {
                onOilTemperature(payload);
            } else if (name.equals("updateBCCoolantTemperature")) {
                onCoolantTemperature(payload);
            } else if (name.equals("updateBCOutsideTemperature")) {
                onOutsideTemperature(payload);
            }
        } catch (Throwable ignored) {
        }
        return null;
    }

    private void onHighFrequent(Object info) throws Exception {
        Class c = info.getClass();
        int newRpm = c.getField("engineSpeed").getInt(info);
        int newRelBoost = (int) c.getField("relChargingAirPressure").getByte(info);
        float newAbsBoost = c.getField("absChargingAirPressure").getFloat(info);
        float newPowerKw = c.getField("currentOutputPower").getFloat(info);
        int newTorque = c.getField("currentTorque").getInt(info);
        float newLongA = c.getField("longitudinalAcceleration").getFloat(info);
        float newLatA = c.getField("lateralAcceleration").getFloat(info);
        int newThrottle = (int) c.getField("acceleratorPosition").getByte(info);

        float spd = extractSpeedKmh(c.getField("realVehicleSpeed").get(info));
        if (spd < 0.0f) {
            spd = extractSpeedKmh(c.getField("vehicleSpeed").get(info));
        }

        /* On C7.5 (AU57x), DSICarVehicleStates is a B9 service that immediately pushes
         * an unpopulated all-zero struct at startup. Ignore all-zero structs so we never
         * flag highFreqKnown=true or overwrite GPS speed with 0 unless real CAN data is present. */
        boolean hasSignal = newRpm > 0
                || newRelBoost > 0
                || newAbsBoost > 0.05f
                || newPowerKw > 0.5f
                || newTorque > 0
                || newThrottle > 0
                || spd > 0.1f
                || Math.abs(newLongA) > 0.05f;
        if (!hasSignal && !highFreqKnown) {
            return;
        }

        if (newRpm >= 0 && newRpm <= 10000) rpm = newRpm;
        if (newRelBoost >= 0 && newRelBoost <= 200) relBoostPct = newRelBoost;
        if (newAbsBoost >= 0.0f && newAbsBoost <= 5.0f) absBoostBar = newAbsBoost;
        if (newPowerKw >= 0.0f && newPowerKw <= 1500.0f) rawEcuPowerKw = (int) (newPowerKw + 0.5f);
        if (newTorque >= 0 && newTorque <= 2500) rawEcuTorqueNm = newTorque;
        if (newLongA >= -25.0f && newLongA <= 25.0f) {
            longAccelRaw = newLongA;
            if (newLongA > 2.2f || newLongA < -2.2f) {
                accelSensorIsMs2 = true;
            }
        }
        if (newLatA >= -25.0f && newLatA <= 25.0f) latAccelRaw = newLatA;
        if (newThrottle >= 0 && newThrottle <= 100) throttlePct = newThrottle;

        long now = System.currentTimeMillis();
        if (spd >= 0.0f) {
            speedKmh = spd;
            speedKnown = true;
            if (spd > 0.1f) {
                canSpeedActive = true;
            }
        }
        highFreqKnown = true;
        computeFusedPowerAndTorque(now);
        if (spd >= 0.0f) {
            updateTimers(now, spd);
        }
    }

    private void onMidFrequent(Object info) throws Exception {
        Class c = info.getClass();
        int g = c.getField("currentGear").getInt(info);
        int tm = c.getField("automaticGearShiftTransMode").getInt(info);
        int boxC = c.getField("gearboxOilTemperature").getInt(info);
        float bv = c.getField("batteryVoltage").getFloat(info);
        boolean kd = false;
        boolean brk = false;
        try {
            kd = c.getField("acceleratorKickDown").getBoolean(info);
            brk = c.getField("driverIsBraking").getBoolean(info);
        } catch (Throwable ignored) {
        }

        /* Ignore unpopulated all-zero B9 DynamicVehicleInfoMidFrequent structs on C7.5
         * (where g=0, tm=0, boxC=0, bv=0.0f), which previously caused gearboxOilC=0C
         * and triggered a permanent false "WARMUP Oil 0C (wait 80C)" loop! */
        boolean hasSignal = g > 0 || tm > 0 || bv >= 8.0f || boxC != 0 || kd || brk;
        if (!hasSignal && !midFreqKnown) {
            return;
        }
        kickDown = kd;
        braking = brk;
        if (g >= 0 && g <= 10) gear = g;
        if (tm >= 0 && tm <= 15) transMode = tm;
        if (boxC >= -40 && boxC <= 200 && (boxC != 0 || g > 0 || bv >= 8.0f)) {
            gearboxOilC = boxC;
        }
        if (bv >= 8.0f && bv <= 18.0f) batteryV = bv;
        midFreqKnown = true;
    }

    private void onSemiStatic(Object info) throws Exception {
        Class c = info.getClass();
        float maxB = c.getField("maxChargingAirPressure").getFloat(info);
        if (maxB > 0.1f && maxB <= 5.0f) {
            maxBoostBar = maxB;
        }
    }

    private void onHighFreqViewOptions(Object vo) {
        if (viewOptionsLogged || vo == null) return;
        viewOptionsLogged = true;
        try {
            GfxKeep.logTelemetry(System.currentTimeMillis(), "HudTelemetry HighFreqViewOptions=" + vo.toString());
        } catch (Throwable ignored) {
        }
    }

    private void onMidFreqViewOptions(Object vo) {
        if (midViewOptionsLogged || vo == null) return;
        midViewOptionsLogged = true;
        try {
            GfxKeep.logTelemetry(System.currentTimeMillis(), "HudTelemetry MidFreqViewOptions=" + vo.toString());
        } catch (Throwable ignored) {
        }
    }

    private void onBcViewOptions(Object vo) {
        if (bcViewOptionsLogged || vo == null) return;
        bcViewOptionsLogged = true;
        try {
            GfxKeep.logTelemetry(System.currentTimeMillis(), "HudTelemetry BCViewOptions=" + vo.toString());
        } catch (Throwable ignored) {
        }
    }

    private void onDcViewOptions(Object vo) {
        if (dcViewOptionsLogged || vo == null) return;
        dcViewOptionsLogged = true;
        try {
            GfxKeep.logTelemetry(System.currentTimeMillis(), "HudTelemetry DCViewOptions=" + vo.toString());
        } catch (Throwable ignored) {
        }
    }

    private void onOilTemperature(Object tempObj) throws Exception {
        int valC = extractTempC(tempObj);
        if (valC >= -40 && valC <= 200) {
            if (valC < WARM_OIL_C - 2) {
                sawColdOil = true;
            } else if (sawColdOil && valC >= WARM_OIL_C && oilTempC < WARM_OIL_C) {
                oilReadyUntil = System.currentTimeMillis() + READY_HOLD_MS;
                sawColdOil = false;
            }
            oilTempC = valC;
            oilTempKnown = true;
        }
    }

    private void onCoolantTemperature(Object tempObj) throws Exception {
        int valC = extractTempC(tempObj);
        if (valC >= -40 && valC <= 200) {
            coolantTempC = valC;
            coolantTempKnown = true;
        }
    }

    private void onOutsideTemperature(Object tempObj) throws Exception {
        int valC = extractTempC(tempObj);
        if (valC >= -50 && valC <= 65) {
            outsideTempC = valC;
            outsideTempKnown = true;
        }
    }

    /* ---- bTres-Grade Multi-Model Power (kW / HP) & Torque (Nm) Engine -- */

    /**
     * Fuses:
     *  (A) 4.0 TFSI Twin-Turbo V8 Thermodynamic Air-Mass Model (MAP * VE(rpm) * rho_T * load)
     *  (B) Slope-Compensated Road-Load & Inertial Virtual Dyno (m*a_sensor + m*(e_i-1)*dv/dt + F_aero + F_roll)
     *  (C) Direct ECU DSI power/torque (uncapped by A & B when tuned)
     */
    private synchronized void computeFusedPowerAndTorque(long now) {
        float vMs = speedKmh / 3.6f;

        /* 1. Effective RPM: live CAN RPM, or mechanical RPM from speed + 8HP90 gear ratio */
        int effRpm = rpm;
        if (effRpm <= 0 && vMs > 1.5f) {
            int g = (gear >= 1 && gear <= 8) ? gear : estimateGearFromSpeed(speedKmh);
            float ratio = GEAR_RATIOS[g] * FINAL_DRIVE;
            effRpm = (int) ((vMs * 60.0f * ratio) / TIRE_CIRC_M);
            if (effRpm < 700) effRpm = 700;
            if (effRpm > 6800) effRpm = 6800;
        }

        /* 2. Kinematic wheel acceleration dv/dt (m/s^2) with low-pass smoothing */
        if (lastPhysicsMs > 0 && now > lastPhysicsMs && now - lastPhysicsMs <= 2000L) {
            float dt = (now - lastPhysicsMs) / 1000.0f;
            float rawDvDt = (vMs - lastPhysicsSpeedMs) / dt;
            if (rawDvDt >= -15.0f && rawDvDt <= 15.0f) {
                smoothedKinAccelMs2 = 0.45f * rawDvDt + 0.55f * smoothedKinAccelMs2;
            }
        } else {
            smoothedKinAccelMs2 = 0.0f;
        }
        lastPhysicsMs = now;
        lastPhysicsSpeedMs = vMs;

        /* 3. Convert longitudinal accelerometer to m/s^2 (auto-detect G vs m/s^2) */
        float sensorAccelMs2 = accelSensorIsMs2 ? longAccelRaw : (longAccelRaw * GRAVITY);
        /* If sensor is in G but exceeded 2.2 m/s^2 earlier, verify consistency with dv/dt */
        if (accelSensorIsMs2 && Math.abs(longAccelRaw) <= 1.6f && Math.abs(smoothedKinAccelMs2) > 3.5f) {
            sensorAccelMs2 = longAccelRaw * GRAVITY;
        }

        /* 4. Model A: 4.0 TFSI V8 Thermodynamic Air-Mass Torque & Power */
        float boostBar = currentBoostGaugeBar();
        float thermoTorqueNm = 0.0f;
        float thermoPowerKw = 0.0f;
        if (effRpm >= 600 && (boostBar >= 0.0f || throttlePct >= 0)) {
            float mapBar = 1.013f + (boostBar > 0.0f ? boostBar : 0.0f);
            /* Load factor from throttle & boost when partially throttled */
            float loadFactor = 1.0f;
            if (throttlePct >= 0 && throttlePct < 85 && boostBar < 0.15f) {
                loadFactor = 0.12f + 0.88f * (throttlePct / 85.0f);
            }
            /* Volumetric * thermal efficiency curve of the 3993cc 4.0 TFSI V8:
             * At 1.20 bar boost (MAP = 2.213 bar):
             *   1750..5500 RPM -> 700 Nm (316.3 Nm per bar MAP)
             *   6000 RPM       -> 656 Nm -> 412 kW / 560 PS (296.4 Nm per bar MAP)
             *   6600 RPM       -> 596 Nm -> 412 kW / 560 PS (269.3 Nm per bar MAP) */
            float nmPerBarMap;
            if (effRpm < 1750) {
                nmPerBarMap = 235.0f + (effRpm - 600) * (81.3f / 1150.0f);
            } else if (effRpm <= 5400) {
                nmPerBarMap = 316.3f;
            } else if (effRpm <= 6000) {
                nmPerBarMap = 316.3f - (effRpm - 5400) * (19.9f / 600.0f);
            } else {
                nmPerBarMap = 296.4f - (effRpm - 6000) * (27.1f / 600.0f);
            }
            if (nmPerBarMap < 200.0f) nmPerBarMap = 200.0f;

            /* Ambient air density temperature correction (ISO 1585 / DIN 70020 reference 20C = 293.15K) */
            float tempK = 273.15f + (outsideTempKnown ? (float) outsideTempC : 20.0f);
            float densityCorr = (float) Math.sqrt(293.15f / tempK);

            thermoTorqueNm = mapBar * nmPerBarMap * loadFactor * densityCorr;
            if (braking && throttlePct <= 5) {
                thermoTorqueNm = 0.0f;
            }
            thermoPowerKw = (thermoTorqueNm * effRpm) / 9549.2968f;
        }

        /* 5. Model B: Slope-Compensated Virtual Dyno (Road-Load + Rotational & Linear Inertia) */
        float physPowerKw = 0.0f;
        boolean physValid = false;
        if (!braking && vMs >= 4.0f && (smoothedKinAccelMs2 > 0.35f || sensorAccelMs2 > 0.5f)) {
            int g = (gear >= 1 && gear <= 8) ? gear : estimateGearFromSpeed(speedKmh);
            float ei = GEAR_INERTIA[g];
            /* If ESP longitudinal accelerometer is active, a_sensor = dv/dt + g*sin(theta),
             * so m*a_sensor + m*(e_i - 1)*dv/dt automatically compensates for road grade theta! */
            float baseAccelMs2 = (Math.abs(sensorAccelMs2) > 0.05f) ? sensorAccelMs2 : smoothedKinAccelMs2;
            float kinAccelMs2 = (smoothedKinAccelMs2 > 0.2f) ? smoothedKinAccelMs2 : baseAccelMs2;
            float fInertSlope = RS7_MASS_KG * baseAccelMs2 + RS7_MASS_KG * (ei - 1.0f) * kinAccelMs2;

            /* Ambient air density rho = P / (R * T) */
            float tempK = 273.15f + (outsideTempKnown ? (float) outsideTempC : 20.0f);
            float rho = 101325.0f / (287.05f * tempK);
            float fAero = 0.5f * rho * RS7_CDA * vMs * vMs;
            float fRoll = RS7_MASS_KG * GRAVITY * (RS7_CRR0 + RS7_CRR2 * vMs * vMs);

            float fTotal = fInertSlope + fAero + fRoll;
            if (fTotal > 0.0f) {
                float wheelKw = (fTotal * vMs) / 1000.0f;
                float pumpLoss = QUATTRO_PUMP_LOSS_KW * (effRpm > 0 ? (effRpm / 4500.0f) : 0.7f);
                physPowerKw = (wheelKw / QUATTRO_MESH_EFF) + pumpLoss;
                if (physPowerKw > 0.0f && physPowerKw < 1200.0f) {
                    physValid = true;
                }
            }
        }

        /* 6. Model C: Direct ECU DSI power / torque (cross-checked via shaft identity) */
        float ecuPowerKw = 0.0f;
        if (rawEcuPowerKw > 0) {
            ecuPowerKw = (float) rawEcuPowerKw;
        }
        if (rawEcuTorqueNm > 0 && effRpm > 0) {
            float kwFromNm = (rawEcuTorqueNm * effRpm) / 9549.2968f;
            /* If currentOutputPower was unpopulated or clipped below torque*rpm, use torque*rpm */
            if (kwFromNm > ecuPowerKw) {
                ecuPowerKw = kwFromNm;
            }
        }

        /* 7. Sensor Fusion:
         *    - Start from the higher of ECU DSI power and 4.0 TFSI Thermodynamic power
         *      (so tuned Stage 1/2/3 cars above the 412 kW / 700 Nm gateway ceiling are never clipped).
         *    - Under real road acceleration (physValid && vMs >= 7 m/s && throttle/boost active),
         *      blend 55% Thermodynamic/ECU + 45% Slope-Compensated Virtual Dyno. */
        float candidateKw = ecuPowerKw >= thermoPowerKw ? ecuPowerKw : thermoPowerKw;
        if (physValid) {
            if (candidateKw <= 0.0f) {
                candidateKw = physPowerKw;
            } else if (vMs >= 7.0f && (throttlePct >= 60 || boostBar >= 0.4f || kickDown)) {
                candidateKw = 0.55f * candidateKw + 0.45f * physPowerKw;
            }
        }

        /* Exponential moving average filter: fast attack on WOT stomp, smooth decay */
        if (candidateKw <= 1.0f) {
            smoothedPowerKw = 0.0f;
        } else if (smoothedPowerKw <= 1.0f || (candidateKw - smoothedPowerKw > 80.0f && throttlePct >= 80)) {
            smoothedPowerKw = candidateKw;
        } else {
            float alpha = (candidateKw > smoothedPowerKw) ? 0.65f : 0.30f;
            smoothedPowerKw = alpha * candidateKw + (1.0f - alpha) * smoothedPowerKw;
        }

        int finalKw = (int) (smoothedPowerKw + 0.5f);
        int finalHp = (int) (smoothedPowerKw * 1.3596216f + 0.5f); /* Metric PS (Audi spec: 412 kW = 560 HP) */
        int finalNm = 0;
        if (effRpm >= 600 && smoothedPowerKw > 0.0f) {
            finalNm = (int) ((smoothedPowerKw * 9549.2968f) / effRpm + 0.5f);
        } else if (rawEcuTorqueNm > 0) {
            finalNm = rawEcuTorqueNm;
        }
        if (rawEcuTorqueNm > finalNm) {
            finalNm = rawEcuTorqueNm;
        }

        fusedPowerKw = finalKw;
        fusedPowerHp = finalHp;
        fusedTorqueNm = finalNm;
        if (finalHp > peakPowerHp) peakPowerHp = finalHp;
        if (finalNm > peakTorqueNm) peakTorqueNm = finalNm;
    }

    private static int estimateGearFromSpeed(float spdKmh) {
        if (spdKmh < 45.0f) return 1;
        if (spdKmh < 78.0f) return 2;
        if (spdKmh < 120.0f) return 3;
        if (spdKmh < 155.0f) return 4;
        if (spdKmh < 200.0f) return 5;
        if (spdKmh < 255.0f) return 6;
        return 7;
    }

    public int getFusedPowerKw() {
        return fusedPowerKw;
    }

    public int getFusedPowerHp() {
        return fusedPowerHp;
    }

    public int getFusedTorqueNm() {
        return fusedTorqueNm;
    }

    private static float extractSpeedKmh(Object speedObj) {
        if (speedObj == null) return -1.0f;
        try {
            Class c = speedObj.getClass();
            int state = c.getField("speedValueState").getInt(speedObj);
            if (state != 1 && state != 2) return -1.0f;
            float val = c.getField("speedValue").getFloat(speedObj);
            int unit = c.getField("speedUnit").getInt(speedObj);
            if (val < 0.0f || val > 400.0f) return -1.0f;
            if (unit == 1) val = val * 1.60934f;
            return val;
        } catch (Throwable t) {
            return -1.0f;
        }
    }

    private static int extractTempC(Object tempObj) {
        if (tempObj == null) return -999;
        try {
            Class c = tempObj.getClass();
            int state = c.getField("state").getInt(tempObj);
            if (state != 1) return -999;
            float val = c.getField("temperatureValue").getFloat(tempObj);
            int unit = c.getField("temperatureUnit").getInt(tempObj);
            if (unit == 1) {
                val = (val - 32.0f) * 5.0f / 9.0f;
            }
            return (int) (val >= 0.0f ? val + 0.5f : val - 0.5f);
        } catch (Throwable t) {
            return -999;
        }
    }

    /* ---- 0-100 km/h & 100-200 km/h Auto-Timer ------------------------- */

    private synchronized void updateTimers(long now, float spd) {
        float boost = currentBoostGaugeBar();
        float gVal = accelSensorIsMs2 ? (longAccelRaw / GRAVITY) : longAccelRaw;
        if (gVal < 0.0f) gVal = -gVal;

        if (spd <= 1.5f) {
            armed0to100 = true;
            running0to100 = false;
            running100to200 = false;
            prevSpeedKmh = spd;
            prevSpeedMs = now;
            return;
        }

        if (armed0to100 && !running0to100 && spd > 1.5f) {
            if (spd < 25.0f) {
                running0to100 = true;
                start0to100Ms = (prevSpeedMs > 0 && now - prevSpeedMs < 1000L) ? prevSpeedMs : now;
                peakBoostDuringRun = boost;
                peakGDuringRun = gVal;
                peakHpDuringRun = fusedPowerHp;
                peakNmDuringRun = fusedTorqueNm;
                last100to200Centis = -1;
            }
            armed0to100 = false;
        }

        if (running0to100) {
            if (boost > peakBoostDuringRun) peakBoostDuringRun = boost;
            if (gVal > peakGDuringRun) peakGDuringRun = gVal;
            if (fusedPowerHp > peakHpDuringRun) peakHpDuringRun = fusedPowerHp;
            if (fusedTorqueNm > peakNmDuringRun) peakNmDuringRun = fusedTorqueNm;
            long elapsed = now - start0to100Ms;
            if (elapsed > 15000L || (spd < prevSpeedKmh - 5.0f)) {
                running0to100 = false;
            } else if (spd >= 100.0f) {
                long crossMs = interpolateCrossing(prevSpeedMs, prevSpeedKmh, now, spd, 100.0f);
                long durMs = crossMs - start0to100Ms;
                if (durMs > 1500L && durMs < 15000L) {
                    last0to100Centis = (int) ((durMs + 5L) / 10L);
                    showResultUntil = now + RESULT_HOLD_MS;
                    running100to200 = true;
                    start100to200Ms = crossMs;
                }
                running0to100 = false;
            }
        } else if (!running100to200 && prevSpeedKmh > 60.0f && prevSpeedKmh < 100.0f && spd >= 100.0f) {
            if (throttlePct >= 70 || gVal >= 0.15f || (now > prevSpeedMs && (spd - prevSpeedKmh) * 1000.0f / (now - prevSpeedMs) > 6.0f)) {
                long crossMs = interpolateCrossing(prevSpeedMs, prevSpeedKmh, now, spd, 100.0f);
                running100to200 = true;
                start100to200Ms = crossMs;
                peakBoostDuringRun = boost;
                peakHpDuringRun = fusedPowerHp;
                peakNmDuringRun = fusedTorqueNm;
            }
        }

        if (running100to200) {
            if (boost > peakBoostDuringRun) peakBoostDuringRun = boost;
            if (fusedPowerHp > peakHpDuringRun) peakHpDuringRun = fusedPowerHp;
            if (fusedTorqueNm > peakNmDuringRun) peakNmDuringRun = fusedTorqueNm;
            long elapsed = now - start100to200Ms;
            if (elapsed > 25000L || spd < 95.0f || spd < prevSpeedKmh - 5.0f) {
                running100to200 = false;
            } else if (spd >= 200.0f) {
                long crossMs = interpolateCrossing(prevSpeedMs, prevSpeedKmh, now, spd, 200.0f);
                long durMs = crossMs - start100to200Ms;
                if (durMs > 2500L && durMs < 25000L) {
                    last100to200Centis = (int) ((durMs + 5L) / 10L);
                    showResultUntil = now + RESULT_HOLD_MS + 3000L;
                }
                running100to200 = false;
            }
        }

        prevSpeedKmh = spd;
        prevSpeedMs = now;
    }

    private static long interpolateCrossing(long t0, float v0, long t1, float v1, float target) {
        if (t0 <= 0 || t1 <= t0 || v1 <= v0 || target <= v0 || target >= v1) {
            return t1;
        }
        float frac = (target - v0) / (v1 - v0);
        return t0 + (long) ((t1 - t0) * frac);
    }

    /* ---- Periodic step called from GfxKeep ---------------------------- */

    public boolean step(long now, Object clusterService, boolean rgdActive, int rgdDistM, boolean disabled) {
        if (disabled) {
            if (hudActive) {
                hudActive = false;
            }
            return false;
        }
        connectIfNeeded(now);
        pollGpsSpeedFallback(now);

        if (now - lastTelemetryLog >= LOG_INTERVAL_MS && (highFreqKnown || midFreqKnown || oilTempKnown)) {
            lastTelemetryLog = now;
            GfxKeep.logTelemetry(now, new StringBuffer(192)
                    .append("telemetry: rpm=").append(rpm)
                    .append(" boost=").append(format1Dec(currentBoostGaugeBar())).append("bar(").append(relBoostPct).append("%)")
                    .append(" fused=").append(fusedPowerKw).append("kW/").append(fusedPowerHp).append("HP/").append(fusedTorqueNm).append("Nm")
                    .append(" peak=").append(peakPowerHp).append("HP/").append(peakTorqueNm).append("Nm")
                    .append(" rawEcu=").append(rawEcuPowerKw).append("kW/").append(rawEcuTorqueNm).append("Nm")
                    .append(" gear=").append(gearName())
                    .append(" oil=").append(oilTempC).append("C")
                    .append(" box=").append(gearboxOilC).append("C")
                    .append(" spd=").append((int) speedKmh).append("km/h").toString());
        }

        /* HUD display output from HudTelemetry is disabled per user preference so that
         * ONLY CarPlay Route Guidance ever writes to or clears HUD Frame 5.
         * Passive DSI listener & periodic telemetry logging above remain active for diagnostics. */
        if (hudActive) {
            hudActive = false;
        }
        return false;
    }

    private void pushToHud(Object cs, boolean starting, String topText, String mainText, int bar) {
        if (cs == null) return;
        GfxKeep.pushHudFrame5(cs, starting, topText, false, "", mainText, bar);
    }

    private float currentBoostGaugeBar() {
        if (absBoostBar >= 1.0f) {
            return absBoostBar - 1.0f;
        }
        if (absBoostBar > 0.0f) {
            return absBoostBar;
        }
        if (relBoostPct >= 0) {
            float ceil = maxBoostBar > 0.5f ? maxBoostBar : 1.6f;
            return (relBoostPct * ceil) / 100.0f;
        }
        return -1.0f;
    }

    private String gearName() {
        String prefix = "";
        if (transMode == 5 || transMode == 2) prefix = "S";
        else if (transMode == 6 || transMode == 3) prefix = "M";
        else if (transMode == 4 || transMode == 1) prefix = "D";
        else if (gear > 0) prefix = "G";
        if (gear > 0 && gear <= 8) {
            return prefix + gear;
        }
        return prefix;
    }

    private void pollGpsSpeedFallback(long now) {
        if (canSpeedActive && (now - prevSpeedMs) < 1500L) {
            return;
        }
        try {
            Object dsiResp = Class.forName("de.audi.tghu.navi.app.command.DSIResponseContainer")
                    .getMethod("getInstance", new Class[0]).invoke(null, new Object[0]);
            Object pos = dsiResp.getClass().getMethod("getSoPosPosition", new Class[0])
                    .invoke(dsiResp, new Object[0]);
            if (pos != null) {
                int spd = pos.getClass().getField("speed").getInt(pos);
                if (spd >= 0 && spd <= 400) {
                    speedKmh = (float) spd;
                    speedKnown = true;
                    computeFusedPowerAndTorque(now);
                    updateTimers(now, (float) spd);
                }
            }
        } catch (Throwable ignored) {
        }
    }

    private void connectIfNeeded(long now) {
        if ((vehicleStatesBound && carKombiBound) || now - lastConnectAttempt < CONNECT_RETRY_MS) {
            return;
        }
        lastConnectAttempt = now;
        try {
            Object fw = Class.forName("de.audi.tghu.navi.app.Navigation")
                    .getMethod("getFramework", new Class[0]).invoke(null, new Object[0]);
            if (fw == null) return;
            Class fwClass = Class.forName("de.audi.atip.base.IFrameworkAccess");
            Object bc = fwClass.getMethod("getBundleCxt", new Class[0]).invoke(fw, new Object[0]);
            if (bc == null) return;
            Class bcClass = Class.forName("org.osgi.framework.BundleContext");
            Class srClass = Class.forName("org.osgi.framework.ServiceReference");
            Class dsiListenerClass = Class.forName("org.dsi.ifc.base.DSIListener");
            Class strClass = "".getClass();
            Method getRef = bcClass.getMethod("getServiceReference", new Class[] {strClass});
            Method getSvc = bcClass.getMethod("getService", new Class[] {srClass});

            if (!vehicleStatesBound) {
                try {
                    String vsName = "org.dsi.ifc.carvehiclestates.DSICarVehicleStates";
                    String vsLName = "org.dsi.ifc.carvehiclestates.DSICarVehicleStatesListener";
                    Object ref = getRef.invoke(bc, new Object[] {vsName});
                    if (ref == null) {
                        fwClass.getMethod("startDSIService", new Class[] {strClass, Integer.TYPE})
                                .invoke(fw, new Object[] {vsName, new Integer(0)});
                        ref = getRef.invoke(bc, new Object[] {vsName});
                    }
                    if (ref != null) {
                        Object vsDsi = getSvc.invoke(bc, new Object[] {ref});
                        if (vsDsi != null) {
                            Class vsLClass = Class.forName(vsLName);
                            Object proxy = Proxy.newProxyInstance(vsLClass.getClassLoader(),
                                    new Class[] {vsLClass}, this);
                            registerOsgiListener(bc, bcClass, strClass, vsLName, proxy);
                            int[] attrs = new int[] {11, 12, 13, 14, 15, 16, 17};
                            vsDsi.getClass().getMethod("setNotification", new Class[] {attrs.getClass(), dsiListenerClass})
                                    .invoke(vsDsi, new Object[] {attrs, proxy});
                            try {
                                vsDsi.getClass().getMethod("setCarMenuState", new Class[] {Boolean.TYPE})
                                        .invoke(vsDsi, new Object[] {new Boolean(true)});
                            } catch (Throwable ignored) {
                            }
                            vehicleStatesBound = true;
                            GfxKeep.logTelemetry(now, "HudTelemetry: bound DSICarVehicleStates (attrs 11..17, setCarMenuState=true)");
                        }
                    }
                } catch (Throwable t) {
                    GfxKeep.logTelemetry(now, "HudTelemetry DSICarVehicleStates bind note: " + t);
                }
            }

            if (!carKombiBound) {
                try {
                    String ckName = "org.dsi.ifc.carkombi.DSICarKombi";
                    String ckLName = "org.dsi.ifc.carkombi.DSICarKombiListener";
                    Object ckDsi = null;
                    try {
                        Object nav = Class.forName("de.audi.tghu.navi.app.Navigation")
                                .getMethod("getInstance", new Class[0]).invoke(null, new Object[0]);
                        Object navKombiL = nav.getClass().getMethod("getDsiCarKombiListener", new Class[0])
                                .invoke(nav, new Object[0]);
                        if (navKombiL != null) {
                            ckDsi = navKombiL.getClass().getMethod("getDSI", new Class[0])
                                    .invoke(navKombiL, new Object[0]);
                        }
                    } catch (Throwable ignored) {
                    }
                    if (ckDsi == null) {
                        Object ref = getRef.invoke(bc, new Object[] {ckName});
                        if (ref != null) {
                            ckDsi = getSvc.invoke(bc, new Object[] {ref});
                        }
                    }
                    if (ckDsi != null) {
                        Class ckLClass = Class.forName(ckLName);
                        Object proxy = Proxy.newProxyInstance(ckLClass.getClassLoader(),
                                new Class[] {ckLClass}, this);
                        registerOsgiListener(bc, bcClass, strClass, ckLName, proxy);
                        int[] attrs = new int[] {4, 30, 31, 63, 64, 65, 82};
                        ckDsi.getClass().getMethod("setNotification", new Class[] {attrs.getClass(), dsiListenerClass})
                                .invoke(ckDsi, new Object[] {attrs, proxy});
                        carKombiBound = true;
                        GfxKeep.logTelemetry(now, "HudTelemetry: bound DSICarKombi (attrs 4,30,31,63,64,65,82)");
                    }
                } catch (Throwable t) {
                    GfxKeep.logTelemetry(now, "HudTelemetry DSICarKombi bind note: " + t);
                }
            }
        } catch (Throwable ignored) {
        }
    }

    private static void registerOsgiListener(Object bc, Class bcClass, Class strClass, String listenerName, Object proxy) {
        try {
            Hashtable props = new Hashtable();
            props.put("DEVICE_NAME", listenerName);
            props.put("DEVICE_INSTANCE", new Integer(0));
            Class dictClass = Class.forName("java.util.Dictionary");
            Class objClass = Class.forName("java.lang.Object");
            bcClass.getMethod("registerService", new Class[] {strClass, objClass, dictClass})
                    .invoke(bc, new Object[] {listenerName, proxy, props});
        } catch (Throwable ignored) {
        }
    }

    private static String formatCentis(int centis) {
        if (centis < 0) centis = 0;
        int sec = centis / 100;
        int rem = centis % 100;
        return sec + "." + (rem < 10 ? "0" : "") + rem;
    }

    private static String format1Dec(float v) {
        if (v < 0.0f) return "0.0";
        int t10 = (int) (v * 10.0f + 0.5f);
        return (t10 / 10) + "." + (t10 % 10);
    }
}
