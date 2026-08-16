import '../models/recipe.dart';

// ---------------------------------------------------------------------------
// SafeCookContext — immutable snapshot of app state, passed into handleInput
// on EVERY call so the agent always reads fresh sensor data.
// ---------------------------------------------------------------------------
class SafeCookContext {
  final Recipe? recipe;
  final int currentStepIndex;
  final int totalSteps;
  final int? gasValue;        // raw ADC value from sensor
  final double? gasPercent;   // calibrated 0-100%
  final String? distanceValue; // formatted string e.g. "28.5 cm"
  final double? distanceCm;    // parsed double for arithmetic
  final String safetyState;
  final Duration sessionDuration;
  final bool isCookingActive;
  final bool isBluetoothConnected;
  final String currentConversationState;

  const SafeCookContext({
    this.recipe,
    this.currentStepIndex = 0,
    this.totalSteps = 0,
    this.gasValue,
    this.gasPercent,
    this.distanceValue,
    this.distanceCm,
    required this.safetyState,
    required this.sessionDuration,
    required this.isCookingActive,
    required this.isBluetoothConnected,
    required this.currentConversationState,
  });
}

// ---------------------------------------------------------------------------
// ConversationState — explicit enum for the state machine.
// ---------------------------------------------------------------------------
enum ConversationState {
  idle,             // Wake-word waiting
  selectingRecipe,  // Agent listed recipes, awaiting user selection
  confirmingStart,  // Agent asked "start cooking?", awaiting yes/no
  awaitingReadyConfirm, // Agent read ingredients+safety, asking "ready for step 1?"
  cooking,          // Active cooking session — NO wake word needed
  confirmingEnd,    // Agent asked "end cooking?", awaiting yes/no
}

extension ConversationStateExtension on ConversationState {
  String get name {
    switch (this) {
      case ConversationState.idle:
        return 'idle';
      case ConversationState.selectingRecipe:
        return 'selecting_recipe';
      case ConversationState.confirmingStart:
        return 'confirming_start';
      case ConversationState.awaitingReadyConfirm:
        return 'awaiting_ready';
      case ConversationState.cooking:
        return 'cooking';
      case ConversationState.confirmingEnd:
        return 'confirming_end';
    }
  }

  bool get requiresWakeWord => this == ConversationState.idle;
  bool get isCooking => this == ConversationState.cooking;
  bool get isActive =>
      this != ConversationState.idle;
}

// ---------------------------------------------------------------------------
// SafeCookSessionMemory — single authoritative mutable session state.
// Owned by SafeCookAgent singleton.  Never create a second instance.
// ---------------------------------------------------------------------------
class SafeCookSessionMemory {
  // Conversation FSM
  ConversationState conversationState = ConversationState.idle;

  // Recipe tracking
  Recipe? selectedRecipe;
  List<Recipe> lastRecipeSearchResults = [];

  // Active step index — this is the ONLY source of truth for step position.
  // It is kept in sync with CookingGuidanceScreen._currentStepIndex via tools.
  int currentStepIndex = 0;

  // Session flags
  bool isCookingActive = false;

  // Live sensor snapshot — updated from context on every handleInput call.
  int? gasValue;
  double? gasPercent;
  String? distanceValue;
  double? distanceCm;
  String safetyState = 'STANDBY';
  Duration sessionDuration = Duration.zero;

  // Bluetooth state
  bool isBluetoothConnected = false;

  // Conversational memory
  String? lastUserRequest;
  String? lastAssistantResponse;

  // Pending action for web search (Phase 7 placeholder)
  String? pendingWebQuery;

  void reset() {
    conversationState = ConversationState.idle;
    selectedRecipe = null;
    lastRecipeSearchResults.clear();
    currentStepIndex = 0;
    isCookingActive = false;
    lastUserRequest = null;
    lastAssistantResponse = null;
    pendingWebQuery = null;
    // Sensor state is NOT cleared on reset — it reflects the physical world.
  }

  /// Transition into cooking mode for a specific recipe.
  void startCookingSession(Recipe recipe) {
    selectedRecipe = recipe;
    currentStepIndex = 0;
    isCookingActive = true;
    conversationState = ConversationState.cooking;
  }

  /// Transition out of cooking mode.
  void endCookingSession() {
    isCookingActive = false;
    currentStepIndex = 0;
    conversationState = ConversationState.idle;
    // Keep selectedRecipe so cooking report can still reference it.
  }

  void nextStep() {
    final r = selectedRecipe;
    if (r != null && currentStepIndex < r.steps.length - 1) {
      currentStepIndex++;
    }
  }

  void previousStep() {
    if (currentStepIndex > 0) {
      currentStepIndex--;
    }
  }

  void repeatStep() {
    // remains on same step
  }

  void goToStep(int stepNumber) {
    final r = selectedRecipe;
    if (r != null) {
      currentStepIndex = (stepNumber - 1).clamp(0, r.steps.length - 1);
    }
  }
}
