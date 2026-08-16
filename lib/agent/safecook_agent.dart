// ignore_for_file: avoid_print

import '../models/recipe.dart';
import '../data/recipes.dart';
import 'safecook_context.dart';
import 'safecook_intent.dart';
import 'safecook_tools.dart';
import 'package:flutter/foundation.dart';

// ---------------------------------------------------------------------------
// SafeCookAgent — singleton brain of the voice assistant.
//
// Architecture:
//   handleInput(rawInput, context, tools) → Future<String>
//
// Flow:
//   1. Snapshot live sensor data from context into _mem
//   2. NLU parse with conversation-state as context
//   3. Recipe resolution pipeline (4-tier) if the utterance isn't recognised
//   4. Intent dispatch → Tool execution → Response
//
// State ownership:
//   - SafeCookSessionMemory (_mem) is the SINGLE source of truth.
//   - CookingGuidanceScreen must call agent.confirmStepIndex(idx) after every
//     navigation to keep _mem.currentStepIndex in sync.
// ---------------------------------------------------------------------------
class SafeCookAgent {
  static final SafeCookAgent _instance = SafeCookAgent._internal();
  factory SafeCookAgent() => _instance;
  SafeCookAgent._internal();

  // Single authoritative memory — never create a second instance
  final SafeCookSessionMemory _mem = SafeCookSessionMemory();

  // Public accessors used by screens to inspect / set state
  SafeCookSessionMemory get memory => _mem;
  ConversationState get conversationState => _mem.conversationState;
  set conversationState(ConversationState s) => _mem.conversationState = s;
  Recipe? get selectedRecipe => _mem.selectedRecipe;
  set selectedRecipe(Recipe? r) => _mem.selectedRecipe = r;
  bool get isCookingActive => _mem.isCookingActive;

  /// Called by CookingGuidanceScreen every time the step index changes
  /// so _mem stays in sync with the UI.
  void confirmStepIndex(int idx) {
    _mem.currentStepIndex = idx;
  }

  /// Full reset — call when a session ends cleanly.
  void reset() => _mem.reset();

  // -------------------------------------------------------------------------
  // Recipe index — built once from kPredefinedRecipes
  // -------------------------------------------------------------------------
  final Map<String, Recipe> _fullNameIndex = {};
  final Map<String, List<Recipe>> _aliasIndex = {};
  bool _isIndexBuilt = false;

  void _buildRecipeIndex() {
    if (_isIndexBuilt) return;
    _fullNameIndex.clear();
    _aliasIndex.clear();
    for (final r in kPredefinedRecipes) {
      final normName = _norm(r.name);
      _fullNameIndex[normName] = r;
      _addAlias(normName, r);
      final words = normName.split(' ');
      for (final w in words) {
        if (w.length > 2) _addAlias(w, r);
      }
      if (words.length > 2) {
        for (int i = 0; i < words.length - 1; i++) {
          _addAlias('${words[i]} ${words[i + 1]}', r);
        }
      }
    }
    _isIndexBuilt = true;
  }

  void _addAlias(String alias, Recipe r) =>
      _aliasIndex.putIfAbsent(alias, () => []).add(r);

  // -------------------------------------------------------------------------
  // Helpers
  // -------------------------------------------------------------------------
  static String _norm(String s) =>
      s.toLowerCase()
       .replaceAll(RegExp(r'[^\w\s]'), '')
       .replaceAll(RegExp(r'\s+'), ' ')
       .trim();

  static String _cleanQuery(String normalized) {
    String c = normalized;
    for (final p in [
      'can you make ', 'how to cook ', 'how to make ', 'i want to cook ',
      'i want to make ', 'search for ', 'find me ', 'show me ', 'i want ',
      'make ', 'cook ', 'find ',
    ]) {
      if (c.startsWith(p)) { c = c.substring(p.length).trim(); break; }
    }
    for (final s in [' recipe', ' please']) {
      if (c.endsWith(s)) { c = c.substring(0, c.length - s.length).trim(); break; }
    }
    return c;
  }

  static String _fmtDuration(Duration d) {
    if (d == Duration.zero) return 'less than a minute';
    final mins = d.inMinutes;
    final secs = d.inSeconds.remainder(60);
    final hours = d.inHours;
    String r = '';
    if (hours > 0) r += '$hours hour${hours > 1 ? 's' : ''}';
    if (mins > 0) {
      final m = mins.remainder(60);
      if (m > 0) { if (r.isNotEmpty) r += ' and '; r += '$m minute${m > 1 ? 's' : ''}'; }
    }
    if (r.isEmpty && secs > 0) r = '$secs second${secs > 1 ? 's' : ''}';
    return r;
  }

