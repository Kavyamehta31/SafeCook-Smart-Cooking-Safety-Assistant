import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'safecook_context.dart';
import 'safecook_intent.dart';
import 'safecook_conversation_memory.dart';
import 'safecook_agent.dart';
import '../data/recipes.dart';

abstract class AIProvider {
  Future<AIResponse> generateResponse({
    required String prompt,
    required SafeCookContext context,
    required SafeCookConversationMemory memory,
  });
}

class AIResponse {
  final String assistantText;
  final SafeCookIntentType intent;
  final String? toolCall;
  final Map<String, dynamic> toolArguments;
  final bool requiresConfirmation;
  final double confidence;

  AIResponse({
    required this.assistantText,
    required this.intent,
    this.toolCall,
    this.toolArguments = const {},
    this.requiresConfirmation = false,
    this.confidence = 1.0,
  });

  Map<String, dynamic> toJson() => {
    'assistantText': assistantText,
    'intent': intent.name,
    'toolCall': toolCall,
    'toolArguments': toolArguments,
    'requiresConfirmation': requiresConfirmation,
    'confidence': confidence,
  };

  factory AIResponse.fromJson(Map<String, dynamic> json) {
    SafeCookIntentType resolvedIntent = SafeCookIntentType.unknown;
    final intentStr = json['intent'] as String?;
    if (intentStr != null) {
      for (final type in SafeCookIntentType.values) {
        if (type.name == intentStr) {
          resolvedIntent = type;
          break;
        }
      }
    }

    return AIResponse(
      assistantText: json['assistantText'] as String? ?? '',
      intent: resolvedIntent,
      toolCall: json['toolCall'] as String?,
      toolArguments:
          (json['toolArguments'] as Map<String, dynamic>?) ?? const {},
      requiresConfirmation: json['requiresConfirmation'] as bool? ?? false,
      confidence: (json['confidence'] as num?)?.toDouble() ?? 1.0,
    );
  }
}

