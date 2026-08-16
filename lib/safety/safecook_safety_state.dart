enum SafeCookSafetyState {
  safe,
  caution,
  distanceAlert,
  gasAlert,
  critical,
  sensorUnavailable,
}

extension SafeCookSafetyStateExt on SafeCookSafetyState {
  // Voice interruption and precedence priority
  // Explicit ordering: critical (5) > gasAlert (4) > distanceAlert (3) > caution (2) > sensorUnavailable (1) > safe (0)
  int get voicePriority {
    switch (this) {
      case SafeCookSafetyState.critical:
        return 5;
      case SafeCookSafetyState.gasAlert:
        return 4;
      case SafeCookSafetyState.distanceAlert:
        return 3;
      case SafeCookSafetyState.caution:
        return 2;
      case SafeCookSafetyState.sensorUnavailable:
        return 1;
      case SafeCookSafetyState.safe:
        return 0;
    }
  }

  // Severity represents the seriousness of the state
  int get severity {
    switch (this) {
      case SafeCookSafetyState.sensorUnavailable:
        return 5; // Serious because system cannot verify safety
      case SafeCookSafetyState.critical:
        return 4;
      case SafeCookSafetyState.gasAlert:
        return 3;
      case SafeCookSafetyState.distanceAlert:
        return 2;
      case SafeCookSafetyState.caution:
        return 1;
      case SafeCookSafetyState.safe:
        return 0;
    }
  }

  String get explanation {
    switch (this) {
      case SafeCookSafetyState.safe:
        return "Cooking conditions look safe.";
      case SafeCookSafetyState.caution:
        return "Please pay attention to the cooking conditions.";
      case SafeCookSafetyState.distanceAlert:
        return "You are too close to the vessel.";
      case SafeCookSafetyState.gasAlert:
        return "Gas level requires attention.";
      case SafeCookSafetyState.critical:
        return "Immediate safety action required.";
      case SafeCookSafetyState.sensorUnavailable:
        return "Safety sensors are unavailable.";
    }
  }

  String get voiceMessage {
    switch (this) {
      case SafeCookSafetyState.safe:
        return "The cooking environment is now safe again.";
      case SafeCookSafetyState.caution:
        return "Caution. Elevated risk detected.";
      case SafeCookSafetyState.distanceAlert:
        return "Warning. You are too close to the cooking vessel. Please step back.";
      case SafeCookSafetyState.gasAlert:
        return "Warning. The gas level is high. Please check the stove environment.";
      case SafeCookSafetyState.critical:
        return "Critical warning! Please check the stove area immediately.";
      case SafeCookSafetyState.sensorUnavailable:
        return "I've lost connection to the stove sensor. I can no longer verify the cooking safety measurements.";
    }
  }
}