  // -------------------------------------------------------------------------
  // Recipe resolution — 4-tier pipeline
  // Returns (single recipe | null) and also sets matchedRecipes for multi-result.
  // -------------------------------------------------------------------------
  (Recipe?, List<Recipe>) _resolveRecipe(String normalized, String cleanedQuery) {
    _buildRecipeIndex();
    Recipe? resolved;
    List<Recipe> matched = [];

    // Tier 1: exact normalized name
    if (_fullNameIndex.containsKey(normalized)) {
      resolved = _fullNameIndex[normalized]!;
      return (resolved, [resolved]);
    }

    // Tier 2: exact cleaned query
    if (_fullNameIndex.containsKey(cleanedQuery)) {
      resolved = _fullNameIndex[cleanedQuery]!;
      return (resolved, [resolved]);
    }

    // Tier 3: containment
    for (final name in _fullNameIndex.keys) {
      if (normalized.contains(name) || name.contains(normalized)) {
        final r = _fullNameIndex[name]!;
        if (!matched.contains(r)) matched.add(r);
      }
    }
    if (matched.length == 1) return (matched.first, matched);
    if (matched.length > 1) return (null, matched);

    // Tier 4: alias index
    for (final query in [normalized, cleanedQuery]) {
      if (_aliasIndex.containsKey(query)) {
        final list = _aliasIndex[query]!;
        if (list.length == 1) return (list.first, list);
        if (list.length > 1) return (null, List.from(list));
      }
    }

    return (null, []);
  }