// ---------------------------------------------------------------------------
// LocalMockAIProvider — deterministic conversational solver for testing
// ---------------------------------------------------------------------------
class LocalMockAIProvider implements AIProvider {
  @override
  Future<AIResponse> generateResponse({
    required String prompt,
    required SafeCookContext context,
    required SafeCookConversationMemory memory,
  }) async {
    final q = prompt.toLowerCase().trim();

    // 1. Contextual select from search results (e.g. "the second one")
    if (q.contains('second') || q.contains('2nd')) {
      final results = SafeCookAgent().memory.lastRecipeSearchResults;
      if (results.length > 1) {
        final r = results[1];
        return AIResponse(
          assistantText:
              'You selected ${r.name}. It takes about ${r.cookingTime} minutes. Would you like to start cooking?',
          intent: SafeCookIntentType.selectRecipe,
          toolCall: 'selectRecipe',
          toolArguments: {'index': 1},
          confidence: 0.95,
        );
      }
    }
    if (q.contains('first') || q.contains('1st') || q.contains('number one')) {
      final results = SafeCookAgent().memory.lastRecipeSearchResults;
      if (results.isNotEmpty) {
        final r = results.first;
        return AIResponse(
          assistantText:
              'You selected ${r.name}. It takes about ${r.cookingTime} minutes. Would you like to start cooking?',
          intent: SafeCookIntentType.selectRecipe,
          toolCall: 'selectRecipe',
          toolArguments: {'index': 0},
          confidence: 0.95,
        );
      }
    }

    // 2. Pronoun resolution of "it" / "that" referring to recipe or step
    if (q.contains('how long') &&
        (q.contains('it take') || q.contains('cook it'))) {
      final r = context.recipe ?? SafeCookAgent().memory.selectedRecipe;
      if (r != null) {
        return AIResponse(
          assistantText:
              '${r.name} takes about ${r.cookingTime} minutes to prepare.',
          intent: SafeCookIntentType.cookingQuestion,
          confidence: 0.9,
        );
      }
    }

    if (q.contains('what was that') ||
        q.contains('repeat that') ||
        q.contains('what is that step')) {
      final r = context.recipe ?? SafeCookAgent().memory.selectedRecipe;
      final stepIdx = context.currentStepIndex;
      if (r != null && stepIdx < r.steps.length) {
        final step = r.steps[stepIdx];
        return AIResponse(
          assistantText: 'Step ${stepIdx + 1}: ${step.voiceInstruction}',
          intent: SafeCookIntentType.readStep,
          toolCall: 'repeatStep',
          confidence: 0.9,
        );
      }
    }

    // 3. Local cooking knowledge substitutes
    if (q.contains('substitute') ||
        q.contains('instead of') ||
        q.contains('replace')) {
      if (q.contains('coriander') || q.contains('cilantro')) {
        return AIResponse(
          assistantText:
              'You can substitute coriander with parsley, celery leaves, or fresh dill.',
          intent: SafeCookIntentType.cookingQuestion,
          confidence: 0.95,
        );
      }
      if (q.contains('butter') || q.contains('ghee')) {
        return AIResponse(
          assistantText:
              'You can substitute butter or ghee with olive oil, coconut oil, or applesauce.',
          intent: SafeCookIntentType.cookingQuestion,
          confidence: 0.95,
        );
      }
      if (q.contains('paneer') || q.contains('cottage cheese')) {
        return AIResponse(
          assistantText:
              'You can substitute paneer with firm tofu, ricotta, or halloumi.',
          intent: SafeCookIntentType.cookingQuestion,
          confidence: 0.95,
        );
      }
      if (q.contains('onion')) {
        return AIResponse(
          assistantText:
              'For onions, you can use leeks, shallots, green onions, or a pinch of asafoetida powder.',
          intent: SafeCookIntentType.cookingQuestion,
          confidence: 0.95,
        );
      }
    }

    if (q.contains('potato') && q.contains('boil')) {
      return AIResponse(
        assistantText:
            'Boiling potatoes generally takes 15 to 20 minutes for medium pieces, or 25 minutes for whole potatoes.',
        intent: SafeCookIntentType.cookingQuestion,
        confidence: 0.95,
      );
    }
    if (q.contains('egg') && q.contains('boil')) {
      return AIResponse(
        assistantText:
            'For soft-boiled eggs, boil for 6 minutes. For medium, 8 minutes. For hard-boiled, 10 minutes.',
        intent: SafeCookIntentType.cookingQuestion,
        confidence: 0.95,
      );
    }

    // 4. Default conversational replies
    if (q.contains('what else') ||
        q.contains('other recipes') ||
        q.contains('options')) {
      final names = kPredefinedRecipes.take(3).map((r) => r.name).join(', ');
      return AIResponse(
        assistantText:
            'I can help you cook recipes like $names. Which would you like to cook?',
        intent: SafeCookIntentType.findRecipe,
        confidence: 0.8,
      );
    }

    // 5. Cooking method comparisons (backup — normally caught by NLU + local knowledge)
    if ((q.contains('boil') || q.contains('steam')) &&
        (q.contains('difference') ||
            q.contains('vs') ||
            q.contains('versus') ||
            q.contains('healthier') ||
            q.contains('different') ||
            q.contains('better') ||
            q.contains('when should'))) {
      return AIResponse(
        assistantText:
            'Boiling cooks food by submerging it in boiling water at 100°C. '
            'Steaming uses hot vapour above the water, preserving more nutrients and vitamins. '
            'Steaming is generally healthier for vegetables; boiling works well for pasta, rice, and potatoes.',
        intent: SafeCookIntentType.cookingQuestion,
        confidence: 0.9,
      );
    }

    final isGeneralKnowledgePrompt =
        q.contains('what is') ||
        q.contains('why') ||
        q.contains('how do i') ||
        q.contains('can i') ||
        q.contains('difference between') ||
        q.contains('what happens if') ||
        q.contains('when is') ||
        q.contains('how long') ||
        q.contains('substitute') ||
        q.contains('thicken') ||
        q.contains('blanch') ||
        q.contains('roast') ||
        q.contains('bake') ||
        q.contains('fry') ||
        q.contains('saute') ||
        q.contains('chop') ||
        q.contains('cut');

    final fallbackAnswer = isGeneralKnowledgePrompt
        ? 'I can answer broader cooking technique and general knowledge questions when the online Gemini provider is available. On this device, I can still help with recipe steps, safety checks, and recipe navigation.'
        : 'I can help with recipe guidance, safety checks, or cooking steps. Ask me about a recipe or a current safety question.';

    return AIResponse(
      assistantText: fallbackAnswer,
      intent: SafeCookIntentType.unknown,
      confidence: 0.5,
    );
  }
}

