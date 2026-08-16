import '../services/voice_assistant_service.dart';

class SafeCookSafetyPolicy {
  // SafeCook's current project calibration/policy thresholds.
  // NOTE: These are app-specific safety thresholds derived from empirical 
  // hardware testing on the Samsung Galaxy S23 FE and the HC-05 module,
  // and are NOT universal medical or scientific gas exposure limits.
  static final double gasCautionThreshold = GasCalibration.toPercent(300); // ~29.41%
  static final double gasCriticalThreshold = GasCalibration.toPercent(600); // ~64.71%

  // Distance thresholds (cm)
  static const double distanceCautionThreshold = 30.0;
  static const double distanceCriticalThreshold = 15.0;

  // Hysteresis bands for recovery transitions
  static const double gasHysteresisPercent = 3.0; // must drop below (threshold - 3%)
  static const double distanceHysteresisCm = 2.0; // must increase above (threshold + 2cm)
}