  // -------------------------------------------------------------------------
  // Main entry point
  // -------------------------------------------------------------------------
  Future<String> handleInput(
    String rawInput,
    SafeCookContext context,
    SafeCookTools tools,
  ) async {
    // Snapshot sensor data — the agent NEVER fabricates sensor readings.
    _mem.gasValue = context.gasValue;
    _mem.gasPercent = context.gasPercent;
    _mem.distanceValue = context.distanceValue;
    _mem.distanceCm = context.distanceCm;
    _mem.safetyState = context.safetyState;
    _mem.sessionDuration = context.sessionDuration;
    _mem.isBluetoothConnected = context.isBluetoothConnected;

    // If the UI says cooking is active, keep our state consistent.
    if (context.isCookingActive && !_mem.isCookingActive) {
      _mem.isCookingActive = true;
      if (_mem.conversationState == ConversationState.idle) {
        _mem.conversationState = ConversationState.cooking;
      }
    }

    _mem.lastUserRequest = rawInput;

    print('[SafeCookAgent] state=${_mem.conversationState.name} input="$rawInput"');

    // -----------------------------------------------------------------------
    // Phase B: NLU parse (context-aware)
    // -----------------------------------------------------------------------
    final intent = SafeCookNLU.parse(
      rawInput,
      conversationState: _mem.conversationState.name,
      isCookingActive: _mem.isCookingActive,
    );

    print('[SafeCookAgent] intent=${intent.type}');

    // -----------------------------------------------------------------------
    // Dispatch
    // -----------------------------------------------------------------------

    // --- GREETING ---
    if (intent.type == SafeCookIntentType.greeting) {
      if (_mem.isCookingActive) {
        final step = _mem.currentStepIndex + 1;
        final total = context.totalSteps;
        return 'Hello! I\'m here. You are on step $step of $total. How can I help?';
      }
      _mem.conversationState = ConversationState.selectingRecipe;
      return 'Hello! I\'m SafeCook, your smart cooking safety assistant. What would you like to cook today?';
    }

    // --- HELP ---
    if (intent.type == SafeCookIntentType.help) {
      if (_mem.isCookingActive) {
        return 'You can say: next step, previous step, repeat that, check gas, check distance, check safety, read ingredients, end cooking.';
      }
      return 'You can say: find me a recipe, start cooking, check gas, check distance, check safety, or connect sensor.';
    }

    // --- CONFIRM YES ---
    if (intent.type == SafeCookIntentType.confirmYes) {
      return await _handleConfirmYes(context, tools);
    }

    // --- CONFIRM NO ---
    if (intent.type == SafeCookIntentType.confirmNo) {
      return _handleConfirmNo(context);
    }

    // --- SELECT RECIPE (ordinal from list) ---
    if (intent.type == SafeCookIntentType.selectRecipe) {
      return _handleSelectRecipe(intent);
    }

    // --- FIND RECIPE ---
    if (intent.type == SafeCookIntentType.findRecipe) {
      return _handleFindRecipe(intent, tools);
    }

    // --- START COOKING ---
    if (intent.type == SafeCookIntentType.startCooking) {
      return await _handleStartCooking(context, tools);
    }

    // --- NEXT STEP ---
    if (intent.type == SafeCookIntentType.nextStep) {
      return await _handleNextStep(context, tools);
    }

    // --- PREVIOUS STEP ---
    if (intent.type == SafeCookIntentType.previousStep) {
      return await _handlePreviousStep(context, tools);
    }

    // --- GO TO STEP ---
    if (intent.type == SafeCookIntentType.goToStep) {
      return await _handleGoToStep(intent, context, tools);
    }

    // --- REPEAT STEP ---
    if (intent.type == SafeCookIntentType.readStep) {
      return await _handleRepeatStep(context, tools);
    }

    // --- READ INGREDIENTS ---
    if (intent.type == SafeCookIntentType.readIngredients) {
      return _handleReadIngredients(context);
    }

    // --- READ SAFETY NOTES ---
    if (intent.type == SafeCookIntentType.readSafetyNotes) {
      return _handleReadSafetyNotes(context);
    }

    // --- CHECK GAS ---
    if (intent.type == SafeCookIntentType.checkGas) {
      return _handleCheckGas(context);
    }

    // --- CHECK DISTANCE ---
    if (intent.type == SafeCookIntentType.checkDistance) {
      return _handleCheckDistance(context);
    }

    // --- CHECK SAFETY ---
    if (intent.type == SafeCookIntentType.checkSafety) {
      return _handleCheckSafety(context);
    }

    // --- CHECK TIME ---
    if (intent.type == SafeCookIntentType.checkTime) {
      if (!_mem.isCookingActive) {
        return 'You are not in an active cooking session.';
      }
      return 'You have been cooking for ${_fmtDuration(context.sessionDuration)}.';
    }

    // --- END COOKING ---
    if (intent.type == SafeCookIntentType.endCooking) {
      return _handleEndCooking(context);
    }

    // --- BLUETOOTH ---
    if (intent.type == SafeCookIntentType.checkConnectionStatus) {
      return _handleBluetoothStatus(intent, tools);
    }

    if (intent.type == SafeCookIntentType.connectBluetooth) {
      return await _handleConnectBluetooth(intent, tools);
    }

    if (intent.type == SafeCookIntentType.disconnectBluetooth) {
      return await _handleDisconnectBluetooth(intent, tools);
    }

    // --- WEB SEARCH ---
    if (intent.type == SafeCookIntentType.webSearch) {
      // Phase 7 placeholder — no API integrated yet
      final query = intent.entities['webQuery'] as String? ?? rawInput;
      return 'I don\'t have web search integrated yet. Would you like help with a recipe, cooking instructions, or a safety check? Your query was: "$query".';
    }

    // --- COOKING QUESTION (local knowledge base) ---
    if (intent.type == SafeCookIntentType.cookingQuestion) {
      final answer = _localCookingKnowledge(rawInput.toLowerCase());
      if (answer != null) {
        _mem.lastAssistantResponse = answer;
        return answer;
      }
    }

    // --- UNKNOWN — recipe detail check, then clarification ---
    return _handleUnknown(rawInput, context, tools);
  }

  // =========================================================================
  // Handler methods
  // =========================================================================

