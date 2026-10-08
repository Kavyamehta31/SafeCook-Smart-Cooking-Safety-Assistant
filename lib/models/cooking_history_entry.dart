class CookingHistoryEntry {
  final String recipeId;
  final DateTime completedAt;
  final Duration duration;
  final int stepsCompleted;
  final int totalSteps;
  final bool completed;

  CookingHistoryEntry({
    required this.recipeId,
    required this.completedAt,
    required this.duration,
    required this.stepsCompleted,
    required this.totalSteps,
    this.completed = true,
  });

  Map<String, dynamic> toJson() => {
    'recipeId': recipeId,
    'completedAt': completedAt.toIso8601String(),
    'durationMs': duration.inMilliseconds,
    'stepsCompleted': stepsCompleted,
    'totalSteps': totalSteps,
    'completed': completed,
  };

  factory CookingHistoryEntry.fromJson(Map<String, dynamic> json) =>
      CookingHistoryEntry(
        recipeId: json['recipeId'] as String,
        completedAt: DateTime.parse(json['completedAt'] as String),
        duration: Duration(milliseconds: json['durationMs'] as int),
        stepsCompleted: json['stepsCompleted'] as int,
        totalSteps: json['totalSteps'] as int,
        completed: json['completed'] as bool? ?? true,
      );
}