// ---------------------------------------------------------------------------
// GeminiAIProvider — actual Gemini API caller using JSON Mode
//
// KEY CONFIGURATION (DEVELOPMENT):
//   Pass the API key at build/run time via --dart-define:
//     flutter run --dart-define=GEMINI_API_KEY=your_key_here
//     flutter build apk --dart-define=GEMINI_API_KEY=your_key_here
//
//   Never hard-code the key in source.
//   Never commit the key to Git.
//   For production, use a backend/proxy so the key is not in the APK.
//
// KEY CONFIGURATION (PRODUCTION):
//   Use a secure backend proxy that SafeCook calls with app-level auth.
//   The backend calls Gemini with a server-side key never exposed to the APK.
// ---------------------------------------------------------------------------
class GeminiAIProvider implements AIProvider {
  // Read key injected at build time via --dart-define=GEMINI_API_KEY=...
  // This works on Android APKs. Platform.environment does NOT.
  static const _dartDefineKey = String.fromEnvironment('GEMINI_API_KEY');

  final String? apiKey;
  final String modelName;
  static const _timeoutSeconds = 10;

  // Google Gemini model availability changes over time. For new-user accounts,
  // current stable cost-efficient text models are 3.x Flash variants.
  // Keep the direct generateContent flow and use a supported lightweight model.
  GeminiAIProvider({this.apiKey, this.modelName = 'gemini-3.5-flash-lite'});

  /// Returns the resolved API key (explicit > dart-define). Empty = not configured.
  String get _resolvedKey =>
      (apiKey != null && apiKey!.isNotEmpty) ? apiKey! : _dartDefineKey;

  bool get isConfigured => _resolvedKey.isNotEmpty;

  @override
  Future<AIResponse> generateResponse({
    required String prompt,
    required SafeCookContext context,
    required SafeCookConversationMemory memory,
  }) async {
    if (!isConfigured) {
      debugPrint(
        '[SafeCook AI] provider=LocalMock reason=GEMINI_API_KEY not configured',
      );
      return LocalMockAIProvider().generateResponse(
        prompt: prompt,
        context: context,
        memory: memory,
      );
    }

    debugPrint('[SafeCook AI] provider=Gemini model=$modelName');
    final promptPreview = prompt.length > 60
        ? '${prompt.substring(0, 60)}...'
        : prompt;
    debugPrint('[SafeCook AI] request started prompt="$promptPreview"');

    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: _timeoutSeconds);

      final uri = Uri.parse(
        'https://generativelanguage.googleapis.com/v1beta/models/$modelName:generateContent',
      );
      debugPrint(
        '[SafeCook AI] request url=https://generativelanguage.googleapis.com/v1beta/models/$modelName:generateContent',
      );

      // Bounded conversation history — last 3 turns for context
      final recentHistory = memory.history.length > 3
          ? memory.history.sublist(memory.history.length - 3)
          : memory.history;

      final historyList = recentHistory
          .expand(
            (turn) => [
              {
                'role': 'user',
                'parts': [
                  {'text': turn.userUtterance},
                ],
              },
              {
                'role': 'model',
                'parts': [
                  {'text': turn.assistantResponse},
                ],
              },
            ],
          )
          .toList();

