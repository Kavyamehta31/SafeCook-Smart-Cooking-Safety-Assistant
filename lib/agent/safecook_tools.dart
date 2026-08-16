import 'package:flutter/foundation.dart';
import '../models/recipe.dart';

// ---------------------------------------------------------------------------
// ToolResult — every tool returns success/failure with a data payload.
// The agent MUST NOT claim an action happened unless result.success == true.
// ---------------------------------------------------------------------------
class ToolResult {
  final bool success;
  final String message;
  final dynamic data;

  const ToolResult({
    required this.success,
    required this.message,
    this.data,
  });

  const ToolResult.ok(this.message, {this.data}) : success = true;

  const ToolResult.fail(this.message)
      : success = false,
        data = null;
}

// ---------------------------------------------------------------------------
// SafeCookTools — dependency-injection shim so the agent can trigger
// UI/navigation/Bluetooth actions without importing Flutter widgets.
// Every callback returns ToolResult so the agent knows whether it worked.
// ---------------------------------------------------------------------------
class SafeCookTools {
  // Recipe search — returns list of matching recipes
  final List<Recipe> Function({
    bool? vegetarian,
    bool? quick,
    String? ingredient,
    String? rawText,
    String? category,
  }) searchRecipes;

  // Start cooking — navigates to guidance screen with the given recipe.
  // Returns success only after navigation has been initiated.
  final Future<ToolResult> Function(Recipe recipe) startCooking;

  // Step navigation — only valid when CookingGuidanceScreen is active
  final Future<ToolResult> Function() nextStep;
  final Future<ToolResult> Function() previousStep;
  final Future<ToolResult> Function() repeatStep;

  // Go to a specific step by 1-based number
  final Future<ToolResult> Function(int stepNumber) goToStep;

  // End the cooking session
  final Future<ToolResult> Function() endCooking;

  // Bluetooth tools — these call the REAL HC-05 implementation
  final Future<ToolResult> Function() connectBluetooth;
  final Future<ToolResult> Function() disconnectBluetooth;
  final ToolResult Function() bluetoothStatus;

  const SafeCookTools({
    required this.searchRecipes,
    required this.startCooking,
    required this.nextStep,
    required this.previousStep,
    required this.repeatStep,
    required this.goToStep,
    required this.endCooking,
    required this.connectBluetooth,
    required this.disconnectBluetooth,
    required this.bluetoothStatus,
  });
}

// ---------------------------------------------------------------------------
// NoOpSafeCookTools — safe placeholder for when tools are not available
// (e.g. when the agent is called from home screen with no cooking active).
// ---------------------------------------------------------------------------
SafeCookTools buildNoOpTools() {
  return SafeCookTools(
    searchRecipes: ({vegetarian, quick, ingredient, rawText, category}) => [],
    startCooking: (_) async => const ToolResult.fail('Navigation not available'),
    nextStep: () async => const ToolResult.fail('Not in cooking mode'),
    previousStep: () async => const ToolResult.fail('Not in cooking mode'),
    repeatStep: () async => const ToolResult.fail('Not in cooking mode'),
    goToStep: (_) async => const ToolResult.fail('Not in cooking mode'),
    endCooking: () async => const ToolResult.fail('Not in cooking mode'),
    connectBluetooth: () async => const ToolResult.fail('Bluetooth tools not wired'),
    disconnectBluetooth: () async => const ToolResult.fail('Bluetooth tools not wired'),
    bluetoothStatus: () => const ToolResult.fail('Bluetooth tools not wired'),
  );
}

// ignore: avoid_print
void logTool(String tool, ToolResult result) {
  debugPrint('[SafeCook Tool] $tool → success=${result.success} msg="${result.message}"');
}