  Future<String> _handleConfirmYes(
      SafeCookContext context, SafeCookTools tools) async {
    switch (_mem.conversationState) {
      case ConversationState.confirmingStart:
        if (_mem.selectedRecipe != null) {
          // Announce recipe, then ingredients, then safety, then ask "ready?"
          final r = _mem.selectedRecipe!;
          final ingredientsList = r.ingredients.join(', ');
          final safetyNotes = r.safetyNotes.isNotEmpty
              ? r.safetyNotes.join(' ')
              : 'Keep your workspace clear and monitor the stove at all times.';
          _mem.conversationState = ConversationState.awaitingReadyConfirm;
          final resp =
              'Great! You\'re cooking ${r.name}. You will need: $ingredientsList. '
              'Safety note: $safetyNotes. '
              'Are you ready to begin step 1?';
          _mem.lastAssistantResponse = resp;
          return resp;
        }
        return 'Please select a recipe first.';

      case ConversationState.awaitingReadyConfirm:
        if (_mem.selectedRecipe != null) {
          final r = _mem.selectedRecipe!;
          final result = await tools.startCooking(r);
          if (result.success) {
            _mem.startCookingSession(r);
            final step1 = r.steps.isNotEmpty
                ? r.steps.first.voiceInstruction
                : 'Begin preparing your ingredients.';
            final resp = 'Starting step 1. $step1';
            _mem.lastAssistantResponse = resp;
            return resp;
          } else {
            return 'I was unable to start the cooking session. ${result.message}';
          }
        }
        return 'Please select a recipe first.';

      case ConversationState.confirmingEnd:
        final result = await tools.endCooking();
        if (result.success) {
          _mem.endCookingSession();
          const resp = 'Cooking session ended. Preparing your cooking report.';
          _mem.lastAssistantResponse = resp;
          return resp;
        } else {
          return 'I was unable to end the session. ${result.message}';
        }

      default:
        // No pending confirmation — treat as general affirmative
        if (_mem.isCookingActive) {
          return 'Continuing your cooking session. How can I help?';
        }
        return 'Okay! What would you like to do?';
    }
  }

  String _handleConfirmNo(SafeCookContext context) {
    switch (_mem.conversationState) {
      case ConversationState.confirmingStart:
        _mem.conversationState = ConversationState.selectingRecipe;
        _mem.selectedRecipe = null;
        return 'Okay, no problem. What else would you like to cook?';

      case ConversationState.awaitingReadyConfirm:
        _mem.conversationState = ConversationState.confirmingStart;
        return 'Take your time. Say "ready" when you want to begin step 1.';

      case ConversationState.confirmingEnd:
        _mem.conversationState = ConversationState.cooking;
        final stepIdx = _mem.currentStepIndex;
        final recipe = context.recipe ?? _mem.selectedRecipe;
        if (recipe != null && stepIdx < recipe.steps.length) {
          final step = recipe.steps[stepIdx];
          return 'Okay, continuing. You are on step ${stepIdx + 1}: ${step.voiceInstruction}';
        }
        return 'Okay, continuing your cooking session.';

      default:
        return 'Okay! Let me know if you need anything.';
    }
  }

  String _handleSelectRecipe(SafeCookIntent intent) {
    final index = intent.entities['index'] as int? ?? -1;
    final results = _mem.lastRecipeSearchResults;

    Recipe? target;
    if (index == -2 && results.isNotEmpty) {
      target = results.last;
    } else if (index >= 0 && index < results.length) {
      target = results[index];
    }

    if (target != null) {
      _mem.selectedRecipe = target;
      _mem.conversationState = ConversationState.confirmingStart;
      final resp =
          'You selected ${target.name}. It takes about ${target.cookingTime} minutes. Would you like to start cooking?';
      _mem.lastAssistantResponse = resp;
      return resp;
    }

    return 'I\'m not sure which recipe you mean. Please say the recipe name, or say "first", "second", etc.';
  }

  String _handleFindRecipe(SafeCookIntent intent, SafeCookTools tools) {
    final results = tools.searchRecipes(
      vegetarian: intent.entities['vegetarian'] as bool?,
      quick: intent.entities['quick'] as bool?,
      ingredient: intent.entities['ingredient'] as String?,
      rawText: intent.entities['rawText'] as String?,
      category: intent.entities['category'] as String?,
    );

    if (results.isEmpty) {
      // Narrow the search
      return 'I couldn\'t find matching recipes. Try asking for a specific ingredient, cuisine, or say "show me all recipes".';
    }

    _mem.lastRecipeSearchResults = results;

    if (results.length == 1) {
      _mem.selectedRecipe = results.first;
      _mem.conversationState = ConversationState.confirmingStart;
      final r = results.first;
      final resp =
          'I found ${r.name}. It takes about ${r.cookingTime} minutes and serves ${r.servings} people. Would you like to start cooking?';
      _mem.lastAssistantResponse = resp;
      return resp;
    }

    _mem.conversationState = ConversationState.selectingRecipe;
    final names = results.take(5).map((r) => r.name).toList();
    String listing = names.asMap().entries.map((e) => '${e.key + 1}. ${e.value}').join(', ');
    if (results.length > 5) listing += ', and ${results.length - 5} more';
    final resp =
        'I found ${results.length} recipes. $listing. Which would you like?';
    _mem.lastAssistantResponse = resp;
    return resp;
  }

