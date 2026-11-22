package local.clustermap;

/**
 * Maps CarPlay (iAP2) ManeuverType (0..53), JunctionElementExitAngle,
 * JunctionType, and DrivingSide to Audi/BAP mainElement + direction,
 * plus distance bargraph percentage (0..100 or -1).
 *
 * Java 1.2 compatible (class version 46, no StackMapTable, no boxing).
 */
public final class ManeuverMapper {
    public static final int NO_SYMBOL = 0;
    public static final int NO_INFO = 1;
    public static final int DIRECTION_TO_DESTINATION = 2;
    public static final int ARRIVED = 3;
    public static final int NEAR_DESTINATION = 4;
    public static final int ARRIVED_DESTINATION_OFFMAP = 5;
    public static final int OFF_ROAD = 6;
    public static final int OFF_MAP = 7;
    public static final int NO_ROUTE = 8;
    public static final int CALC_ROUTE = 9;
    public static final int RECALC_ROUTE = 10;
    public static final int FOLLOW_STREET = 11;
    public static final int CHANGE_LANE = 12;
    public static final int TURN = 13;
    public static final int TURN_ON_MAINROAD = 14;
    public static final int EXIT_RIGHT = 15;
    public static final int EXIT_LEFT = 16;
    public static final int SERVICE_ROAD_RIGHT = 17;
    public static final int SERVICE_ROAD_LEFT = 18;
    public static final int FORK_2 = 19;
    public static final int FORK_3 = 20;
    public static final int ROUNDABOUT_TRS_RIGHT = 21;
    public static final int ROUNDABOUT_TRS_LEFT = 22;
    public static final int SQUARE_TRS_RIGHT = 23;
    public static final int SQUARE_TRS_LEFT = 24;
    public static final int UTURN = 25;
    public static final int EXIT_ROUNDABOUT_TRS_RIGHT = 26;
    public static final int EXIT_ROUNDABOUT_TRS_LEFT = 27;
    public static final int PREPARE_TURN = 28;
    public static final int PREPARE_ROUNDABOUT = 29;
    public static final int PREPARE_SQUARE = 30;
    public static final int PREPARE_U_TURN = 31;
    public static final int MICHIGAN_TURN = 34;
    public static final int DOUBLE_TURN = 35;
    public static final int DIRECTION_TO_WAYPOINT = 38;

    public static final int DIR_STRAIGHT = 0;
    public static final int DIR_SLIGHT_LEFT = 32;
    public static final int DIR_LEFT = 64;
    public static final int DIR_SHARP_LEFT = 96;
    public static final int DIR_UTURN = 128;
    public static final int DIR_SHARP_RIGHT = 160;
    public static final int DIR_RIGHT = 192;
    public static final int DIR_SLIGHT_RIGHT = 224;

    public static final int JUNCTION_NOT_SET = -1;
    public static final int JUNCTION_SINGLE_INTERSECTION = 0;
    public static final int JUNCTION_ROUNDABOUT = 1;

    public static final int DRIVING_SIDE_NOT_SET = -1;
    public static final int DRIVING_SIDE_RIGHT = 0;
    public static final int DRIVING_SIDE_LEFT = 1;

