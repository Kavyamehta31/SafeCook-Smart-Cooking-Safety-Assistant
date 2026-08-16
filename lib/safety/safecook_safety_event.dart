import 'safecook_safety_state.dart';

class SafeCookSafetyEvent {
  final String eventId;
  final SafeCookSafetyState previousState;
  final SafeCookSafetyState currentState;
  final double? gasPercentage;
  final double? chefDistanceCm;
  final List<String> reasons;
  final DateTime timestamp;

  SafeCookSafetyEvent({
    required this.eventId,
    required this.previousState,
    required this.currentState,
    this.gasPercentage,
    this.chefDistanceCm,
    required this.reasons,
    required this.timestamp,
  });
}