      final systemInstruction =
          'You are SafeCook, a smart cooking safety assistant embedded in a mobile app. '
          'You answer general cooking questions knowledgeably and conversationally. '
          'You also help users navigate cooking recipes step by step.\n\n'
          'CURRENT APP STATE:\n'
          '- Cooking active: ${context.isCookingActive}\n'
          '- Current recipe: ${context.recipe?.name ?? "none"}\n'
          '- Current step: ${context.isCookingActive ? context.currentStepIndex + 1 : "N/A"}\n'
          '- Safety state: ${context.safetyState}\n\n'
          'IMPORTANT RULES:\n'
          '1. For general cooking questions (e.g. techniques, methods, substitutions, science), '
          '   set intent to "cookingQuestion" and provide a clear, helpful answer in assistantText.\n'
          '2. Do NOT answer or fabricate safety sensor data (gas level, distance). '
          '   If asked about actual gas or distance readings, say the device sensors handle that.\n'
          '3. Resolve pronouns ("it", "that one") using the conversation history.\n'
          '4. For recipe navigation (next step, previous step), set toolCall accordingly.\n'
          '5. Keep assistantText conversational and appropriate for text-to-speech.\n\n'
          'RESPOND IN STRICT JSON:\n'
          '{\n'
          '  "assistantText": "your spoken response here",\n'
          '  "intent": "cookingQuestion",\n'
          '  "toolCall": null,\n'
          '  "toolArguments": {},\n'
          '  "requiresConfirmation": false,\n'
          '  "confidence": 0.95\n'
          '}\n'
          'Available intent values: greeting, findRecipe, selectRecipe, startCooking, '
          'nextStep, previousStep, goToStep, readStep, readIngredients, readSafetyNotes, '
          'checkGas, checkDistance, checkSafety, checkTime, checkConnectionStatus, '
          'connectBluetooth, disconnectBluetooth, endCooking, confirmYes, confirmNo, '
          'help, cookingQuestion, webSearch, unknown.';

      final requestBody = {
        'contents': [
          ...historyList,
          {
            'role': 'user',
            'parts': [
              {'text': prompt},
            ],
          },
        ],
        'systemInstruction': {
          'parts': [
            {'text': systemInstruction},
          ],
        },
        'generationConfig': {
          'responseMimeType': 'application/json',
          'maxOutputTokens': 300,
        },
      };

      final request = await client
          .postUrl(uri)
          .timeout(const Duration(seconds: _timeoutSeconds));
      request.headers.set('Content-Type', 'application/json');
      request.headers.set('x-goog-api-key', _resolvedKey);
      request.write(jsonEncode(requestBody));

      final response = await request.close().timeout(
        const Duration(seconds: _timeoutSeconds),
      );

      if (response.statusCode != 200) {
        final errorBody = await response
            .transform(utf8.decoder)
            .join()
            .timeout(const Duration(seconds: _timeoutSeconds));
        debugPrint('[SafeCook AI] HTTP status=${response.statusCode}');
        debugPrint('[SafeCook AI] error body=$errorBody');
        debugPrint(
          '[SafeCook AI] fallback=LocalMock reason=HTTP ${response.statusCode}',
        );
        client.close();
        return _networkUnavailableResponse();
      }

      final responseBody = await response
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(seconds: _timeoutSeconds));
      client.close();

      final parsed = jsonDecode(responseBody);
      final text =
          parsed['candidates']?[0]?['content']?['parts']?[0]?['text']
              as String?;

      if (text != null && text.trim().isNotEmpty) {
        try {
          final jsonResponse = jsonDecode(text.trim());
          final aiResp = AIResponse.fromJson(jsonResponse);
          final textPreview = aiResp.assistantText.length > 60
              ? '${aiResp.assistantText.substring(0, 60)}...'
              : aiResp.assistantText;
          debugPrint(
            '[SafeCook AI] response received intent=${aiResp.intent.name} text="$textPreview"',
          );
          return aiResp;
        } catch (_) {
          // Gemini returned non-JSON text despite responseMimeType — use raw text
          debugPrint('[SafeCook AI] fallback=rawText reason=JSON parse failed');
          return AIResponse(
            assistantText: text.trim(),
            intent: SafeCookIntentType.cookingQuestion,
            confidence: 0.7,
          );
        }
      }

      debugPrint('[SafeCook AI] fallback=LocalMock reason=empty response body');
    } on TimeoutException {
      debugPrint(
        '[SafeCook AI] fallback=LocalMock reason=timeout after ${_timeoutSeconds}s',
      );
      return _networkUnavailableResponse();
    } catch (e) {
      debugPrint('[SafeCook AI] fallback=LocalMock reason=${e.runtimeType}');
    }

    return _networkUnavailableResponse();
  }

  /// Graceful spoken response when network/Gemini is unavailable.
  static AIResponse _networkUnavailableResponse() => AIResponse(
    assistantText:
        "I can't reach my online cooking assistant right now, but I can still "
        'help with recipe navigation, sensor safety, and the recipes stored on this device. '
        'Try asking me to find a recipe, check safety, or navigate a cooking step.',
    intent: SafeCookIntentType.unknown,
    confidence: 0.0,
  );
}