    public static final int MT_NOT_SET = -1;
    public static final int MT_NO_TURN = 0;
    public static final int MT_LEFT_TURN = 1;
    public static final int MT_RIGHT_TURN = 2;
    public static final int MT_STRAIGHT_AHEAD = 3;
    public static final int MT_U_TURN = 4;
    public static final int MT_FOLLOW_ROAD = 5;
    public static final int MT_ENTER_ROUNDABOUT = 6;
    public static final int MT_EXIT_ROUNDABOUT = 7;
    public static final int MT_OFF_RAMP = 8;
    public static final int MT_ON_RAMP = 9;
    public static final int MT_ARRIVE_END_OF_NAVIGATION = 10;
    public static final int MT_START_ROUTE = 11;
    public static final int MT_ARRIVE_AT_DESTINATION = 12;
    public static final int MT_KEEP_LEFT = 13;
    public static final int MT_KEEP_RIGHT = 14;
    public static final int MT_ENTER_FERRY = 15;
    public static final int MT_EXIT_FERRY = 16;
    public static final int MT_CHANGE_FERRY = 17;
    public static final int MT_START_ROUTE_WITH_U_TURN = 18;
    public static final int MT_U_TURN_AT_ROUNDABOUT = 19;
    public static final int MT_LEFT_TURN_AT_END = 20;
    public static final int MT_RIGHT_TURN_AT_END = 21;
    public static final int MT_HIGHWAY_OFF_RAMP_LEFT = 22;
    public static final int MT_HIGHWAY_OFF_RAMP_RIGHT = 23;
    public static final int MT_ARRIVE_DESTINATION_LEFT = 24;
    public static final int MT_ARRIVE_DESTINATION_RIGHT = 25;
    public static final int MT_U_TURN_WHEN_POSSIBLE = 26;
    public static final int MT_ARRIVE_END_OF_DIRECTIONS = 27;
    public static final int MT_ROUNDABOUT_EXIT_1 = 28;
    public static final int MT_ROUNDABOUT_EXIT_19 = 46;
    public static final int MT_SHARP_LEFT_TURN = 47;
    public static final int MT_SHARP_RIGHT_TURN = 48;
    public static final int MT_SLIGHT_LEFT_TURN = 49;
    public static final int MT_SLIGHT_RIGHT_TURN = 50;
    public static final int MT_CHANGE_HIGHWAY = 51;
    public static final int MT_CHANGE_HIGHWAY_LEFT = 52;
    public static final int MT_CHANGE_HIGHWAY_RIGHT = 53;

    private static final int[] DIR16 = {
        128, 112, 96, 80, 64, 48, 32, 16, 0, 240, 224, 208, 192, 176, 160, 144, 128
    };

    private ManeuverMapper() {
    }

