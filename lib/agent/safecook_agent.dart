// ignore_for_file: avoid_print

import '../models/recipe.dart';
import '../data/recipes.dart';
import 'safecook_context.dart';
import 'safecook_intent.dart';
import 'safecook_tools.dart';
import 'safecook_ai_provider.dart';
import 'safecook_conversation_memory.dart';
import '../services/web_search_service.dart';
import 'package:flutter/foundation.dart';
import '../safety/safecook_safety_engine.dart';
import '../safety/safecook_safety_state.dart';
import '../safety/safecook_safety_policy.dart';

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

  // Decoupled AI provider — GeminiAIProvider auto-activates if
  // GEMINI_API_KEY is present (injected via --dart-define at build time).
  // Falls back to LocalMockAIProvider when the key is absent.
  AIProvider aiProvider = _buildDefaultProvider();

  static AIProvider _buildDefaultProvider() {
    final gemini = GeminiAIProvider();
    if (gemini.isConfigured) {
      print('[SafeCook AI] provider=Gemini');
      return gemini;
    }
    print('[SafeCook AI] provider=LocalMock reason=missing-key');
    return LocalMockAIProvider();
  }

  // Bounded conversation memory
  final SafeCookConversationMemory conversationMemory =
      SafeCookConversationMemory();

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
  void reset() {
    _mem.reset();
    conversationMemory.clear();
  }

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
  static String _norm(String s) => s
      .toLowerCase()
      .replaceAll(RegExp(r'[^\w\s]'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  static String _cleanQuery(String normalized) {
    String c = normalized;
    for (final p in [
      'can you make ',
      'how to cook ',
      'how to make ',
      'i want to cook ',
      'i want to make ',
      'search for ',
      'find me ',
      'show me ',
      'i want ',
      'make ',
      'cook ',
      'find ',
    ]) {
      if (c.startsWith(p)) {
        c = c.substring(p.length).trim();
        break;
      }
    }
    for (final s in [' recipe', ' please']) {
      if (c.endsWith(s)) {
        c = c.substring(0, c.length - s.length).trim();
        break;
      }
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
      if (m > 0) {
        if (r.isNotEmpty) r += ' and ';
        r += '$m minute${m > 1 ? 's' : ''}';
      }
    }
    if (r.isEmpty && secs > 0) r = '$secs second${secs > 1 ? 's' : ''}';
    return r;
  }

  // -------------------------------------------------------------------------
  // Recipe resolution — 4-tier pipeline
  // Returns (single recipe | null) and also sets matchedRecipes for multi-result.
  // -------------------------------------------------------------------------
  (Recipe?, List<Recipe>) _resolveRecipe(
    String normalized,
    String cleanedQuery,
  ) {
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
  // Detects deliberate safety-rule override attempts before NLU.
  static bool _isUnsafeOverrideAttempt(String q) {
    final lower = q.toLowerCase();
    return (lower.contains('ignore') && lower.contains('safety')) ||
        (lower.contains('override') && lower.contains('safety')) ||
        (lower.contains('bypass') && lower.contains('safety')) ||
        (lower.contains('disable') && lower.contains('safety')) ||
        (lower.contains('turn on') && lower.contains('stove')) ||
        (lower.contains('ignore the rules')) ||
        (lower.contains('forget the rules') && lower.contains('stove'));
  }

  // Semantic safety classifier: maps ambiguous queries to specific safety intents.
  // Returns null if the query is genuinely not safety-related.
  SafeCookIntentType? _classifySafetyQuery(String rawInput) {
    final q = rawInput.toLowerCase();
    // Gas
    if (q.contains('gas') ||
        q.contains('leak') ||
        q.contains('flame') ||
        q.contains('burner')) {
      return SafeCookIntentType.checkGas;
    }
    // Distance
    if (q.contains('close') ||
        q.contains('distance') ||
        q.contains('far') ||
        q.contains('proximity') ||
        q.contains('step back')) {
      return SafeCookIntentType.checkDistance;
    }
    // Safety status
    if (q.contains('safe') ||
        q.contains('danger') ||
        q.contains('worried') ||
        q.contains('alert') ||
        q.contains('hazard')) {
      return SafeCookIntentType.checkSafety;
    }
    // Connection
    if (q.contains('connect') ||
        q.contains('sensor') ||
        q.contains('hc') ||
        q.contains('bluetooth')) {
      // Distinguish connect vs status
      if (q.contains('disconnect')) {
        return SafeCookIntentType.disconnectBluetooth;
      }
      if (q.contains('status') ||
          q.contains('are we') ||
          q.contains('is it connected') ||
          q.contains('is the sensor connected')) {
        return SafeCookIntentType.checkConnectionStatus;
      }
      return SafeCookIntentType.connectBluetooth;
    }
    // End cooking
    if ((q.contains('end') || q.contains('stop') || q.contains('abort')) &&
        (q.contains('cooking') || q.contains('session'))) {
      return SafeCookIntentType.endCooking;
    }
    return null;
  }

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

    _mem.lastUserRequest = rawInput;

    // Check for deliberate safety-rule override attempts before any routing.
    if (_isUnsafeOverrideAttempt(rawInput)) {
      const safetyRefusal =
          "I can't override SafeCook's safety rules or recommend unsafe stove actions. "
          'I can check the current gas level, your distance from the vessel, '
          'and the overall cooking safety status for you.';
      _mem.lastAssistantResponse = safetyRefusal;
      conversationMemory.addTurn(rawInput, safetyRefusal, 'safetyRefusal');
      return safetyRefusal;
    }

    print(
      '[SafeCookAgent] state=${_mem.conversationState.name} input="$rawInput"',
    );
    print(
      '[SafeCook AI] provider=${aiProvider is GeminiAIProvider ? "Gemini" : "LocalMock"}',
    );

    // -----------------------------------------------------------------------
    // Phase B: NLU parse (context-aware)
    // -----------------------------------------------------------------------
    var intent = SafeCookNLU.parse(
      rawInput,
      conversationState: _mem.conversationState.name,
      isCookingActive: _mem.isCookingActive,
    );

    print('[SafeCookAgent] intent=${intent.type}');

    String responseText = '';

    // -----------------------------------------------------------------------
    // Two-Layer Routing: Direct deterministic routing if NLU returns high confidence (not unknown)
    // -----------------------------------------------------------------------
    if (intent.type != SafeCookIntentType.unknown) {
      // Dispatch deterministically
      if (intent.type == SafeCookIntentType.greeting) {
        if (_mem.isCookingActive) {
          final step = _mem.currentStepIndex + 1;
          final total = _mem.selectedRecipe?.steps.length ?? 0;
          responseText =
              'Hello! I\'m here. You are on step $step of $total. How can I help?';
        } else {
          _mem.conversationState = ConversationState.selectingRecipe;
          responseText =
              'Hello! I\'m SafeCook, your smart cooking safety assistant. What would you like to cook today?';
        }
      } else if (intent.type == SafeCookIntentType.help) {
        if (_mem.isCookingActive) {
          responseText =
              'You can say: next step, previous step, repeat that, check gas, check distance, check safety, read ingredients, end cooking.';
        } else {
          responseText =
              'You can say: find me a recipe, start cooking, check gas, check distance, check safety, or connect sensor.';
        }
      } else if (intent.type == SafeCookIntentType.confirmYes) {
        responseText = await _handleConfirmYes(context, tools);
      } else if (intent.type == SafeCookIntentType.confirmNo) {
        responseText = _handleConfirmNo(context);
      } else if (intent.type == SafeCookIntentType.selectRecipe) {
        responseText = _handleSelectRecipe(intent);
      } else if (intent.type == SafeCookIntentType.findRecipe) {
        responseText = _handleFindRecipe(intent, tools);
      } else if (intent.type == SafeCookIntentType.startCooking) {
        responseText = await _handleStartCooking(context, tools);
      } else if (intent.type == SafeCookIntentType.nextStep) {
        responseText = await _handleNextStep(context, tools);
      } else if (intent.type == SafeCookIntentType.previousStep) {
        responseText = await _handlePreviousStep(context, tools);
      } else if (intent.type == SafeCookIntentType.goToStep) {
        responseText = await _handleGoToStep(intent, context, tools);
      } else if (intent.type == SafeCookIntentType.readStep) {
        responseText = await _handleRepeatStep(context, tools);
      } else if (intent.type == SafeCookIntentType.readIngredients) {
        responseText = _handleReadIngredients(context);
      } else if (intent.type == SafeCookIntentType.readSafetyNotes) {
        responseText = _handleReadSafetyNotes(context);
      } else if (intent.type == SafeCookIntentType.checkGas) {
        responseText = _handleCheckGas(context);
      } else if (intent.type == SafeCookIntentType.checkDistance) {
        responseText = _handleCheckDistance(context);
      } else if (intent.type == SafeCookIntentType.checkSafety) {
        responseText = _handleCheckSafety(context);
      } else if (intent.type == SafeCookIntentType.checkTime) {
        if (!_mem.isCookingActive) {
          responseText = 'You are not in an active cooking session.';
        } else {
          responseText =
              'You have been cooking for ${_fmtDuration(context.sessionDuration)}.';
        }
      } else if (intent.type == SafeCookIntentType.endCooking) {
        responseText = _handleEndCooking(context);
      } else if (intent.type == SafeCookIntentType.checkConnectionStatus) {
        responseText = _handleBluetoothStatus(intent, tools);
      } else if (intent.type == SafeCookIntentType.connectBluetooth) {
        responseText = await _handleConnectBluetooth(intent, tools);
      } else if (intent.type == SafeCookIntentType.disconnectBluetooth) {
        responseText = await _handleDisconnectBluetooth(intent, tools);
      } else if (intent.type == SafeCookIntentType.webSearch) {
        final query = intent.entities['webQuery'] as String? ?? rawInput;
        responseText = await _handleWebSearch(query, tools);
      } else if (intent.type == SafeCookIntentType.cookingQuestion) {
        final answer = _localCookingKnowledge(rawInput.toLowerCase());
        if (answer != null) {
          responseText = answer;
        }
      }
    }

    // -----------------------------------------------------------------------
    // AI Fallback Layer for unknown/conversational queries
    // -----------------------------------------------------------------------
    if (responseText.isEmpty) {
      // First try to run deterministic unknown resolution (resolves exact recipe matches/aliases/details)
      final unknownResult = _handleUnknown(rawInput, context, tools);
      final isClarification = unknownResult.startsWith("I didn't quite");

      if (!isClarification) {
        responseText = unknownResult;
      } else {
        // Truly unknown: try semantic safety routing first, then AI
        final safetyIntent = _classifySafetyQuery(rawInput);
        if (safetyIntent != null) {
          // Route to the correct deterministic safety handler
          switch (safetyIntent) {
            case SafeCookIntentType.checkGas:
              {
                responseText = _handleCheckGas(context);
              }
            case SafeCookIntentType.checkDistance:
              {
                responseText = _handleCheckDistance(context);
              }
            case SafeCookIntentType.checkSafety:
              {
                responseText = _handleCheckSafety(context);
              }
            case SafeCookIntentType.connectBluetooth:
              {
                responseText = await _handleConnectBluetooth(
                  SafeCookIntent(
                    type: SafeCookIntentType.connectBluetooth,
                    rawQuery: rawInput,
                  ),
                  tools,
                );
              }
            case SafeCookIntentType.disconnectBluetooth:
              {
                responseText = await _handleDisconnectBluetooth(
                  SafeCookIntent(
                    type: SafeCookIntentType.disconnectBluetooth,
                    rawQuery: rawInput,
                  ),
                  tools,
                );
              }
            case SafeCookIntentType.checkConnectionStatus:
              {
                responseText = _handleBluetoothStatus(
                  SafeCookIntent(
                    type: SafeCookIntentType.checkConnectionStatus,
                    rawQuery: rawInput,
                  ),
                  tools,
                );
              }
            case SafeCookIntentType.endCooking:
              {
                responseText = _handleEndCooking(context);
              }
            default:
              {
                responseText =
                    'Please say a specific command such as "check gas", "check safety", or "connect sensor".';
              }
          }
        } else {
          // 2. Call decoupled AIProvider
          final aiResponse = await aiProvider.generateResponse(
            prompt: rawInput,
            context: context,
            memory: conversationMemory,
          );

          // 3. Safety Constraint: reject AI-generated safety intents only when no
          // explicit tool call is present. If the AI asks to perform an action, route
          // it through SafeCook's authoritative handlers instead of mutating state.
          final isAiSafetyIntent =
              aiResponse.intent == SafeCookIntentType.checkGas ||
              aiResponse.intent == SafeCookIntentType.checkDistance ||
              aiResponse.intent == SafeCookIntentType.checkSafety ||
              aiResponse.intent == SafeCookIntentType.connectBluetooth ||
              aiResponse.intent == SafeCookIntentType.disconnectBluetooth ||
              aiResponse.intent == SafeCookIntentType.checkConnectionStatus ||
              aiResponse.intent == SafeCookIntentType.endCooking;

          if (aiResponse.toolCall != null && aiResponse.toolCall!.isNotEmpty) {
            final tCall = aiResponse.toolCall!;
            if (tCall == 'nextStep') {
              responseText = await _handleNextStep(context, tools);
            } else if (tCall == 'previousStep') {
              responseText = await _handlePreviousStep(context, tools);
            } else if (tCall == 'repeatStep') {
              responseText = await _handleRepeatStep(context, tools);
            } else if (tCall == 'goToStep') {
              final stepNum =
                  aiResponse.toolArguments['stepNumber'] as int? ?? 1;
              responseText = await _handleGoToStep(
                SafeCookIntent(
                  type: SafeCookIntentType.goToStep,
                  rawQuery: rawInput,
                  entities: {'stepNumber': stepNum},
                ),
                context,
                tools,
              );
            } else if (tCall == 'selectRecipe') {
              final index = aiResponse.toolArguments['index'] as int? ?? -1;
              responseText = _handleSelectRecipe(
                SafeCookIntent(
                  type: SafeCookIntentType.selectRecipe,
                  rawQuery: rawInput,
                  entities: {'index': index},
                ),
              );
            } else if (tCall == 'findRecipe') {
              responseText = _handleFindRecipe(
                SafeCookIntent(
                  type: SafeCookIntentType.findRecipe,
                  rawQuery: rawInput,
                  entities: {
                    'vegetarian': aiResponse.toolArguments['vegetarian'],
                    'quick': aiResponse.toolArguments['quick'],
                    'ingredient': aiResponse.toolArguments['ingredient'],
                    'category': aiResponse.toolArguments['category'],
                    'rawText': rawInput,
                  },
                ),
                tools,
              );
            } else if (tCall == 'startCooking') {
              responseText = await _handleStartCooking(context, tools);
            } else if (tCall == 'connectBluetooth') {
              responseText = await _handleConnectBluetooth(
                SafeCookIntent(
                  type: SafeCookIntentType.connectBluetooth,
                  rawQuery: rawInput,
                ),
                tools,
              );
            } else if (tCall == 'disconnectBluetooth') {
              responseText = await _handleDisconnectBluetooth(
                SafeCookIntent(
                  type: SafeCookIntentType.disconnectBluetooth,
                  rawQuery: rawInput,
                ),
                tools,
              );
            } else if (tCall == 'endCooking') {
              responseText = _handleEndCooking(context);
            } else if (tCall == 'webSearch') {
              final query = aiResponse.toolArguments['query'] as String? ?? rawInput;
              responseText = await _handleWebSearch(query, tools);
            } else {
              responseText = aiResponse.assistantText;
            }
          } else if (isAiSafetyIntent) {
            responseText =
                'For your safety, I cannot perform that safety command via the AI fallback. Please say a clear command like "check gas" or "connect sensor".';
          } else {
            responseText = aiResponse.assistantText;
          }
        }

        // Ultimate fallback if AI output is empty
        if (responseText.isEmpty) {
          responseText = unknownResult;
        }
      }
    }

    // Save final response and record the turn in conversation memory
    _mem.lastAssistantResponse = responseText;
    conversationMemory.addTurn(rawInput, responseText, intent.type.name);

    return responseText;
  }

  // =========================================================================
  // Handler methods
  // =========================================================================

  Future<String> _handleConfirmYes(
    SafeCookContext context,
    SafeCookTools tools,
  ) async {
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
        final recipe = _mem.selectedRecipe;
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
    final requestedCount = intent.entities['count'] as int? ?? 0;

    final results = tools.searchRecipes(
      vegetarian: intent.entities['vegetarian'] as bool?,
      quick: intent.entities['quick'] as bool?,
      ingredient: intent.entities['ingredient'] as String?,
      rawText: intent.entities['rawText'] as String?,
      category: intent.entities['category'] as String?,
    );

    // If searchRecipes returned nothing with the raw text but there are no
    // specific constraints either, return recipes from the full list.
    final hasConstraints =
        (intent.entities['ingredient'] as String? ?? '').isNotEmpty ||
        (intent.entities['category'] as String? ?? '').isNotEmpty ||
        (intent.entities['vegetarian'] as bool? ?? false) ||
        (intent.entities['quick'] as bool? ?? false);

    final effectiveResults = (results.isEmpty && !hasConstraints)
        ? kPredefinedRecipes
        : results;

    if (effectiveResults.isEmpty) {
      return "I couldn't find matching recipes. Try asking for a specific ingredient, cuisine, or say \"show me all recipes\".";
    }

    _mem.lastRecipeSearchResults = List.from(effectiveResults);

    // Apply requested count.
    final limit =
        (requestedCount > 0 && requestedCount < effectiveResults.length)
        ? requestedCount
        : effectiveResults.length;
    final limited = effectiveResults.take(limit).toList();

    if (limited.length == 1) {
      _mem.selectedRecipe = limited.first;
      _mem.conversationState = ConversationState.confirmingStart;
      final r = limited.first;
      final resp =
          'I found ${r.name}. It takes about ${r.cookingTime} minutes and serves ${r.servings} people. Would you like to start cooking?';
      _mem.lastAssistantResponse = resp;
      return resp;
    }

    _mem.conversationState = ConversationState.selectingRecipe;
    final names = limited.map((r) => r.name).toList();
    String listing = names
        .asMap()
        .entries
        .map((e) => '${e.key + 1}. ${e.value}')
        .join(', ');
    if (effectiveResults.length > limit) {
      listing += ', and ${effectiveResults.length - limit} more';
    }
    final resp =
        'I found ${effectiveResults.length} recipes. Showing $limit: $listing. Which would you like?';
    _mem.lastAssistantResponse = resp;
    return resp;
  }

  Future<String> _handleStartCooking(
    SafeCookContext context,
    SafeCookTools tools,
  ) async {
    if (_mem.isCookingActive) {
      {
        return 'A cooking session is already active.';
      }
    }
    var recipe = _mem.selectedRecipe;
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
    SafeCookContext context,
    SafeCookTools tools,
  ) async {
    if (!_mem.isCookingActive) {
      return 'Please select a recipe and start cooking first.';
    }
    final recipe = _mem.selectedRecipe;
    final stepIdx = _mem.currentStepIndex; // authoritative source from UI
    final total = recipe?.steps.length ?? 0;

    if (recipe == null || total == 0) {
      return 'No active recipe is loaded.';
    }

    if (stepIdx >= total - 1) {
      return 'You are already on the last step. Say "end cooking" when you\'re done.';
    }

    final memoryIndexBefore = _mem.currentStepIndex;
    final result = await tools.nextStep();
    final memoryIndexAfter = _mem.currentStepIndex;

    debugPrint(
      '[SafeCook STEP]\n'
      'command="next step"\n'
      'beforeIndex=$stepIdx\n'
      'contextIndex=${_mem.currentStepIndex}\n'
      'memoryIndexBefore=$memoryIndexBefore\n'
      'toolCalled=true\n'
      'toolResult=${result.success}\n'
      'memoryIndexAfter=$memoryIndexAfter\n'
      'uiIndex=$memoryIndexAfter\n'
      'responseStep=${memoryIndexAfter + 1}',
    );

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
    SafeCookContext context,
    SafeCookTools tools,
  ) async {
    if (!_mem.isCookingActive) {
      return 'Please start cooking first.';
    }
    final recipe = _mem.selectedRecipe;
    final stepIdx = _mem.currentStepIndex;

    if (recipe == null) return 'No active recipe is loaded.';

    if (stepIdx <= 0) {
      return 'You are already on step 1.';
    }

    final memoryIndexBefore = _mem.currentStepIndex;
    final result = await tools.previousStep();
    final memoryIndexAfter = _mem.currentStepIndex;

    debugPrint(
      '[SafeCook STEP]\n'
      'command="previous step"\n'
      'beforeIndex=$stepIdx\n'
      'contextIndex=${_mem.currentStepIndex}\n'
      'memoryIndexBefore=$memoryIndexBefore\n'
      'toolCalled=true\n'
      'toolResult=${result.success}\n'
      'memoryIndexAfter=$memoryIndexAfter\n'
      'uiIndex=$memoryIndexAfter\n'
      'responseStep=${memoryIndexAfter + 1}',
    );

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
    SafeCookIntent intent,
    SafeCookContext context,
    SafeCookTools tools,
  ) async {
    if (!_mem.isCookingActive) {
      return 'Please start cooking first.';
    }
    final rawStep = intent.entities['stepNumber'] as int? ?? -1;
    final recipe = _mem.selectedRecipe;
    final total = recipe?.steps.length ?? 0;

    if (recipe == null || total == 0) return 'No active recipe is loaded.';

    // Clamp stepNumber safely to [1, total] to allow boundaries and excessive numbers
    final stepNumber = rawStep.clamp(1, total);

    final memoryIndexBefore = _mem.currentStepIndex;
    final result = await tools.goToStep(stepNumber);
    final memoryIndexAfter = _mem.currentStepIndex;

    debugPrint(
      '[SafeCook STEP]\n'
      'command="go to step"\n'
      'beforeIndex=${_mem.currentStepIndex}\n'
      'contextIndex=${_mem.currentStepIndex}\n'
      'memoryIndexBefore=$memoryIndexBefore\n'
      'toolCalled=true\n'
      'toolResult=${result.success}\n'
      'memoryIndexAfter=$memoryIndexAfter\n'
      'uiIndex=$memoryIndexAfter\n'
      'responseStep=${memoryIndexAfter + 1}',
    );

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
    SafeCookContext context,
    SafeCookTools tools,
  ) async {
    if (!_mem.isCookingActive) {
      return 'You are not currently in a cooking session.';
    }
    final recipe = _mem.selectedRecipe;
    final stepIdx = _mem.currentStepIndex;

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
    final r = _mem.selectedRecipe;
    if (r == null) {
      return 'Please select a recipe first before checking ingredients.';
    }
    final list = r.ingredients.join(', ');
    return 'The ingredients for ${r.name} are: $list.';
  }

  String _handleReadSafetyNotes(SafeCookContext context) {
    final r = _mem.selectedRecipe;
    if (r == null) {
      return 'Please select a recipe first.';
    }
    if (r.safetyNotes.isEmpty) {
      return 'No specific safety notes for ${r.name}. Always keep the stove area clear and monitor the heat.';
    }
    return 'Safety notes for ${r.name}: ${r.safetyNotes.join('. ')}.';
  }

  String _handleCheckGas(SafeCookContext context) {
    final engine = SafeCookSafetyEngine();
    final gasPercentage = engine.gasPercentage ?? context.gasPercent;
    if (gasPercentage == null) {
      return "I can't verify the gas level because the gas sensor is not currently providing a valid reading.";
    }
    final pct = gasPercentage.toStringAsFixed(0);
    final isGasSafe = gasPercentage < SafeCookSafetyPolicy.gasCautionThreshold;
    return 'Gas level is $pct percent. The current gas condition is ${isGasSafe ? 'safe' : 'unsafe'}.';
  }

  String _handleCheckDistance(SafeCookContext context) {
    final engine = SafeCookSafetyEngine();
    final chefDistanceCm = engine.chefDistanceCm ?? context.distanceCm;
    if (chefDistanceCm == null) {
      return "I can't verify your distance because the distance sensor is not currently providing a valid reading.";
    }
    final cm = chefDistanceCm.toStringAsFixed(0);
    final isDistanceSafe =
        chefDistanceCm > SafeCookSafetyPolicy.distanceCautionThreshold;
    if (isDistanceSafe) {
      return 'Your distance from the vessel is $cm centimetres. That is currently safe.';
    } else {
      return "Your distance from the vessel is $cm centimetres. You're too close to the cooking vessel. Please step back.";
    }
  }

  String _handleCheckSafety(SafeCookContext context) {
    final engine = SafeCookSafetyEngine();
    final isConnected =
        engine.isBluetoothConnected || context.isBluetoothConnected;
    final state =
        (engine.currentState != SafeCookSafetyState.sensorUnavailable ||
            !isConnected)
        ? engine.currentState
        : _mapStringToState(context.safetyState);

    if (state == SafeCookSafetyState.sensorUnavailable) {
      return "I can't verify the safety status because the sensors are not currently providing valid readings.";
    }

    final gasPercentage = engine.gasPercentage ?? context.gasPercent;
    final chefDistanceCm = engine.chefDistanceCm ?? context.distanceCm;

    final gasPart = gasPercentage != null
        ? 'Gas level is ${gasPercentage.toStringAsFixed(0)} percent.'
        : "I can't verify the gas level.";

    final distPart = chefDistanceCm != null
        ? 'Your distance from the vessel is ${chefDistanceCm.toStringAsFixed(0)} centimetres.'
        : "I can't verify your distance.";

    switch (state) {
      case SafeCookSafetyState.safe:
        return '$distPart $gasPart Your cooking environment is currently safe.';
      case SafeCookSafetyState.caution:
        return '$distPart $gasPart Caution is advised. SafeCook has detected elevated readings.';
      case SafeCookSafetyState.gasAlert:
        return '$distPart $gasPart Warning: elevated gas level detected. Please check your burner.';
      case SafeCookSafetyState.distanceAlert:
        return "$distPart $gasPart Warning: you're too close to the cooking vessel. Please step back.";
      case SafeCookSafetyState.critical:
        return '$distPart $gasPart Critical alert: both gas and distance readings are unsafe. Please take immediate action.';
      default:
        return "I can't verify the safety sensors right now.";
    }
  }

  SafeCookSafetyState _mapStringToState(String stateStr) {
    switch (stateStr) {
      case 'SAFE':
        return SafeCookSafetyState.safe;
      case 'CAUTION':
        return SafeCookSafetyState.caution;
      case 'GAS ALERT':
        return SafeCookSafetyState.gasAlert;
      case 'DISTANCE ALERT':
        return SafeCookSafetyState.distanceAlert;
      case 'CRITICAL':
        return SafeCookSafetyState.critical;
      default:
        return SafeCookSafetyState.sensorUnavailable;
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
    debugPrint(
      '[SafeCook BT]\n'
      'recognized="${intent.rawQuery}"\n'
      'intent=checkConnectionStatus\n'
      'tool=bluetoothStatus\n'
      'nativeOperationStarted=false\n'
      'nativeOperationResult=${result.message}\n'
      'actualConnected=${_mem.isBluetoothConnected}',
    );
    return result.success
        ? 'The sensor is connected and transmitting data.'
        : 'The sensor is not connected. Say "connect sensor" to connect.';
  }

  Future<String> _handleConnectBluetooth(
    SafeCookIntent intent,
    SafeCookTools tools,
  ) async {
    if (_mem.isBluetoothConnected) {
      return 'The sensor is already connected.';
    }
    final result = await tools.connectBluetooth();
    logTool('connectBluetooth', result);
    if (result.success) {
      _mem.isBluetoothConnected = true;
    }
    debugPrint(
      '[SafeCook BT]\n'
      'recognized="${intent.rawQuery}"\n'
      'intent=connectBluetooth\n'
      'tool=connectBluetooth\n'
      'nativeOperationStarted=true\n'
      'nativeOperationResult=${result.message}\n'
      'actualConnected=${_mem.isBluetoothConnected}',
    );
    return result.success
        ? 'Connection successful. The sensor is now active.'
        : 'I was unable to connect to the sensor. ${result.message} Please make sure the device is powered on and paired.';
  }

  Future<String> _handleDisconnectBluetooth(
    SafeCookIntent intent,
    SafeCookTools tools,
  ) async {
    if (!_mem.isBluetoothConnected) {
      return 'The sensor is already disconnected.';
    }
    final result = await tools.disconnectBluetooth();
    logTool('disconnectBluetooth', result);
    if (result.success) {
      _mem.isBluetoothConnected = false;
    }
    debugPrint(
      '[SafeCook BT]\n'
      'recognized="${intent.rawQuery}"\n'
      'intent=disconnectBluetooth\n'
      'tool=disconnectBluetooth\n'
      'nativeOperationStarted=true\n'
      'nativeOperationResult=${result.message}\n'
      'actualConnected=${_mem.isBluetoothConnected}',
    );
    return result.success
        ? 'Sensor disconnected.'
        : 'I was unable to disconnect. ${result.message}';
  }

  Future<String> _handleWebSearch(
    String query,
    SafeCookTools tools,
  ) async {
    _mem.pendingWebQuery = query;
    if (tools.webSearch == null) {
      return 'I was unable to search the web right now. Web search is not wired.';
    }
    final result = await tools.webSearch!(query);
    logTool('webSearch', result);
    if (result.success) {
      _mem.pendingWebQuery = null;
      final response = result.data as WebSearchResponse;
      if (response.answer != null && response.answer!.trim().isNotEmpty) {
        return response.answer!;
      }
      if (response.results.isNotEmpty) {
        final topResult = response.results.first;
        return '${topResult.snippet} (Source: ${topResult.title})';
      }
      return 'I found no results online for "$query".';
    } else {
      return 'I was unable to search the web right now. ${result.message}';
    }
  }

  String _handleUnknown(
    String rawInput,
    SafeCookContext context,
    SafeCookTools tools,
  ) {
    final normalized = _norm(rawInput);
    final cleanedQuery = _cleanQuery(normalized);

    // Try to resolve a recipe first
    if (!_mem.isCookingActive &&
        _mem.conversationState != ConversationState.confirmingEnd) {
      final (resolvedRecipe, matchedRecipes) = _resolveRecipe(
        normalized,
        cleanedQuery,
      );

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
        if (q.contains('how long') ||
            q.contains('time') ||
            q.contains('duration')) {
          return '${r.name} takes about ${r.cookingTime} minutes to prepare.';
        }
        if (q.contains('how to') ||
            q.contains('step') ||
            q.contains('instruction')) {
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
      if (q.contains('substitute') ||
          q.contains('instead') ||
          q.contains('replace')) {
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
    // Boiling vs steaming method comparison
    if ((q.contains('boil') || q.contains('steam')) &&
        (q.contains('difference') ||
            q.contains('vs') ||
            q.contains('versus') ||
            q.contains('healthier') ||
            q.contains('different') ||
            q.contains('better') ||
            q.contains('when should'))) {
      return 'Boiling cooks food by fully submerging it in water at 100°C, which can cause water-soluble vitamins to leach out. '
          'Steaming cooks food using hot vapour above boiling water, preserving more nutrients and natural flavours. '
          'Steaming is generally considered healthier for vegetables. '
          'Use boiling for pasta, rice, and potatoes; use steaming for delicate vegetables, fish, and dim sum.';
    }
    return null;
  }
}
