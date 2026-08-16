import 'dart:async';
import 'package:flutter/foundation.dart';
import 'safecook_safety_state.dart';
import 'safecook_safety_event.dart';
import 'safecook_safety_policy.dart';

class SafeCookSafetyEngine {
  static final SafeCookSafetyEngine _instance = SafeCookSafetyEngine._internal();
  factory SafeCookSafetyEngine() => _instance;
  SafeCookSafetyEngine._internal();

  double? _gasPercentage;
  double? _chefDistanceCm;
  bool _isBluetoothConnected = false;
  SafeCookSafetyState _currentState = SafeCookSafetyState.sensorUnavailable;
  
  final List<SafeCookSafetyEvent> _history = [];
  final StreamController<SafeCookSafetyEvent> _eventController = StreamController<SafeCookSafetyEvent>.broadcast(sync: true);

  double? get gasPercentage => _gasPercentage;
  double? get chefDistanceCm => _chefDistanceCm;
  bool get isBluetoothConnected => _isBluetoothConnected;
  SafeCookSafetyState get currentState => _currentState;
  List<SafeCookSafetyEvent> get history => List.unmodifiable(_history);
  Stream<SafeCookSafetyEvent> get onSafetyEvent => _eventController.stream;

  void reset() {
    _gasPercentage = null;
    _chefDistanceCm = null;
    _isBluetoothConnected = false;
    _currentState = SafeCookSafetyState.sensorUnavailable;
    _history.clear();
  }

  SafeCookSafetyEvent updateSensorData({
    double? gasPercentage,
    double? chefDistanceCm,
    required bool isBluetoothConnected,
  }) {
    _gasPercentage = gasPercentage;
    _chefDistanceCm = chefDistanceCm;
    _isBluetoothConnected = isBluetoothConnected;

    final newState = _evaluateNextState();
    
    if (newState != _currentState) {
      final prev = _currentState;
      _currentState = newState;
      
      final reasons = _generateReasons(newState);
      final event = SafeCookSafetyEvent(
        eventId: '${DateTime.now().millisecondsSinceEpoch}_${_history.length}',
        previousState: prev,
        currentState: newState,
        gasPercentage: gasPercentage,
        chefDistanceCm: chefDistanceCm,
        reasons: reasons,
        timestamp: DateTime.now(),
      );

      _history.add(event);
      _eventController.add(event);

      debugPrint('[SafeCook SAFETY]\n'
          'eventId=${event.eventId}\n'
          'previous=${prev.name}\n'
          'current=${newState.name}\n'
          'gas=${gasPercentage?.toStringAsFixed(1) ?? "N/A"}\n'
          'distance=${chefDistanceCm?.toStringAsFixed(1) ?? "N/A"}\n'
          'reason=${reasons.join(", ")}');

      return event;
    }

    return SafeCookSafetyEvent(
      eventId: 'no_change',
      previousState: _currentState,
      currentState: _currentState,
      gasPercentage: gasPercentage,
      chefDistanceCm: chefDistanceCm,
      reasons: [],
      timestamp: DateTime.now(),
    );
  }

  SafeCookSafetyState _evaluateNextState() {
    if (!_isBluetoothConnected) {
      return SafeCookSafetyState.sensorUnavailable;
    }

    final isGasValid = _gasPercentage != null;
    final isDistValid = _chefDistanceCm != null;

    final previous = _currentState;

    // 1. Determine effective critical thresholds (applying hysteresis if recovering)
    final effGasCritical = (previous == SafeCookSafetyState.critical || previous == SafeCookSafetyState.gasAlert)
        ? (SafeCookSafetyPolicy.gasCriticalThreshold - SafeCookSafetyPolicy.gasHysteresisPercent)
        : SafeCookSafetyPolicy.gasCriticalThreshold;

    final effDistCritical = (previous == SafeCookSafetyState.critical || previous == SafeCookSafetyState.distanceAlert)
        ? (SafeCookSafetyPolicy.distanceCriticalThreshold + SafeCookSafetyPolicy.distanceHysteresisCm)
        : SafeCookSafetyPolicy.distanceCriticalThreshold;

    // Check individual critical sensor statuses
    final isGasCritical = isGasValid && _gasPercentage! >= effGasCritical;
    final isDistCritical = isDistValid && _chefDistanceCm! < effDistCritical;

    // 2. Prioritized Multi-Sensor Rules (ensuring unavailable sensors never hide active dangers)
    if (isGasCritical && isDistCritical) {
      return SafeCookSafetyState.critical;
    }
    if (isGasCritical) {
      return SafeCookSafetyState.gasAlert;
    }
    if (isDistCritical) {
      return SafeCookSafetyState.distanceAlert;
    }

    // 3. Handle Sensor Unavailable (if either sensor is invalid/null, and neither is critical)
    if (!isGasValid || !isDistValid) {
      return SafeCookSafetyState.sensorUnavailable;
    }

    // 4. Caution threshold evaluation (with hysteresis)
    final effGasCaution = (previous == SafeCookSafetyState.caution)
        ? (SafeCookSafetyPolicy.gasCautionThreshold - SafeCookSafetyPolicy.gasHysteresisPercent)
        : SafeCookSafetyPolicy.gasCautionThreshold;

    final effDistCaution = (previous == SafeCookSafetyState.caution)
        ? (SafeCookSafetyPolicy.distanceCautionThreshold + SafeCookSafetyPolicy.distanceHysteresisCm)
        : SafeCookSafetyPolicy.distanceCautionThreshold;

    final isGasCaution = _gasPercentage! >= effGasCaution;
    final isDistCaution = _chefDistanceCm! <= effDistCaution;

    if (isGasCaution || isDistCaution) {
      return SafeCookSafetyState.caution;
    }

    // 5. If both sensors are valid and fully below the caution thresholds, it is safe
    return SafeCookSafetyState.safe;
  }

  List<String> _generateReasons(SafeCookSafetyState state) {
    final list = <String>[];
    if (!_isBluetoothConnected) {
      list.add("Bluetooth disconnected");
      return list;
    }
    if (_gasPercentage == null) {
      list.add("Gas sensor invalid or missing");
    } else if (_gasPercentage! >= SafeCookSafetyPolicy.gasCriticalThreshold) {
      list.add("Gas level critical (${_gasPercentage!.toStringAsFixed(1)}%)");
    } else if (_gasPercentage! >= SafeCookSafetyPolicy.gasCautionThreshold) {
      list.add("Gas level caution (${_gasPercentage!.toStringAsFixed(1)}%)");
    }

    if (_chefDistanceCm == null) {
      list.add("Distance sensor invalid or missing");
    } else if (_chefDistanceCm! < SafeCookSafetyPolicy.distanceCriticalThreshold) {
      list.add("Distance critical (${_chefDistanceCm!.toStringAsFixed(1)} cm)");
    } else if (_chefDistanceCm! <= SafeCookSafetyPolicy.distanceCautionThreshold) {
      list.add("Distance caution (${_chefDistanceCm!.toStringAsFixed(1)} cm)");
    }
    return list;
  }
}