    public static int[] map(int maneuverType, int turnAngle, int junctionType, int drivingSide,
                            boolean anglePresent) {
        if (!anglePresent) {
            turnAngle = 1000;
        }
        if (junctionType == JUNCTION_NOT_SET) {
            junctionType = JUNCTION_SINGLE_INTERSECTION;
        }
        int mainElement;
        int direction;

        if (maneuverType == MT_NOT_SET) {
            return new int[] { FOLLOW_STREET, DIR_STRAIGHT };
        }
        if (maneuverType == MT_NO_TURN || maneuverType == MT_FOLLOW_ROAD) {
            return new int[] { FOLLOW_STREET, DIR_STRAIGHT };
        }
        if (maneuverType == MT_ARRIVE_END_OF_NAVIGATION
                || maneuverType == MT_ARRIVE_AT_DESTINATION
                || maneuverType == MT_ARRIVE_END_OF_DIRECTIONS) {
            return new int[] { ARRIVED, DIR_STRAIGHT };
        }
        if (maneuverType == MT_CHANGE_HIGHWAY_LEFT) {
            return new int[] { CHANGE_LANE, DIR_LEFT };
        }
        if (maneuverType == MT_CHANGE_HIGHWAY_RIGHT) {
            return new int[] { CHANGE_LANE, DIR_RIGHT };
        }
        if (maneuverType == MT_ENTER_FERRY || maneuverType == MT_CHANGE_FERRY) {
            return new int[] { FOLLOW_STREET, DIR_STRAIGHT };
        }
        if (maneuverType == MT_START_ROUTE
                || maneuverType == MT_EXIT_FERRY
                || maneuverType == MT_CHANGE_HIGHWAY) {
            return new int[] { TURN, directionFromTurnAngle(turnAngle) };
        }
        if (maneuverType == MT_U_TURN_AT_ROUNDABOUT) {
            mainElement = (drivingSide == DRIVING_SIDE_LEFT) ? ROUNDABOUT_TRS_LEFT : ROUNDABOUT_TRS_RIGHT;
            return new int[] { mainElement, DIR_UTURN };
        }
        if (maneuverType == MT_ENTER_ROUNDABOUT) {
            direction = (drivingSide == DRIVING_SIDE_LEFT) ? DIR_LEFT : DIR_RIGHT;
            direction = applyDsiNavBapDirectionOverride(maneuverType, direction);
            return new int[] { TURN, direction };
        }
        /* Roundabout exit maneuver types (7, 28..46) should map to roundabout icons
         * whether or not the app explicitly set junctionType=1. */
        if (maneuverType == MT_EXIT_ROUNDABOUT) {
            mainElement = (drivingSide == DRIVING_SIDE_LEFT) ? EXIT_ROUNDABOUT_TRS_LEFT : EXIT_ROUNDABOUT_TRS_RIGHT;
            direction = (drivingSide == DRIVING_SIDE_LEFT) ? DIR_LEFT : DIR_RIGHT;
            return new int[] { mainElement, direction };
        }
        if (maneuverType >= MT_ROUNDABOUT_EXIT_1 && maneuverType <= MT_ROUNDABOUT_EXIT_19) {
            mainElement = (drivingSide == DRIVING_SIDE_LEFT) ? ROUNDABOUT_TRS_LEFT : ROUNDABOUT_TRS_RIGHT;
            direction = directionFromAngle16(turnAngle, maneuverType - MT_ROUNDABOUT_EXIT_1 + 1, drivingSide);
            return new int[] { mainElement, direction };
        }
        if (junctionType != JUNCTION_SINGLE_INTERSECTION) {
            return new int[] { NO_INFO, DIR_STRAIGHT };
        }

        switch (maneuverType) {
            case MT_STRAIGHT_AHEAD:
                mainElement = TURN;
                direction = DIR_STRAIGHT;
                break;
            case MT_LEFT_TURN:
                mainElement = TURN;
                direction = DIR_LEFT;
                break;
            case MT_RIGHT_TURN:
                mainElement = TURN;
                direction = DIR_RIGHT;
                break;
            case MT_SLIGHT_LEFT_TURN:
            case MT_KEEP_LEFT:
                mainElement = TURN;
                direction = DIR_SLIGHT_LEFT;
                break;
            case MT_SLIGHT_RIGHT_TURN:
            case MT_KEEP_RIGHT:
                mainElement = TURN;
                direction = DIR_SLIGHT_RIGHT;
                break;
            case MT_SHARP_LEFT_TURN:
                mainElement = TURN;
                direction = DIR_SHARP_LEFT;
                break;
            case MT_SHARP_RIGHT_TURN:
                mainElement = TURN;
                direction = DIR_SHARP_RIGHT;
                break;
            case MT_U_TURN:
            case MT_START_ROUTE_WITH_U_TURN:
            case MT_U_TURN_WHEN_POSSIBLE:
                mainElement = UTURN;
                if (hasDirectionalTurnAngle(turnAngle)) {
                    direction = (turnAngle < 0) ? DIR_LEFT : DIR_RIGHT;
                } else {
                    direction = (drivingSide == DRIVING_SIDE_LEFT) ? DIR_RIGHT : DIR_LEFT;
                }
                break;
            case MT_OFF_RAMP:
            case MT_ON_RAMP:
                mainElement = TURN;
                direction = rampGoesLeft(turnAngle, drivingSide) ? DIR_SLIGHT_LEFT : DIR_SLIGHT_RIGHT;
                break;
            case MT_HIGHWAY_OFF_RAMP_LEFT:
                mainElement = TURN;
                direction = DIR_SLIGHT_LEFT;
                break;
            case MT_HIGHWAY_OFF_RAMP_RIGHT:
                mainElement = TURN;
                direction = DIR_SLIGHT_RIGHT;
                break;
            case MT_ARRIVE_DESTINATION_LEFT:
            case MT_ARRIVE_DESTINATION_RIGHT:
                mainElement = ARRIVED;
                direction = (maneuverType == MT_ARRIVE_DESTINATION_LEFT) ? DIR_LEFT : DIR_RIGHT;
                break;
            case MT_LEFT_TURN_AT_END:
                mainElement = TURN;
                direction = dirFromEndOfRoadAngleLeft(turnAngle);
                break;
            case MT_RIGHT_TURN_AT_END:
                mainElement = TURN;
                direction = dirFromEndOfRoadAngleRight(turnAngle);
                break;
            default:
                mainElement = FOLLOW_STREET;
                direction = DIR_STRAIGHT;
                break;
        }
        direction = applyDsiNavBapDirectionOverride(maneuverType, direction);
        return new int[] { mainElement, direction };
    }

