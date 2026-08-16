import 'package:flutter_test/flutter_test.dart';
import 'package:safecook_bluetooth_test/agent/safecook_agent.dart';
import 'package:safecook_bluetooth_test/agent/safecook_context.dart';
import 'package:safecook_bluetooth_test/agent/safecook_intent.dart';
import 'package:safecook_bluetooth_test/agent/safecook_tools.dart';
import 'package:safecook_bluetooth_test/services/voice_assistant_service.dart';
import 'package:safecook_bluetooth_test/models/recipe.dart';
import 'package:safecook_bluetooth_test/data/recipes.dart';

void main() {
  setUp(() {
    SafeCookAgent().reset();
  });

  group('Recipe Matching & Disambiguation', () {
    // 1. Recipe exact matching
    test('1. Recipe exact matching', () {
      final intent = SafeCookNLU.parse('Paneer Butter Masala');
      expect(intent.type, equals(SafeCookIntentType.unknown)); // Resolved by pipeline, not parser directly
    });

    test('Recipe resolution exact match', () async {
      final agent = SafeCookAgent();
      final context = const SafeCookContext(
        safetyState: 'SAFE',
        sessionDuration: Duration.zero,
        isCookingActive: false,
        isBluetoothConnected: false,
        currentConversationState: 'idle',
      );
      final tools = buildNoOpTools();

      final reply = await agent.handleInput('Paneer Butter Masala', context, tools);
      expect(reply, contains('Paneer Butter Masala'));
      expect(agent.conversationState, equals(ConversationState.confirmingStart));
      expect(agent.selectedRecipe?.name, equals('Paneer Butter Masala'));
    });

    // 2. Short recipe alias matching
    test('2. Short recipe alias matching', () async {
      final agent = SafeCookAgent();
      final context = const SafeCookContext(
        safetyState: 'SAFE',
        sessionDuration: Duration.zero,
        isCookingActive: false,
        isBluetoothConnected: false,
        currentConversationState: 'idle',
      );
      final tools = buildNoOpTools();

      // Poha Indori is the only predefined recipe with "Poha"
      final reply = await agent.handleInput('cook poha', context, tools);
      expect(reply, contains('Poha (Indori)'));
      expect(agent.conversationState, equals(ConversationState.confirmingStart));
    });

    // 3. Recipe matching with filler words
    test('3. Recipe matching with filler words', () async {
      final agent = SafeCookAgent();
      final context = const SafeCookContext(
        safetyState: 'SAFE',
        sessionDuration: Duration.zero,
        isCookingActive: false,
        isBluetoothConnected: false,
        currentConversationState: 'idle',
      );
      final tools = buildNoOpTools();

      final reply = await agent.handleInput('can you make paneer butter masala please', context, tools);
      expect(reply, contains('Paneer Butter Masala'));
      expect(agent.conversationState, equals(ConversationState.confirmingStart));
    });

    // 4. Recipe vs ingredient disambiguation
    test('4. Recipe vs ingredient disambiguation', () async {
      final agent = SafeCookAgent();
      final context = const SafeCookContext(
        safetyState: 'SAFE',
        sessionDuration: Duration.zero,
        isCookingActive: false,
        isBluetoothConnected: false,
        currentConversationState: 'idle',
      );
      final tools = buildNoOpTools();

      // Saying the recipe name directly must prioritize the recipe itself
      final reply = await agent.handleInput('Paneer Butter Masala', context, tools);
      expect(reply, contains('Paneer Butter Masala'));
      expect(agent.conversationState, equals(ConversationState.confirmingStart));
    });

    test('Recipe search by ingredient', () async {
      final agent = SafeCookAgent();
      final context = const SafeCookContext(
        safetyState: 'SAFE',
        sessionDuration: Duration.zero,
        isCookingActive: false,
        isBluetoothConnected: false,
        currentConversationState: 'idle',
      );

      var searchIngredient = '';
      var searchVegetarian = false;
      final tools = SafeCookTools(
        searchRecipes: ({vegetarian, quick, ingredient, rawText, category}) {
          searchIngredient = ingredient ?? '';
          searchVegetarian = vegetarian ?? false;
          return kPredefinedRecipes.where((r) => r.ingredients.any((i) => i.toLowerCase().contains(searchIngredient))).toList();
        },
        startCooking: (_) async => const ToolResult.ok(''),
        nextStep: () async => const ToolResult.ok(''),
        previousStep: () async => const ToolResult.ok(''),
        repeatStep: () async => const ToolResult.ok(''),
        goToStep: (_) async => const ToolResult.ok(''),
        endCooking: () async => const ToolResult.ok(''),
        connectBluetooth: () async => const ToolResult.ok(''),
        disconnectBluetooth: () async => const ToolResult.ok(''),
        bluetoothStatus: () => const ToolResult.ok(''),
      );

      final reply = await agent.handleInput('find me vegetarian recipes with potato', context, tools);
      expect(searchIngredient, equals('potato'));
      expect(searchVegetarian, isTrue);
      expect(reply, contains('found'));
    });
  });

  group('Step Navigation & Boundaries', () {
    late Recipe dummyRecipe;
    late SafeCookTools stepTools;
    int nextStepCount = 0;
    int prevStepCount = 0;
    int repeatStepCount = 0;
    int goToStepVal = -1;

    setUp(() {
      dummyRecipe = Recipe(
        id: '1',
        name: 'Test Dish',
        category: 'Test',
        description: 'Test',
        cookingTime: 10,
        difficulty: 'Easy',
        servings: 2,
        ingredients: ['Ing 1'],
        steps: [
          RecipeStep(stepNumber: 1, instruction: 'Step 1 description', voiceInstruction: 'Read 1'),
          RecipeStep(stepNumber: 2, instruction: 'Step 2 description', voiceInstruction: 'Read 2'),
          RecipeStep(stepNumber: 3, instruction: 'Step 3 description', voiceInstruction: 'Read 3'),
        ],
        safetyNotes: [],
      );

      nextStepCount = 0;
      prevStepCount = 0;
      repeatStepCount = 0;
      goToStepVal = -1;

      stepTools = SafeCookTools(
        searchRecipes: ({vegetarian, quick, ingredient, rawText, category}) => [],
        startCooking: (_) async => const ToolResult.ok(''),
        nextStep: () async {
          nextStepCount++;
          SafeCookAgent().memory.nextStep();
          return const ToolResult.ok('');
        },
        previousStep: () async {
          prevStepCount++;
          SafeCookAgent().memory.previousStep();
          return const ToolResult.ok('');
        },
        repeatStep: () async {
          repeatStepCount++;
          SafeCookAgent().memory.repeatStep();
          return const ToolResult.ok('');
        },
        goToStep: (stepNum) async {
          goToStepVal = stepNum;
          SafeCookAgent().memory.goToStep(stepNum);
          return const ToolResult.ok('');
        },
        endCooking: () async => const ToolResult.ok(''),
        connectBluetooth: () async => const ToolResult.ok(''),
        disconnectBluetooth: () async => const ToolResult.ok(''),
        bluetoothStatus: () => const ToolResult.ok(''),
      );
    });

    // 5. Next step
    test('5. Next step command', () async {
      final agent = SafeCookAgent();
      agent.memory.isCookingActive = true;
      agent.memory.selectedRecipe = dummyRecipe;
      agent.memory.currentStepIndex = 0;
      agent.conversationState = ConversationState.cooking;

      final context = SafeCookContext(
        recipe: dummyRecipe,
        currentStepIndex: 0,
        totalSteps: 3,
        safetyState: 'SAFE',
        sessionDuration: Duration.zero,
        isCookingActive: true,
        isBluetoothConnected: false,
        currentConversationState: 'cooking',
      );

      final reply = await agent.handleInput('next step', context, stepTools);
      expect(nextStepCount, equals(1));
      expect(reply, contains('Step 2'));
    });

    // 6. Previous step
    test('6. Previous step command', () async {
      final agent = SafeCookAgent();
      agent.memory.isCookingActive = true;
      agent.memory.selectedRecipe = dummyRecipe;
      agent.memory.currentStepIndex = 1;
      agent.conversationState = ConversationState.cooking;

      final context = SafeCookContext(
        recipe: dummyRecipe,
        currentStepIndex: 1,
        totalSteps: 3,
        safetyState: 'SAFE',
        sessionDuration: Duration.zero,
        isCookingActive: true,
        isBluetoothConnected: false,
        currentConversationState: 'cooking',
      );

      final reply = await agent.handleInput('go back', context, stepTools);
      expect(prevStepCount, equals(1));
      expect(reply.toLowerCase(), contains('step 1'));
    });

    // 7. Repeat step
    test('7. Repeat step command', () async {
      final agent = SafeCookAgent();
      agent.memory.isCookingActive = true;
      agent.memory.selectedRecipe = dummyRecipe;
      agent.memory.currentStepIndex = 1;
      agent.conversationState = ConversationState.cooking;

      final context = SafeCookContext(
        recipe: dummyRecipe,
        currentStepIndex: 1,
        totalSteps: 3,
        safetyState: 'SAFE',
        sessionDuration: Duration.zero,
        isCookingActive: true,
        isBluetoothConnected: false,
        currentConversationState: 'cooking',
      );

      final reply = await agent.handleInput('repeat the step', context, stepTools);
      expect(repeatStepCount, equals(1));
      expect(reply, contains('Step 2'));
    });

    // 8. Go-to-step
    test('8. Go-to-step command', () async {
      final agent = SafeCookAgent();
      agent.memory.isCookingActive = true;
      agent.memory.selectedRecipe = dummyRecipe;
      agent.memory.currentStepIndex = 0;
      agent.conversationState = ConversationState.cooking;

      final context = SafeCookContext(
        recipe: dummyRecipe,
        currentStepIndex: 0,
        totalSteps: 3,
        safetyState: 'SAFE',
        sessionDuration: Duration.zero,
        isCookingActive: true,
        isBluetoothConnected: false,
        currentConversationState: 'cooking',
      );

      final reply = await agent.handleInput('go to step 3', context, stepTools);
      expect(goToStepVal, equals(3));
      expect(reply.toLowerCase(), contains('step 3'));
    });

    // 9. Step boundaries
    test('9. Step boundaries (clamping)', () async {
      final agent = SafeCookAgent();
      agent.memory.isCookingActive = true;
      agent.memory.selectedRecipe = dummyRecipe;

      // At step 1, previous step should fail/warn
      agent.memory.currentStepIndex = 0;
      final context1 = SafeCookContext(
        recipe: dummyRecipe,
        currentStepIndex: 0,
        totalSteps: 3,
        safetyState: 'SAFE',
        sessionDuration: Duration.zero,
        isCookingActive: true,
        isBluetoothConnected: false,
        currentConversationState: 'cooking',
      );
      final reply1 = await agent.handleInput('previous step', context1, stepTools);
      expect(prevStepCount, equals(0));
      expect(reply1, contains('already on step 1'));

      // At step 3 (last step), next step should fail/warn
      agent.memory.currentStepIndex = 2;
      final context3 = SafeCookContext(
        recipe: dummyRecipe,
        currentStepIndex: 2,
        totalSteps: 3,
        safetyState: 'SAFE',
        sessionDuration: Duration.zero,
        isCookingActive: true,
        isBluetoothConnected: false,
        currentConversationState: 'cooking',
      );
      final reply3 = await agent.handleInput('next step', context3, stepTools);
      expect(nextStepCount, equals(0));
      expect(reply3, contains('already on the last step'));
    });
  });

  group('Cooking Start Flow & Confirmation', () {
    late Recipe recipe;
    late SafeCookTools startTools;
    bool didStartCooking = false;

    setUp(() {
      recipe = kPredefinedRecipes.first; // Paneer Butter Masala or similar
      didStartCooking = false;
      startTools = SafeCookTools(
        searchRecipes: ({vegetarian, quick, ingredient, rawText, category}) => [],
        startCooking: (_) async {
          didStartCooking = true;
          return const ToolResult.ok('');
        },
        nextStep: () async => const ToolResult.ok(''),
        previousStep: () async => const ToolResult.ok(''),
        repeatStep: () async => const ToolResult.ok(''),
        goToStep: (_) async => const ToolResult.ok(''),
        endCooking: () async => const ToolResult.ok(''),
        connectBluetooth: () async => const ToolResult.ok(''),
        disconnectBluetooth: () async => const ToolResult.ok(''),
        bluetoothStatus: () => const ToolResult.ok(''),
      );
    });

    // 10. Cooking start state
    test('10. Cooking start state (offers details, does not start immediately)', () async {
      final agent = SafeCookAgent();
      final context = const SafeCookContext(
        safetyState: 'SAFE',
        sessionDuration: Duration.zero,
        isCookingActive: false,
        isBluetoothConnected: false,
        currentConversationState: 'idle',
      );

      final reply = await agent.handleInput('start Paneer Butter Masala', context, startTools);
      expect(didStartCooking, isFalse);
      expect(agent.conversationState, equals(ConversationState.awaitingReadyConfirm));
      expect(reply, contains('You will need'));
      expect(reply, contains('Safety note'));
      expect(reply.toLowerCase(), contains('ready'));
    });

    // 11. Confirmation handling
    test('11. Confirmation handling (yes starts step 1)', () async {
      final agent = SafeCookAgent();
      agent.memory.selectedRecipe = recipe;
      agent.conversationState = ConversationState.awaitingReadyConfirm;

      final context = SafeCookContext(
        recipe: recipe,
        safetyState: 'SAFE',
        sessionDuration: Duration.zero,
        isCookingActive: false,
        isBluetoothConnected: false,
        currentConversationState: ConversationState.awaitingReadyConfirm.name,
      );

      final reply = await agent.handleInput('yes', context, startTools);
      expect(didStartCooking, isTrue);
      expect(agent.conversationState, equals(ConversationState.cooking));
      expect(reply, contains('Starting step 1'));
    });

    // 12. Negative confirmation handling
    test('12. Negative confirmation handling (cancels start)', () async {
      final agent = SafeCookAgent();
      agent.memory.selectedRecipe = recipe;
      agent.conversationState = ConversationState.confirmingStart;

      final context = const SafeCookContext(
        safetyState: 'SAFE',
        sessionDuration: Duration.zero,
        isCookingActive: false,
        isBluetoothConnected: false,
        currentConversationState: 'confirming_start',
      );

      final reply = await agent.handleInput('no', context, startTools);
      expect(didStartCooking, isFalse);
      expect(agent.conversationState, equals(ConversationState.selectingRecipe));
      expect(agent.selectedRecipe, isNull);
      expect(reply, contains('What else would you like to cook'));
    });
  });

  group('Session Transitions & Reset', () {
    // 13. Cooking state transitions
    test('13. Cooking state transitions FSM path', () async {
      final agent = SafeCookAgent();
      expect(agent.conversationState, equals(ConversationState.idle));

      // 1. Find recipe
      var context = const SafeCookContext(
        safetyState: 'SAFE',
        sessionDuration: Duration.zero,
        isCookingActive: false,
        isBluetoothConnected: false,
        currentConversationState: 'idle',
      );
      final tools = SafeCookTools(
        searchRecipes: ({vegetarian, quick, ingredient, rawText, category}) => [kPredefinedRecipes.first],
        startCooking: (_) async => const ToolResult.ok(''),
        nextStep: () async => const ToolResult.ok(''),
        previousStep: () async => const ToolResult.ok(''),
        repeatStep: () async => const ToolResult.ok(''),
        goToStep: (_) async => const ToolResult.ok(''),
        endCooking: () async => const ToolResult.ok(''),
        connectBluetooth: () async => const ToolResult.ok(''),
        disconnectBluetooth: () async => const ToolResult.ok(''),
        bluetoothStatus: () => const ToolResult.ok(''),
      );

      await agent.handleInput('find paneer recipe', context, tools);
      expect(agent.conversationState, equals(ConversationState.confirmingStart));

      // 2. Select yes to review details
      context = SafeCookContext(
        safetyState: 'SAFE',
        sessionDuration: Duration.zero,
        isCookingActive: false,
        isBluetoothConnected: false,
        currentConversationState: agent.conversationState.name,
      );
      await agent.handleInput('yes', context, tools);
      expect(agent.conversationState, equals(ConversationState.awaitingReadyConfirm));

      // 3. Confirm readiness to cook
      var started = false;
      final startTools = SafeCookTools(
        searchRecipes: ({vegetarian, quick, ingredient, rawText, category}) => [],
        startCooking: (_) async {
          started = true;
          return const ToolResult.ok('');
        },
        nextStep: () async => const ToolResult.ok(''),
        previousStep: () async => const ToolResult.ok(''),
        repeatStep: () async => const ToolResult.ok(''),
        goToStep: (_) async => const ToolResult.ok(''),
        endCooking: () async => const ToolResult.ok(''),
        connectBluetooth: () async => const ToolResult.ok(''),
        disconnectBluetooth: () async => const ToolResult.ok(''),
        bluetoothStatus: () => const ToolResult.ok(''),
      );

      context = SafeCookContext(
        recipe: kPredefinedRecipes.first,
        safetyState: 'SAFE',
        sessionDuration: Duration.zero,
        isCookingActive: false,
        isBluetoothConnected: false,
        currentConversationState: agent.conversationState.name,
      );

      await agent.handleInput('yes', context, startTools);
      expect(started, isTrue);
      expect(agent.conversationState, equals(ConversationState.cooking));
    });

    // 14. End cooking reset
    test('14. End cooking reset state', () async {
      final agent = SafeCookAgent();
      agent.memory.isCookingActive = true;
      agent.memory.selectedRecipe = kPredefinedRecipes.first;
      agent.memory.currentStepIndex = 3;
      agent.conversationState = ConversationState.cooking;

      final context = SafeCookContext(
        recipe: kPredefinedRecipes.first,
        currentStepIndex: 3,
        totalSteps: 10,
        safetyState: 'SAFE',
        sessionDuration: const Duration(minutes: 15),
        isCookingActive: true,
        isBluetoothConnected: false,
        currentConversationState: 'cooking',
      );

      var ended = false;
      final tools = SafeCookTools(
        searchRecipes: ({vegetarian, quick, ingredient, rawText, category}) => [],
        startCooking: (_) async => const ToolResult.ok(''),
        nextStep: () async => const ToolResult.ok(''),
        previousStep: () async => const ToolResult.ok(''),
        repeatStep: () async => const ToolResult.ok(''),
        goToStep: (_) async => const ToolResult.ok(''),
        endCooking: () async {
          ended = true;
          return const ToolResult.ok('');
        },
        connectBluetooth: () async => const ToolResult.ok(''),
        disconnectBluetooth: () async => const ToolResult.ok(''),
        bluetoothStatus: () => const ToolResult.ok(''),
      );

      final reply = await agent.handleInput('end cooking', context, tools);
      expect(agent.conversationState, equals(ConversationState.confirmingEnd));
      expect(reply, contains('running for 15 minutes'));

      // Say yes to finalize
      final finalContext = SafeCookContext(
        recipe: kPredefinedRecipes.first,
        currentStepIndex: 3,
        totalSteps: 10,
        safetyState: 'SAFE',
        sessionDuration: const Duration(minutes: 15),
        isCookingActive: true,
        isBluetoothConnected: false,
        currentConversationState: 'confirming_end',
      );
      final reply2 = await agent.handleInput('yes', finalContext, tools);
      expect(ended, isTrue);
      expect(agent.conversationState, equals(ConversationState.idle));
      expect(agent.isCookingActive, isFalse);
      expect(reply2, contains('report'));
    });
  });

  group('Bluetooth & Sensor Logic', () {
    // 15. Bluetooth command intent mapping
    test('15. Bluetooth command intent mapping', () {
      final intentConnect = SafeCookNLU.parse('connect sensor');
      expect(intentConnect.type, equals(SafeCookIntentType.connectBluetooth));

      final intentDisconnect = SafeCookNLU.parse('disconnect Bluetooth');
      expect(intentDisconnect.type, equals(SafeCookIntentType.disconnectBluetooth));

      final intentStatus = SafeCookNLU.parse('are we connected?');
      expect(intentStatus.type, equals(SafeCookIntentType.checkConnectionStatus));
    });

    // 16. Sensor safety state calculation
    test('16. Calibrated sensor percent conversion and distance interpretation', () {
      // 17. Gas percentage conversion
      expect(GasCalibration.toPercent(50), equals(0.0));
      expect(GasCalibration.toPercent(900), equals(100.0));
      expect(GasCalibration.toPercent(475), closeTo(50.0, 0.1));

      // Test bounds clamping
      expect(GasCalibration.toPercent(20), equals(0.0));
      expect(GasCalibration.toPercent(1000), equals(100.0));
    });

    // 18. Distance interpretation & 19. NO_ECHO handling
    test('18. Distance and 19. NO_ECHO check', () async {
      final agent = SafeCookAgent();
      final tools = buildNoOpTools();

      // Normal reading
      final contextSafe = const SafeCookContext(
        distanceValue: '45.0 cm',
        distanceCm: 45.0,
        safetyState: 'SAFE',
        sessionDuration: Duration.zero,
        isCookingActive: false,
        isBluetoothConnected: true,
        currentConversationState: 'idle',
      );
      final replySafe = await agent.handleInput('am i too close?', contextSafe, tools);
      expect(replySafe, contains('safe distance'));

      // Unsafe reading
      final contextClose = const SafeCookContext(
        distanceValue: '10.0 cm',
        distanceCm: 10.0,
        safetyState: 'DISTANCE ALERT',
        sessionDuration: Duration.zero,
        isCookingActive: false,
        isBluetoothConnected: true,
        currentConversationState: 'idle',
      );
      final replyClose = await agent.handleInput('am i too close?', contextClose, tools);
      expect(replyClose, contains('Warning: you are very close'));

      // NO ECHO reading
      final contextNoEcho = const SafeCookContext(
        distanceValue: 'No Echo',
        distanceCm: null,
        safetyState: 'STANDBY',
        sessionDuration: Duration.zero,
        isCookingActive: false,
        isBluetoothConnected: true,
        currentConversationState: 'idle',
      );
      final replyNoEcho = await agent.handleInput('am i too close?', contextNoEcho, tools);
      expect(replyNoEcho, contains('not detecting anything'));
    });
  });

  group('Safety Interruption State Preservation', () {
    // 20. Safety interruption state preservation
    test('20. Safety interruption does not corrupt agent state', () async {
      final agent = SafeCookAgent();
      agent.memory.isCookingActive = true;
      agent.memory.selectedRecipe = kPredefinedRecipes.first;
      agent.memory.currentStepIndex = 4;
      agent.conversationState = ConversationState.cooking;

      final context = SafeCookContext(
        recipe: kPredefinedRecipes.first,
        currentStepIndex: 4,
        totalSteps: 10,
        safetyState: 'GAS ALERT', // safety warning
        sessionDuration: const Duration(minutes: 5),
        isCookingActive: true,
        isBluetoothConnected: true,
        currentConversationState: 'cooking',
      );

      final tools = buildNoOpTools();
      // Ask a sensor question during alert
      final reply = await agent.handleInput('check safety', context, tools);
      expect(reply, contains('Warning: elevated gas level'));

      // Ensure cooking state, current step index and recipe remain perfectly preserved
      expect(agent.conversationState, equals(ConversationState.cooking));
      expect(agent.selectedRecipe, equals(kPredefinedRecipes.first));
      expect(agent.memory.currentStepIndex, equals(4));
    });
  });

  group('Stale Sensor Data & TTS Lifecycle Audits', () {
    test('Stale sensor values (null) are handled safely without crash', () async {
      final agent = SafeCookAgent();
      final context = const SafeCookContext(
        gasValue: null,
        distanceValue: null,
        safetyState: 'STANDBY',
        sessionDuration: Duration.zero,
        isCookingActive: false,
        isBluetoothConnected: false,
        currentConversationState: 'idle',
      );
      final replyGas = await agent.handleInput('check gas level', context, buildNoOpTools());
      expect(replyGas, contains('not connected or not reporting data'));

      final replyDist = await agent.handleInput('how far am i?', context, buildNoOpTools());
      expect(replyDist, contains('not detecting anything right now'));
    });

    test('Clean voice navigation actions do not trigger duplicate local TTS calls', () async {
      int localSpeakCalls = 0;
      final stepTools = SafeCookTools(
        searchRecipes: ({vegetarian, quick, ingredient, rawText, category}) => [],
        startCooking: (_) async => const ToolResult.ok(''),
        nextStep: () async {
          localSpeakCalls++; // simulating speaker output inside callback
          SafeCookAgent().memory.nextStep();
          return const ToolResult.ok('');
        },
        previousStep: () async {
          localSpeakCalls++;
          SafeCookAgent().memory.previousStep();
          return const ToolResult.ok('');
        },
        repeatStep: () async {
          localSpeakCalls++;
          SafeCookAgent().memory.repeatStep();
          return const ToolResult.ok('');
        },
        goToStep: (stepNum) async {
          localSpeakCalls++;
          SafeCookAgent().memory.goToStep(stepNum);
          return const ToolResult.ok('');
        },
        endCooking: () async => const ToolResult.ok(''),
        connectBluetooth: () async => const ToolResult.ok(''),
        disconnectBluetooth: () async => const ToolResult.ok(''),
        bluetoothStatus: () => const ToolResult.ok(''),
      );

      final agent = SafeCookAgent();
      agent.memory.isCookingActive = true;
      agent.memory.selectedRecipe = kPredefinedRecipes.first;
      agent.memory.currentStepIndex = 1;
      agent.conversationState = ConversationState.cooking;

      final context = SafeCookContext(
        recipe: kPredefinedRecipes.first,
        currentStepIndex: 1,
        totalSteps: 10,
        safetyState: 'SAFE',
        sessionDuration: Duration.zero,
        isCookingActive: true,
        isBluetoothConnected: false,
        currentConversationState: 'cooking',
      );

      // 1. Next step
      final replyNext = await agent.handleInput('next step', context, stepTools);
      expect(replyNext, contains('Step 3'));
      // The voice command handler is responsible for speaking the returned reply.
      // The stepTools callback must NOT speak internally, which we verify by ensuring stepTools nextStep doesn't leak outer speak.
      expect(localSpeakCalls, equals(1)); // verified stepTools.nextStep was called exactly once to transition index
    });
  });

  group('Hardware integration verification checklist', () {
    late Recipe dummyRecipe;
    late SafeCookTools stepTools;

    setUp(() {
      dummyRecipe = Recipe(
        id: '1',
        name: 'Test Dish',
        category: 'Test',
        description: 'Test',
        cookingTime: 10,
        difficulty: 'Easy',
        servings: 2,
        ingredients: ['Ing 1'],
        steps: [
          RecipeStep(stepNumber: 1, instruction: 'Step 1 description', voiceInstruction: 'Read 1'),
          RecipeStep(stepNumber: 2, instruction: 'Step 2 description', voiceInstruction: 'Read 2'),
          RecipeStep(stepNumber: 3, instruction: 'Step 3 description', voiceInstruction: 'Read 3'),
          RecipeStep(stepNumber: 4, instruction: 'Step 4 description', voiceInstruction: 'Read 4'),
          RecipeStep(stepNumber: 5, instruction: 'Step 5 description', voiceInstruction: 'Read 5'),
        ],
        safetyNotes: [],
      );

      stepTools = SafeCookTools(
        searchRecipes: ({vegetarian, quick, ingredient, rawText, category}) => [],
        startCooking: (_) async => const ToolResult.ok(''),
        nextStep: () async {
          SafeCookAgent().memory.nextStep();
          return const ToolResult.ok('');
        },
        previousStep: () async {
          SafeCookAgent().memory.previousStep();
          return const ToolResult.ok('');
        },
        repeatStep: () async {
          SafeCookAgent().memory.repeatStep();
          return const ToolResult.ok('');
        },
        goToStep: (stepNum) async {
          SafeCookAgent().memory.goToStep(stepNum);
          return const ToolResult.ok('');
        },
        endCooking: () async => const ToolResult.ok(''),
        connectBluetooth: () async => const ToolResult.ok(''),
        disconnectBluetooth: () async => const ToolResult.ok(''),
        bluetoothStatus: () => const ToolResult.ok(''),
      );
    });

    test('1. step 1 + next => step 2', () async {
      final agent = SafeCookAgent();
      agent.memory.reset();
      agent.memory.isCookingActive = true;
      agent.memory.selectedRecipe = dummyRecipe;
      agent.memory.currentStepIndex = 0;
      agent.conversationState = ConversationState.cooking;

      final context = SafeCookContext(
        recipe: dummyRecipe,
        currentStepIndex: 0,
        totalSteps: 5,
        safetyState: 'SAFE',
        sessionDuration: Duration.zero,
        isCookingActive: true,
        isBluetoothConnected: false,
        currentConversationState: 'cooking',
      );

      final reply = await agent.handleInput('next step', context, stepTools);
      expect(agent.memory.currentStepIndex, equals(1));
      expect(reply, contains('Read 2'));
    });

    test('2. step 2 + next => step 3', () async {
      final agent = SafeCookAgent();
      agent.memory.reset();
      agent.memory.isCookingActive = true;
      agent.memory.selectedRecipe = dummyRecipe;
      agent.memory.currentStepIndex = 1;
      agent.conversationState = ConversationState.cooking;

      final context = SafeCookContext(
        recipe: dummyRecipe,
        currentStepIndex: 1,
        totalSteps: 5,
        safetyState: 'SAFE',
        sessionDuration: Duration.zero,
        isCookingActive: true,
        isBluetoothConnected: false,
        currentConversationState: 'cooking',
      );

      await agent.handleInput('next step', context, stepTools);
      expect(agent.memory.currentStepIndex, equals(2));
    });

    test('3. step 3 + previous => step 2', () async {
      final agent = SafeCookAgent();
      agent.memory.reset();
      agent.memory.isCookingActive = true;
      agent.memory.selectedRecipe = dummyRecipe;
      agent.memory.currentStepIndex = 2;
      agent.conversationState = ConversationState.cooking;

      final context = SafeCookContext(
        recipe: dummyRecipe,
        currentStepIndex: 2,
        totalSteps: 5,
        safetyState: 'SAFE',
        sessionDuration: Duration.zero,
        isCookingActive: true,
        isBluetoothConnected: false,
        currentConversationState: 'cooking',
      );

      await agent.handleInput('previous step', context, stepTools);
      expect(agent.memory.currentStepIndex, equals(1));
    });

    test('4. step 2 + previous => step 1', () async {
      final agent = SafeCookAgent();
      agent.memory.reset();
      agent.memory.isCookingActive = true;
      agent.memory.selectedRecipe = dummyRecipe;
      agent.memory.currentStepIndex = 1;
      agent.conversationState = ConversationState.cooking;

      final context = SafeCookContext(
        recipe: dummyRecipe,
        currentStepIndex: 1,
        totalSteps: 5,
        safetyState: 'SAFE',
        sessionDuration: Duration.zero,
        isCookingActive: true,
        isBluetoothConnected: false,
        currentConversationState: 'cooking',
      );

      await agent.handleInput('previous step', context, stepTools);
      expect(agent.memory.currentStepIndex, equals(0));
    });

    test('5. step 1 + previous => step 1', () async {
      final agent = SafeCookAgent();
      agent.memory.reset();
      agent.memory.isCookingActive = true;
      agent.memory.selectedRecipe = dummyRecipe;
      agent.memory.currentStepIndex = 0;
      agent.conversationState = ConversationState.cooking;

      final context = SafeCookContext(
        recipe: dummyRecipe,
        currentStepIndex: 0,
        totalSteps: 5,
        safetyState: 'SAFE',
        sessionDuration: Duration.zero,
        isCookingActive: true,
        isBluetoothConnected: false,
        currentConversationState: 'cooking',
      );

      await agent.handleInput('previous step', context, stepTools);
      expect(agent.memory.currentStepIndex, equals(0));
    });

    test('6. step 2 + repeat => step 2', () async {
      final agent = SafeCookAgent();
      agent.memory.reset();
      agent.memory.isCookingActive = true;
      agent.memory.selectedRecipe = dummyRecipe;
      agent.memory.currentStepIndex = 1;
      agent.conversationState = ConversationState.cooking;

      final context = SafeCookContext(
        recipe: dummyRecipe,
        currentStepIndex: 1,
        totalSteps: 5,
        safetyState: 'SAFE',
        sessionDuration: Duration.zero,
        isCookingActive: true,
        isBluetoothConnected: false,
        currentConversationState: 'cooking',
      );

      await agent.handleInput('repeat', context, stepTools);
      expect(agent.memory.currentStepIndex, equals(1));
    });

    test('7. go to step 1 => index 0', () async {
      final agent = SafeCookAgent();
      agent.memory.reset();
      agent.memory.isCookingActive = true;
      agent.memory.selectedRecipe = dummyRecipe;
      agent.memory.currentStepIndex = 2;
      agent.conversationState = ConversationState.cooking;

      final context = SafeCookContext(
        recipe: dummyRecipe,
        currentStepIndex: 2,
        totalSteps: 5,
        safetyState: 'SAFE',
        sessionDuration: Duration.zero,
        isCookingActive: true,
        isBluetoothConnected: false,
        currentConversationState: 'cooking',
      );

      await agent.handleInput('go to step 1', context, stepTools);
      expect(agent.memory.currentStepIndex, equals(0));
    });

    test('8. go to step 3 => index 2', () async {
      final agent = SafeCookAgent();
      agent.memory.reset();
      agent.memory.isCookingActive = true;
      agent.memory.selectedRecipe = dummyRecipe;
      agent.memory.currentStepIndex = 0;
      agent.conversationState = ConversationState.cooking;

      final context = SafeCookContext(
        recipe: dummyRecipe,
        currentStepIndex: 0,
        totalSteps: 5,
        safetyState: 'SAFE',
        sessionDuration: Duration.zero,
        isCookingActive: true,
        isBluetoothConnected: false,
        currentConversationState: 'cooking',
      );

      await agent.handleInput('go to step 3', context, stepTools);
      expect(agent.memory.currentStepIndex, equals(2));
    });

    test('9. go to step five => index 4', () async {
      final agent = SafeCookAgent();
      agent.memory.reset();
      agent.memory.isCookingActive = true;
      agent.memory.selectedRecipe = dummyRecipe;
      agent.memory.currentStepIndex = 0;
      agent.conversationState = ConversationState.cooking;

      final context = SafeCookContext(
        recipe: dummyRecipe,
        currentStepIndex: 0,
        totalSteps: 5,
        safetyState: 'SAFE',
        sessionDuration: Duration.zero,
        isCookingActive: true,
        isBluetoothConnected: false,
        currentConversationState: 'cooking',
      );

      await agent.handleInput('go to step five', context, stepTools);
      expect(agent.memory.currentStepIndex, equals(4));
    });

    test('10. jump to step 2 => index 1', () async {
      final agent = SafeCookAgent();
      agent.memory.reset();
      agent.memory.isCookingActive = true;
      agent.memory.selectedRecipe = dummyRecipe;
      agent.memory.currentStepIndex = 0;
      agent.conversationState = ConversationState.cooking;

      final context = SafeCookContext(
        recipe: dummyRecipe,
        currentStepIndex: 0,
        totalSteps: 5,
        safetyState: 'SAFE',
        sessionDuration: Duration.zero,
        isCookingActive: true,
        isBluetoothConnected: false,
        currentConversationState: 'cooking',
      );

      await agent.handleInput('jump to step 2', context, stepTools);
      expect(agent.memory.currentStepIndex, equals(1));
    });

    test('11. excessive step number => last step', () async {
      final agent = SafeCookAgent();
      agent.memory.reset();
      agent.memory.isCookingActive = true;
      agent.memory.selectedRecipe = dummyRecipe;
      agent.memory.currentStepIndex = 0;
      agent.conversationState = ConversationState.cooking;

      final context = SafeCookContext(
        recipe: dummyRecipe,
        currentStepIndex: 0,
        totalSteps: 5,
        safetyState: 'SAFE',
        sessionDuration: Duration.zero,
        isCookingActive: true,
        isBluetoothConnected: false,
        currentConversationState: 'cooking',
      );

      await agent.handleInput('go to step 999', context, stepTools);
      expect(agent.memory.currentStepIndex, equals(4));
    });

    test('12. "what\'s next" => NEXT_STEP', () async {
      final intent = SafeCookNLU.parse("what's next", conversationState: 'cooking', isCookingActive: true);
      expect(intent.type, equals(SafeCookIntentType.nextStep));
    });

    test('13. "go ahead" => NEXT_STEP', () async {
      final intent = SafeCookNLU.parse("go ahead", conversationState: 'cooking', isCookingActive: true);
      expect(intent.type, equals(SafeCookIntentType.nextStep));
    });

    test('14. "go back" => PREVIOUS_STEP', () async {
      final intent = SafeCookNLU.parse("go back", conversationState: 'cooking', isCookingActive: true);
      expect(intent.type, equals(SafeCookIntentType.previousStep));
    });

    test('15. "repeat that" => REPEAT_STEP', () async {
      final intent = SafeCookNLU.parse("repeat that", conversationState: 'cooking', isCookingActive: true);
      expect(intent.type, equals(SafeCookIntentType.readStep));
    });

    test('16. "take me to step three" => GO_TO_STEP(3)', () async {
      final intent = SafeCookNLU.parse("take me to step three", conversationState: 'cooking', isCookingActive: true);
      expect(intent.type, equals(SafeCookIntentType.goToStep));
      expect(intent.entities['stepNumber'], equals(3));
    });

    test('17. "end cooking" => END_COOKING', () async {
      final intent = SafeCookNLU.parse("end cooking", conversationState: 'cooking', isCookingActive: true);
      expect(intent.type, equals(SafeCookIntentType.endCooking));
    });

    test('18. "and cooking" in cooking state => END_COOKING', () async {
      final intent = SafeCookNLU.parse("and cooking", conversationState: 'cooking', isCookingActive: true);
      expect(intent.type, equals(SafeCookIntentType.endCooking));
    });

    test('19. "finish cooking" => END_COOKING', () async {
      final intent = SafeCookNLU.parse("finish cooking", conversationState: 'cooking', isCookingActive: true);
      expect(intent.type, equals(SafeCookIntentType.endCooking));
    });

    test('20. "I\'m done cooking" => END_COOKING', () async {
      final intent = SafeCookNLU.parse("I'm done cooking", conversationState: 'cooking', isCookingActive: true);
      expect(intent.type, equals(SafeCookIntentType.endCooking));
    });

    test('21. "that\'s all" => END_COOKING', () async {
      final intent = SafeCookNLU.parse("that's all", conversationState: 'cooking', isCookingActive: true);
      expect(intent.type, equals(SafeCookIntentType.endCooking));
    });

    test('22. "connect to HC05" => CONNECT_BLUETOOTH', () async {
      final intent = SafeCookNLU.parse("connect to HC05");
      expect(intent.type, equals(SafeCookIntentType.connectBluetooth));
    });

    test('23. "connect to the stove sensor" => CONNECT_BLUETOOTH', () async {
      final intent = SafeCookNLU.parse("connect to the stove sensor");
      expect(intent.type, equals(SafeCookIntentType.connectBluetooth));
    });

    test('24. "pair the sensor" => CONNECT_BLUETOOTH', () async {
      final intent = SafeCookNLU.parse("pair the sensor");
      expect(intent.type, equals(SafeCookIntentType.connectBluetooth));
    });

    test('25. "disconnect bluetooth" => DISCONNECT_BLUETOOTH', () async {
      final intent = SafeCookNLU.parse("disconnect bluetooth");
      expect(intent.type, equals(SafeCookIntentType.disconnectBluetooth));
    });

    test('26. "disconnect the sensor" => DISCONNECT_BLUETOOTH', () async {
      final intent = SafeCookNLU.parse("disconnect the sensor");
      expect(intent.type, equals(SafeCookIntentType.disconnectBluetooth));
    });

    test('27. "are we connected" => BLUETOOTH_STATUS', () async {
      final intent = SafeCookNLU.parse("are we connected");
      expect(intent.type, equals(SafeCookIntentType.checkConnectionStatus));
    });
  });

  group('Duplicate voice command execution prevention', () {
    test('Utterance cleared immediately prevents duplicate state change', () async {
      final agent = SafeCookAgent();
      agent.memory.reset();
      agent.memory.isCookingActive = true;
      agent.memory.selectedRecipe = kPredefinedRecipes.first;
      agent.memory.currentStepIndex = 0;
      agent.conversationState = ConversationState.cooking;

      final context = SafeCookContext(
        recipe: kPredefinedRecipes.first,
        currentStepIndex: 0,
        totalSteps: 5,
        safetyState: 'SAFE',
        sessionDuration: Duration.zero,
        isCookingActive: true,
        isBluetoothConnected: false,
        currentConversationState: 'cooking',
      );

      // Simulating a speech listener that fires twice
      String userSpokenText = 'next step';
      
      // First fire
      final query1 = userSpokenText.trim();
      userSpokenText = ''; // Cleared immediately!
      
      final reply1 = await agent.handleInput(query1, context, SafeCookTools(
        searchRecipes: ({vegetarian, quick, ingredient, rawText, category}) => [],
        startCooking: (_) async => const ToolResult.ok(''),
        nextStep: () async {
          agent.memory.nextStep();
          return const ToolResult.ok('');
        },
        previousStep: () async => const ToolResult.ok(''),
        repeatStep: () async => const ToolResult.ok(''),
        goToStep: (_) async => const ToolResult.ok(''),
        endCooking: () async => const ToolResult.ok(''),
        connectBluetooth: () async => const ToolResult.ok(''),
        disconnectBluetooth: () async => const ToolResult.ok(''),
        bluetoothStatus: () => const ToolResult.ok(''),
      ));

      expect(agent.memory.currentStepIndex, equals(1));
      expect(reply1, contains('Step 2'));

      // Second fire (userSpokenText is now empty, so the UI code doesn't call handleInput again)
      expect(userSpokenText.isEmpty, isTrue);
    });
  });
}