  Future<String> _handleStartCooking(
      SafeCookContext context, SafeCookTools tools) async {
    if (_mem.isCookingActive) {
      return 'A cooking session is already active.';
    }
    var recipe = context.recipe ?? _mem.selectedRecipe;
    if (recipe == null) {
      final normalized = _norm(_mem.lastUserRequest ?? '');
      final cleanedQuery = _cleanQuery(normalized);
      final (resolved, _) = _resolveRecipe(normalized, cleanedQuery);
      recipe = resolved;
    }

    if (recipe == null) {
      _mem.conversationState = ConversationState.selectingRecipe;
      return 'Please search or name a recipe first, then say start cooking.';
    }

    // Move to awaitingReadyConfirm phase (ingredients + safety)
    final ingredientsList = recipe.ingredients.join(', ');
    final safetyNotes = recipe.safetyNotes.isNotEmpty
        ? recipe.safetyNotes.join(' ')
        : 'Keep your workspace clear and monitor the stove at all times.';
    _mem.selectedRecipe = recipe;
    _mem.conversationState = ConversationState.awaitingReadyConfirm;
    final resp =
        'Starting ${recipe.name}. You will need: $ingredientsList. '
        'Safety note: $safetyNotes. '
        'Say ready when you want to begin step 1.';
    _mem.lastAssistantResponse = resp;
    return resp;
  }

  Future<String> _handleNextStep(
      SafeCookContext context, SafeCookTools tools) async {
    if (!_mem.isCookingActive) {
      return 'Please select a recipe and start cooking first.';
    }
    final recipe = context.recipe ?? _mem.selectedRecipe;
    final stepIdx = context.currentStepIndex; // authoritative source from UI
    final total = context.totalSteps;

    if (recipe == null || total == 0) {
      return 'No active recipe is loaded.';
    }

    if (stepIdx >= total - 1) {
      return 'You are already on the last step. Say "end cooking" when you\'re done.';
    }

    final memoryIndexBefore = _mem.currentStepIndex;
    final result = await tools.nextStep();
    final memoryIndexAfter = _mem.currentStepIndex;

    debugPrint('[SafeCook STEP]\n'
        'command="next step"\n'
        'beforeIndex=$stepIdx\n'
        'contextIndex=${context.currentStepIndex}\n'
        'memoryIndexBefore=$memoryIndexBefore\n'
        'toolCalled=true\n'
        'toolResult=${result.success}\n'
        'memoryIndexAfter=$memoryIndexAfter\n'
        'uiIndex=$memoryIndexAfter\n'
        'responseStep=${memoryIndexAfter + 1}');

    if (!result.success) {
      return 'I couldn\'t advance the step. ${result.message}';
    }

    final nextIdx = _mem.currentStepIndex;
    final step = recipe.steps[nextIdx];
    final resp = 'Step ${nextIdx + 1}. ${step.voiceInstruction}';
    _mem.lastAssistantResponse = resp;
    return resp;
  }

  Future<String> _handlePreviousStep(
      SafeCookContext context, SafeCookTools tools) async {
    if (!_mem.isCookingActive) {
      return 'Please start cooking first.';
    }
    final recipe = context.recipe ?? _mem.selectedRecipe;
    final stepIdx = context.currentStepIndex;

    if (recipe == null) return 'No active recipe is loaded.';

    if (stepIdx <= 0) {
      return 'You are already on step 1.';
    }

    final memoryIndexBefore = _mem.currentStepIndex;
    final result = await tools.previousStep();
    final memoryIndexAfter = _mem.currentStepIndex;

    debugPrint('[SafeCook STEP]\n'
        'command="previous step"\n'
        'beforeIndex=$stepIdx\n'
        'contextIndex=${context.currentStepIndex}\n'
        'memoryIndexBefore=$memoryIndexBefore\n'
        'toolCalled=true\n'
        'toolResult=${result.success}\n'
        'memoryIndexAfter=$memoryIndexAfter\n'
        'uiIndex=$memoryIndexAfter\n'
        'responseStep=${memoryIndexAfter + 1}');

    if (!result.success) {
      return 'I couldn\'t go back. ${result.message}';
    }

    final prevIdx = _mem.currentStepIndex;
    final step = recipe.steps[prevIdx];
    final resp = 'Going back to step ${prevIdx + 1}. ${step.voiceInstruction}';
    _mem.lastAssistantResponse = resp;
    return resp;
  }