    /**
     * Compute distance bargraph percentage (0..100) or -1 if outside countdown window.
     */
    public static int computeBargraph(int maneuverType, int distM, boolean distPresent, int stepDistM) {
        if (!distPresent || distM < 0) {
            return -1;
        }
        if (maneuverType == MT_NO_TURN || maneuverType == MT_FOLLOW_ROAD || maneuverType == MT_NOT_SET) {
            return -1;
        }
        int threshold = isHighwayManeuver(maneuverType) ? 1000 : 300;
        if (stepDistM > 0 && stepDistM < threshold) {
            threshold = stepDistM;
        }
        if (threshold <= 0 || distM > threshold) {
            return -1;
        }
        int pct = ((threshold - distM) * 100) / threshold;
        if (pct < 0) pct = 0;
        if (pct > 100) pct = 100;
        return pct;
    }

    /**
     * Synthesize a native C7.5 DDP2 RGI maneuver descriptor stream (short[]) for
     * DSIDDP20Controller.setManeuver(5, rgiStream, true) on the C7.5 RS7 HUD/cluster.
     *
     * Captured native RGIString format on MHI2_ER_AU57x_K3663:
     *   - Simple maneuver / calculation: [mainElement, direction] (e.g. [9, 144])
     *   - Turn / roundabout with side-street or exit ray after 0xFFFF (-1) separator:
     *     [mainElement, direction, -1, sideOrExit] (e.g. [13, 192, -1, 64])
     */
    public static short[] buildDdp2RgiStream(int mainElement, int direction, int maneuverType) {
        int dir = direction & 0xFF;
        if (maneuverType >= MT_ROUNDABOUT_EXIT_1 && maneuverType <= MT_ROUNDABOUT_EXIT_19) {
            return new short[] {
                (short) mainElement,
                (short) dir,
                (short) -1,
                (short) (maneuverType - MT_ROUNDABOUT_EXIT_1 + 1)
            };
        }
        return new short[] {
            (short) mainElement,
            (short) dir
        };
    }

