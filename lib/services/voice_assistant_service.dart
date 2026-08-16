// ignore_for_file: avoid_print
import 'voice_service.dart';
import '../models/recipe.dart';
import '../data/recipes.dart';
import '../agent/safecook_agent.dart';
import '../agent/safecook_context.dart';
import '../agent/safecook_tools.dart';

// ---------------------------------------------------------------------------
// Gas calibration layer — converts raw ADC to a 0-100% percentage.
// Clearly documented calibration range so future devs can adjust it.
// ---------------------------------------------------------------------------
class GasCalibration {
  // MQ-2/MQ-5 sensor range on a typical 10-bit ADC (0-1023).
  // Values below rawClean are considered baseline clean air.
  // Values above rawMax are clamped to 100%.
  // IMPORTANT: These values are derived from empirical observation of the
  // HC-05 sensor module connected to the SafeCook device.  Adjust if the
  // hardware changes.
  static const int rawClean = 50;    // baseline air reading
  static const int rawMax   = 900;   // reading that represents 100% scale

  static double toPercent(int rawValue) {
    final clamped = rawValue.clamp(rawClean, rawMax);
    return ((clamped - rawClean) / (rawMax - rawClean) * 100)
        .clamp(0.0, 100.0);
  }
}

// ---------------------------------------------------------------------------
// VoiceAssistantContext — snapshot of app state for one command turn.
// ---------------------------------------------------------------------------
class VoiceAssistantContext {
  final int? gasValue;
  final String? distanceValue;
  final double? distanceCm;
  final String safetyState;
  final Duration sessionDuration;
  final bool isBluetoothConnected;

  const VoiceAssistantContext({
    this.gasValue,
    this.distanceValue,
    this.distanceCm,
    required this.safetyState,
    required this.sessionDuration,
    required this.isBluetoothConnected,
  });
}

// ---------------------------------------------------------------------------
// VoiceAssistantActions — UI callbacks for the voice assistant.
// Each callback returns a ToolResult so the agent knows actual outcome.
// ---------------------------------------------------------------------------
class VoiceAssistantActions {
  final Future<ToolResult> Function() onNextStep;
  final Future<ToolResult> Function() onPreviousStep;
  final Future<ToolResult> Function() onRepeatStep;
  final Future<ToolResult> Function(int stepNumber) onGoToStep;
  final Future<ToolResult> Function() onEndCooking;
  final Future<ToolResult> Function(Recipe recipe) onStartCooking;
  final Future<ToolResult> Function() onConnectBluetooth;
  final Future<ToolResult> Function() onDisconnectBluetooth;
  final ToolResult Function() onBluetoothStatus;

  const VoiceAssistantActions({
    required this.onNextStep,
    required this.onPreviousStep,
    required this.onRepeatStep,
    required this.onGoToStep,
    required this.onEndCooking,
    required this.onStartCooking,
    required this.onConnectBluetooth,
    required this.onDisconnectBluetooth,
    required this.onBluetoothStatus,
  });
}

// ---------------------------------------------------------------------------
// VoiceAssistantService — bridges screen context into SafeCookAgent.
// ---------------------------------------------------------------------------
class VoiceAssistantService {
  static final VoiceAssistantService _instance =
      VoiceAssistantService._internal();
  factory VoiceAssistantService() => _instance;
  VoiceAssistantService._internal();

  final VoiceService _voiceService = VoiceService();

  Future<String> processVoiceCommand(
    String command,
    VoiceAssistantContext ctx,
    VoiceAssistantActions actions,
  ) async {
    // Build calibrated gas percentage
    final gasPercent =
        ctx.gasValue != null ? GasCalibration.toPercent(ctx.gasValue!) : null;

    // Parse raw distance string to double
    double? distanceCm = ctx.distanceCm;
    if (distanceCm == null && ctx.distanceValue != null) {
      final val = double.tryParse(
          ctx.distanceValue!.replaceAll(' cm', '').trim());
      distanceCm = val;
    }

    final agentContext = SafeCookContext(
      gasValue: ctx.gasValue,
      gasPercent: gasPercent,
      distanceValue: ctx.distanceValue,
      distanceCm: distanceCm,
      safetyState: ctx.safetyState,
      sessionDuration: ctx.sessionDuration,
      isBluetoothConnected: ctx.isBluetoothConnected,
    );

    final agentTools = SafeCookTools(
      searchRecipes: ({vegetarian, quick, ingredient, rawText, category}) {
        return _searchRecipes(
            vegetarian: vegetarian,
            quick: quick,
            ingredient: ingredient,
            rawText: rawText,
            category: category);
      },
      startCooking: actions.onStartCooking,
      nextStep: actions.onNextStep,
      previousStep: actions.onPreviousStep,
      repeatStep: actions.onRepeatStep,
      goToStep: actions.onGoToStep,
      endCooking: actions.onEndCooking,
      connectBluetooth: actions.onConnectBluetooth,
      disconnectBluetooth: actions.onDisconnectBluetooth,
      bluetoothStatus: actions.onBluetoothStatus,
    );

    return SafeCookAgent().handleInput(command, agentContext, agentTools);
  }

  Future<void> speakResponse(String text) async {
    await _voiceService.speak(text);
  }

  // ---------------------------------------------------------------------------
  // Recipe search implementation — shared by all screens
  // ---------------------------------------------------------------------------
  static List<Recipe> _searchRecipes({
    bool? vegetarian,
    bool? quick,
    String? ingredient,
    String? rawText,
    String? category,
  }) {
    return kPredefinedRecipes.where((r) {
      final nameLower = r.name.toLowerCase();
      final descLower = r.description.toLowerCase();
      final catLower = r.category.toLowerCase();

      // Vegetarian filter
      if (vegetarian == true) {
        final nonVegKeywords = [
          'chicken', 'egg', 'fish', 'mutton', 'prawn', 'meat', 'lamb'
        ];
        final isNonVeg = nonVegKeywords.any(
          (kw) => nameLower.contains(kw) || descLower.contains(kw),
        );
        if (isNonVeg) return false;
      }

      // Quick filter
      if (quick == true && r.cookingTime > 25) return false;

      // Ingredient filter
      if (ingredient != null && ingredient.isNotEmpty) {
        final matchIng = r.ingredients
            .any((i) => i.toLowerCase().contains(ingredient));
        if (!matchIng && !nameLower.contains(ingredient)) return false;
      }

      // Category filter
      if (category != null && category.isNotEmpty) {
        if (!catLower.contains(category) && !nameLower.contains(category)) {
          return false;
        }
      }

      // Raw text search
      if (rawText != null && rawText.isNotEmpty) {
        final words = rawText.split(' ')
            .where((w) => w.length > 2)
            .toList();
        // At least one word must match
        final anyMatch = words.any(
          (w) =>
              nameLower.contains(w) ||
              catLower.contains(w) ||
              descLower.contains(w),
        );
        if (!anyMatch) return false;
      }

      return true;
    }).toList();
  }
}