  Future<String> _handleGoToStep(
      SafeCookIntent intent, SafeCookContext context, SafeCookTools tools) async {
    if (!_mem.isCookingActive) {
      return 'Please start cooking first.';
    }
    final rawStep = intent.entities['stepNumber'] as int? ?? -1;
    final recipe = context.recipe ?? _mem.selectedRecipe;
    final total = context.totalSteps;

    if (recipe == null || total == 0) return 'No active recipe is loaded.';
    
    // Clamp stepNumber safely to [1, total] to allow boundaries and excessive numbers
    final stepNumber = rawStep.clamp(1, total);

    final memoryIndexBefore = _mem.currentStepIndex;
    final result = await tools.goToStep(stepNumber);
    final memoryIndexAfter = _mem.currentStepIndex;

    debugPrint('[SafeCook STEP]\n'
        'command="go to step"\n'
        'beforeIndex=${context.currentStepIndex}\n'
        'contextIndex=${context.currentStepIndex}\n'
        'memoryIndexBefore=$memoryIndexBefore\n'
        'toolCalled=true\n'
        'toolResult=${result.success}\n'
        'memoryIndexAfter=$memoryIndexAfter\n'
        'uiIndex=$memoryIndexAfter\n'
        'responseStep=${memoryIndexAfter + 1}');

    if (!result.success) {
      return 'I couldn\'t navigate to step $stepNumber. ${result.message}';
    }

    final idx = _mem.currentStepIndex;
    final step = recipe.steps[idx];
    final resp = 'Going to step ${idx + 1}. ${step.voiceInstruction}';
    _mem.lastAssistantResponse = resp;
    return resp;
  }

  Future<String> _handleRepeatStep(
      SafeCookContext context, SafeCookTools tools) async {
    if (!_mem.isCookingActive) {
      return 'You are not currently in a cooking session.';
    }
    final recipe = context.recipe ?? _mem.selectedRecipe;
    final stepIdx = context.currentStepIndex;

    if (recipe == null) return 'No active recipe is loaded.';

    final result = await tools.repeatStep();
    if (!result.success) {
      // Fall back to reading from data
      if (stepIdx < recipe.steps.length) {
        return 'Step ${stepIdx + 1}: ${recipe.steps[stepIdx].voiceInstruction}';
      }
      return 'I couldn\'t repeat the step. ${result.message}';
    }

    final step = recipe.steps[stepIdx];
    return 'Step ${stepIdx + 1}: ${step.voiceInstruction}';
  }

  String _handleReadIngredients(SafeCookContext context) {
    final r = context.recipe ?? _mem.selectedRecipe;
    if (r == null) {
      return 'Please select a recipe first before checking ingredients.';
    }
    final list = r.ingredients.join(', ');
    return 'The ingredients for ${r.name} are: $list.';
  }

  String _handleReadSafetyNotes(SafeCookContext context) {
    final r = context.recipe ?? _mem.selectedRecipe;
    if (r == null) {
      return 'Please select a recipe first.';
    }
    if (r.safetyNotes.isEmpty) {
      return 'No specific safety notes for ${r.name}. Always keep the stove area clear and monitor the heat.';
    }
    return 'Safety notes for ${r.name}: ${r.safetyNotes.join('. ')}.';
  }

  String _handleCheckGas(SafeCookContext context) {
    if (context.gasValue == null) {
      return 'The gas sensor is not connected or not reporting data yet.';
    }
    if (context.gasPercent != null) {
      final pct = context.gasPercent!.toStringAsFixed(0);
      final label = context.gasPercent! < 30
          ? 'normal'
          : context.gasPercent! < 60
              ? 'elevated'
              : 'high';
      return 'The current flame and gas level is approximately $pct percent, which is $label.';
    }
    // Fallback to raw value
    final val = context.gasValue!;
    final label = val < 300 ? 'normal' : val < 600 ? 'elevated' : 'high';
    return 'The current gas sensor reading is $val, which is $label.';
  }

  String _handleCheckDistance(SafeCookContext context) {
    if (context.distanceValue == null || context.distanceValue == 'No Echo') {
      return 'The distance sensor is not detecting anything right now. Make sure the sensor is facing the cooking vessel.';
    }
    if (context.distanceCm != null) {
      final cm = context.distanceCm!.toStringAsFixed(1);
      String advice;
      if (context.distanceCm! > 30) {
        advice = 'You are at a safe distance from the cooking vessel.';
      } else if (context.distanceCm! > 15) {
        advice = 'You are fairly close to the cooking vessel. Be cautious.';
      } else {
        advice = 'Warning: you are very close to the cooking vessel. Please step back.';
      }
      return 'You are approximately $cm centimetres from the cooking vessel. $advice';
    }
    return 'Your distance from the cooking vessel is ${context.distanceValue}.';
  }