    /**
     * Format a compact HUD turn indicator label from mapped mainElement, direction,
     * raw maneuverType, and exitInfo so the windshield HUD always displays a clear
     * directional turn indicator on Cell 1 (distance to maneuver) even when native
     * Audi navigation RGI bitstreams are not active.
     */
    public static String formatHudTurnPrefix(int mainElement, int direction, int maneuverType, String exitInfo) {
        if (mainElement == ARRIVED || mainElement == NEAR_DESTINATION || mainElement == ARRIVED_DESTINATION_OFFMAP) {
            if (direction == DIR_LEFT) return "ARR L";
            if (direction == DIR_RIGHT) return "ARR R";
            return "ARRIVE";
        }
        if (mainElement == RECALC_ROUTE || mainElement == CALC_ROUTE) {
            return "RECALC";
        }
        if (mainElement == UTURN || mainElement == PREPARE_U_TURN
                || maneuverType == MT_U_TURN
                || maneuverType == MT_START_ROUTE_WITH_U_TURN
                || maneuverType == MT_U_TURN_WHEN_POSSIBLE) {
            return "U-TURN";
        }
        if (mainElement == ROUNDABOUT_TRS_RIGHT || mainElement == ROUNDABOUT_TRS_LEFT
                || mainElement == EXIT_ROUNDABOUT_TRS_RIGHT || mainElement == EXIT_ROUNDABOUT_TRS_LEFT
                || mainElement == PREPARE_ROUNDABOUT
                || maneuverType == MT_ENTER_ROUNDABOUT
                || maneuverType == MT_EXIT_ROUNDABOUT
                || maneuverType == MT_U_TURN_AT_ROUNDABOUT
                || (maneuverType >= MT_ROUNDABOUT_EXIT_1 && maneuverType <= MT_ROUNDABOUT_EXIT_19)) {
            if (maneuverType >= MT_ROUNDABOUT_EXIT_1 && maneuverType <= MT_ROUNDABOUT_EXIT_19) {
                return "RND EX" + (maneuverType - MT_ROUNDABOUT_EXIT_1 + 1);
            }
            if (exitInfo != null && exitInfo.length() > 0 && exitInfo.length() <= 4) {
                return "RND " + exitInfo;
            }
            return "RND";
        }
        if (maneuverType == MT_OFF_RAMP || maneuverType == MT_HIGHWAY_OFF_RAMP_LEFT || maneuverType == MT_HIGHWAY_OFF_RAMP_RIGHT
                || mainElement == EXIT_RIGHT || mainElement == EXIT_LEFT) {
            if (direction >= 16 && direction <= 112) {
                return "EXIT L";
            }
            return "EXIT R";
        }
        if (maneuverType == MT_ON_RAMP || maneuverType == MT_CHANGE_HIGHWAY
                || maneuverType == MT_CHANGE_HIGHWAY_LEFT || maneuverType == MT_CHANGE_HIGHWAY_RIGHT
                || mainElement == CHANGE_LANE) {
            if (direction >= 16 && direction <= 112) {
                return "KEEP L";
            }
            if (direction >= 144 && direction <= 240) {
                return "KEEP R";
            }
            return "MERGE";
        }
        if (maneuverType == MT_KEEP_LEFT) {
            return "KEEP L";
        }
        if (maneuverType == MT_KEEP_RIGHT) {
            return "KEEP R";
        }
        if (direction == DIR_UTURN) {
            return "U-TURN";
        }
        if (direction >= 80 && direction <= 112) {
            return "<< L";
        }
        if (direction >= 48 && direction < 80) {
            return "<- L";
        }
        if (direction >= 16 && direction < 48) {
            return "\\ L";
        }
        if (direction >= 144 && direction <= 176) {
            return "R >>";
        }
        if (direction > 176 && direction <= 208) {
            return "R ->";
        }
        if (direction > 208 && direction <= 240) {
            return "R /";
        }
        return "^";
    }

    public static boolean isHighwayManeuver(int maneuverType) {
        return maneuverType == MT_OFF_RAMP
                || maneuverType == MT_ON_RAMP
                || maneuverType == MT_HIGHWAY_OFF_RAMP_LEFT
                || maneuverType == MT_HIGHWAY_OFF_RAMP_RIGHT
                || maneuverType == MT_CHANGE_HIGHWAY
                || maneuverType == MT_CHANGE_HIGHWAY_LEFT
                || maneuverType == MT_CHANGE_HIGHWAY_RIGHT;
    }

    private static boolean hasDirectionalTurnAngle(int turnAngle) {
        return turnAngle != 0 && turnAngle != 1000 && turnAngle != -1000;
    }

    private static boolean rampGoesLeft(int turnAngle, int drivingSide) {
        if (hasDirectionalTurnAngle(turnAngle)) return turnAngle < 0;
        return drivingSide == DRIVING_SIDE_LEFT;
    }

