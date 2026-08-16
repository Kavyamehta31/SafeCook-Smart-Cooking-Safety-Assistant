
class SafeCookTurn {
  final String userUtterance;
  final String assistantResponse;
  final String intent;
  final DateTime timestamp;

  SafeCookTurn({
    required this.userUtterance,
    required this.assistantResponse,
    required this.intent,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'userUtterance': userUtterance,
        'assistantResponse': assistantResponse,
        'intent': intent,
        'timestamp': timestamp.toIso8601String(),
      };
}

class SafeCookConversationMemory {
  static final SafeCookConversationMemory _instance =
      SafeCookConversationMemory._internal();
  factory SafeCookConversationMemory() => _instance;
  SafeCookConversationMemory._internal();

  final List<SafeCookTurn> _history = [];
  final int maxTurns = 20;

  // Track state relating to references
  String? lastMentionedIngredient;
  int? lastSelectedStepIndex;

  List<SafeCookTurn> get history => List.unmodifiable(_history);

  void addTurn(String user, String assistant, String intent) {
    if (_history.length >= maxTurns) {
      _history.removeAt(0);
    }
    _history.add(SafeCookTurn(
      userUtterance: user,
      assistantResponse: assistant,
      intent: intent,
    ));
  }

  void clear() {
    _history.clear();
    lastMentionedIngredient = null;
    lastSelectedStepIndex = null;
  }
}