  String _handleCheckSafety(SafeCookContext context) {
    final state = context.safetyState;
    switch (state) {
      case 'SAFE':
        return 'Your cooking environment is currently safe.';
      case 'CAUTION':
        return 'Caution is advised. SafeCook has detected elevated readings.';
      case 'GAS ALERT':
        return 'Warning: elevated gas level detected. Please check your burner.';
      case 'DISTANCE ALERT':
        return 'Warning: you are too close to the cooking vessel. Please step back.';
      case 'CRITICAL':
        return 'Critical alert: both gas and distance readings are unsafe. Please take immediate action.';
      case 'STANDBY':
        return 'Sensors are in standby mode. Connect your sensor for live safety monitoring.';
      default:
        return 'I cannot verify the safety sensors right now.';
    }
  }

  String _handleEndCooking(SafeCookContext context) {
    if (!_mem.isCookingActive) {
      return 'There is no active cooking session to end.';
    }
    _mem.conversationState = ConversationState.confirmingEnd;
    final elapsed = _fmtDuration(context.sessionDuration);
    final resp =
        'Your cooking session has been running for $elapsed. Do you want to end it?';
    _mem.lastAssistantResponse = resp;
    return resp;
  }

  String _handleBluetoothStatus(SafeCookIntent intent, SafeCookTools tools) {
    final result = tools.bluetoothStatus();
    debugPrint('[SafeCook BT]\n'
        'recognized="${intent.rawQuery}"\n'
        'intent=checkConnectionStatus\n'
        'tool=bluetoothStatus\n'
        'nativeOperationStarted=false\n'
        'nativeOperationResult=${result.message}\n'
        'actualConnected=${_mem.isBluetoothConnected}');
    return result.success
        ? 'The sensor is connected and transmitting data.'
        : 'The sensor is not connected. Say "connect sensor" to connect.';
  }

  Future<String> _handleConnectBluetooth(SafeCookIntent intent, SafeCookTools tools) async {
    if (_mem.isBluetoothConnected) {
      return 'The sensor is already connected.';
    }
    final result = await tools.connectBluetooth();
    logTool('connectBluetooth', result);
    if (result.success) {
      _mem.isBluetoothConnected = true;
    }
    debugPrint('[SafeCook BT]\n'
        'recognized="${intent.rawQuery}"\n'
        'intent=connectBluetooth\n'
        'tool=connectBluetooth\n'
        'nativeOperationStarted=true\n'
        'nativeOperationResult=${result.message}\n'
        'actualConnected=${_mem.isBluetoothConnected}');
    return result.success
        ? 'Connection successful. The sensor is now active.'
        : 'I was unable to connect to the sensor. ${result.message} Please make sure the device is powered on and paired.';
  }

  Future<String> _handleDisconnectBluetooth(SafeCookIntent intent, SafeCookTools tools) async {
    if (!_mem.isBluetoothConnected) {
      return 'The sensor is already disconnected.';
    }
    final result = await tools.disconnectBluetooth();
    logTool('disconnectBluetooth', result);
    if (result.success) {
      _mem.isBluetoothConnected = false;
    }
    debugPrint('[SafeCook BT]\n'
        'recognized="${intent.rawQuery}"\n'
        'intent=disconnectBluetooth\n'
        'tool=disconnectBluetooth\n'
        'nativeOperationStarted=true\n'
        'nativeOperationResult=${result.message}\n'
        'actualConnected=${_mem.isBluetoothConnected}');
    return result.success
        ? 'Sensor disconnected.'
        : 'I was unable to disconnect. ${result.message}';
  }