    private static int applyDsiNavBapDirectionOverride(int maneuverType, int dir) {
        if (maneuverType == MT_ENTER_ROUNDABOUT
                || maneuverType == MT_EXIT_ROUNDABOUT
                || maneuverType == MT_U_TURN_AT_ROUNDABOUT
                || maneuverType == MT_U_TURN
                || maneuverType == MT_START_ROUTE_WITH_U_TURN
                || maneuverType == MT_U_TURN_WHEN_POSSIBLE
                || (maneuverType >= MT_ROUNDABOUT_EXIT_1 && maneuverType <= MT_ROUNDABOUT_EXIT_19)) {
            return dir;
        }
        if (maneuverType == MT_OFF_RAMP
                || maneuverType == MT_ON_RAMP
                || maneuverType == MT_HIGHWAY_OFF_RAMP_LEFT
                || maneuverType == MT_HIGHWAY_OFF_RAMP_RIGHT
                || maneuverType == MT_KEEP_LEFT
                || maneuverType == MT_KEEP_RIGHT
                || maneuverType == MT_SLIGHT_LEFT_TURN
                || maneuverType == MT_SLIGHT_RIGHT_TURN
                || maneuverType == MT_SHARP_LEFT_TURN
                || maneuverType == MT_SHARP_RIGHT_TURN
                || maneuverType == MT_LEFT_TURN_AT_END
                || maneuverType == MT_RIGHT_TURN_AT_END) {
            return dir;
        }
        if (dir == DIR_SLIGHT_LEFT || dir == DIR_LEFT || dir == DIR_SHARP_LEFT) return DIR_LEFT;
        if (dir == DIR_SLIGHT_RIGHT || dir == DIR_RIGHT || dir == DIR_SHARP_RIGHT) return DIR_RIGHT;
        if (dir == DIR_UTURN) return DIR_UTURN;
        return DIR_STRAIGHT;
    }

    public static int directionFromAngle16(int angle, int exitNumber, int drivingSide) {
        if (angle == 1000 || angle == -1000) {
            /* If iOS app did not supply exit angle for a roundabout exit, estimate
             * from exit 1=right/left (90 deg), exit 2=straight (0 deg), exit 3=left/right. */
            if (exitNumber == 1) {
                return (drivingSide == DRIVING_SIDE_LEFT) ? DIR_LEFT : DIR_RIGHT;
            }
            if (exitNumber == 2) {
                return DIR_STRAIGHT;
            }
            if (exitNumber >= 3) {
                return (drivingSide == DRIVING_SIDE_LEFT) ? DIR_RIGHT : DIR_LEFT;
            }
            return DIR_STRAIGHT;
        }
        int a = angle;
        if (a > 180) a = 180;
        if (a < -180) a = -180;
        int idx = (int) Math.floor(((a + 180) / 22.5) + 0.5);
        if (idx < 0) idx = 0;
        if (idx > 16) idx = 16;
        return DIR16[idx];
    }

    private static int directionFromTurnAngle(int turnAngle) {
        if (turnAngle == 1000 || turnAngle == -1000 || turnAngle == 0) return DIR_STRAIGHT;
        if (turnAngle < -180) return DIR_LEFT;
        if (turnAngle > 180) return DIR_RIGHT;
        int magnitude = (turnAngle < 0) ? -turnAngle : turnAngle;
        if (magnitude <= 22) return DIR_STRAIGHT;
        if (magnitude <= 67) return (turnAngle < 0) ? DIR_SLIGHT_LEFT : DIR_SLIGHT_RIGHT;
        if (magnitude <= 112) return (turnAngle < 0) ? DIR_LEFT : DIR_RIGHT;
        return (turnAngle < 0) ? DIR_SHARP_LEFT : DIR_SHARP_RIGHT;
    }

    private static int dirFromEndOfRoadAngleLeft(int exitAngle) {
        if (exitAngle < 0 && exitAngle >= -180) {
            if (exitAngle >= -67) return DIR_SLIGHT_LEFT;
            if (exitAngle < -112) return DIR_SHARP_LEFT;
        }
        return DIR_LEFT;
    }

    private static int dirFromEndOfRoadAngleRight(int exitAngle) {
        if (exitAngle > 0 && exitAngle <= 180) {
            if (exitAngle <= 67) return DIR_SLIGHT_RIGHT;
            if (exitAngle > 112) return DIR_SHARP_RIGHT;
        }
        return DIR_RIGHT;
    }
}