  String _handleUnknown(
      String rawInput, SafeCookContext context, SafeCookTools tools) {
    final normalized = _norm(rawInput);
    final cleanedQuery = _cleanQuery(normalized);

    // Try to resolve a recipe first
    if (!_mem.isCookingActive &&
        _mem.conversationState != ConversationState.confirmingEnd) {
      final (resolvedRecipe, matchedRecipes) =
          _resolveRecipe(normalized, cleanedQuery);

      if (resolvedRecipe != null) {
        _mem.selectedRecipe = resolvedRecipe;
        _mem.conversationState = ConversationState.confirmingStart;
        final resp =
            'I found ${resolvedRecipe.name}. It takes about ${resolvedRecipe.cookingTime} minutes and serves ${resolvedRecipe.servings} people. Would you like to start cooking?';
        _mem.lastAssistantResponse = resp;
        return resp;
      }

      if (matchedRecipes.length > 1 &&
          _mem.conversationState != ConversationState.selectingRecipe) {
        _mem.lastRecipeSearchResults = matchedRecipes;
        _mem.conversationState = ConversationState.selectingRecipe;
        final names = matchedRecipes.take(5).map((r) => r.name).join(', ');
        final resp =
            'I found ${matchedRecipes.length} matching recipes. The options are: $names. Which one would you like?';
        _mem.lastAssistantResponse = resp;
        return resp;
      }
    }

    // Check local knowledge base
    final answer = _localCookingKnowledge(rawInput.toLowerCase());
    if (answer != null) {
      _mem.lastAssistantResponse = answer;
      return answer;
    }

    // Check if the utterance contains a recipe name — offer detail info
    final q = rawInput.toLowerCase();

    for (final r in kPredefinedRecipes) {
      final normName = _norm(r.name);
      if (normalized.contains(normName) ||
          (cleanedQuery.length > 3 && normName.contains(cleanedQuery))) {
        if (q.contains('ingredient') || q.contains('what do i need')) {
          return 'The ingredients for ${r.name} are: ${r.ingredients.join(', ')}.';
        }
        if (q.contains('how long') || q.contains('time') || q.contains('duration')) {
          return '${r.name} takes about ${r.cookingTime} minutes to prepare.';
        }
        if (q.contains('how to') || q.contains('step') || q.contains('instruction')) {
          return 'To prepare ${r.name}, we will go through ${r.steps.length} steps. Say "start cooking" and I will guide you step by step.';
        }
      }
    }

    // Default clarification
    if (_mem.isCookingActive) {
      return 'I didn\'t quite catch that. You can say: next step, previous step, repeat that, check gas, check distance, or end cooking.';
    }
    return 'I didn\'t quite understand. You can say: find me a recipe, check gas, check safety, or connect sensor.';
  }

  // =========================================================================
  // Local cooking knowledge base
  // =========================================================================
  static String? _localCookingKnowledge(String q) {
    if (q.contains('coriander') || q.contains('cilantro')) {
      if (q.contains('substitute') || q.contains('instead') || q.contains('replace')) {
        return 'You can substitute coriander with parsley, celery leaves, or fresh dill.';
      }
    }
    if (q.contains('potato') && q.contains('boil')) {
      return 'Boiling potatoes generally takes 15 to 20 minutes for medium pieces, or 25 minutes for whole potatoes.';
    }
    if (q.contains('egg') && q.contains('boil')) {
      return 'For soft-boiled eggs, boil for 6 minutes. For medium, 8 minutes. For hard-boiled, 10 minutes.';
    }
    if ((q.contains('butter') || q.contains('ghee')) &&
        (q.contains('substitute') || q.contains('instead'))) {
      return 'You can substitute butter or ghee with olive oil, coconut oil, or applesauce.';
    }
    if ((q.contains('paneer') || q.contains('cottage cheese')) &&
        (q.contains('substitute') || q.contains('instead'))) {
      return 'You can substitute paneer with firm tofu, ricotta, or halloumi.';
    }
    if (q.contains('onion') &&
        (q.contains('substitute') || q.contains('instead'))) {
      return 'For onions, you can use leeks, shallots, green onions, or a pinch of asafoetida powder.';
    }
    if (q.contains('oil') && (q.contains('hot') || q.contains('test'))) {
      return 'To test if oil is hot, drop a small piece of food in — if bubbles form rapidly around it, the oil is ready.';
    }
    if (q.contains('rice') && q.contains('wash')) {
      return 'Wash rice 2 to 3 times until the water runs fairly clear. This removes excess starch.';
    }
    if (q.contains('spice') && q.contains('too hot')) {
      return 'To reduce spiciness, add dairy like cream, yogurt, or milk. Coconut milk or a pinch of sugar also help.';
    }
    if (q.contains('salt') && q.contains('too much')) {
      return 'To fix over-salted food, add potato pieces and cook briefly — they absorb excess salt. You can also add unsalted liquid.';
    }
    return null;
  }
}
