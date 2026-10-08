import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safecook_bluetooth_test/main.dart';
import 'package:safecook_bluetooth_test/screens/cooking_guidance_screen.dart';
import 'package:safecook_bluetooth_test/data/recipes.dart';
import 'package:safecook_bluetooth_test/services/voice_service.dart';
import 'package:safecook_bluetooth_test/agent/safecook_agent.dart';
import 'package:safecook_bluetooth_test/agent/safecook_context.dart';

void main() {
  testWidgets('Bluetooth app basic layout test', (WidgetTester tester) async {
    BluetoothTestPage.isTesting = true;
    // Build our app and trigger a frame.
    await tester.pumpWidget(const SafeCookBluetoothTestApp());

    // Verify that the title is displayed.
    expect(find.text('SafeCook'), findsOneWidget);
  });

  testWidgets('TTS counting test on CookingGuidanceScreen', (
    WidgetTester tester,
  ) async {
    BluetoothTestPage.isTesting = true;
    await tester.pumpWidget(const SafeCookBluetoothTestApp());
    await tester.pumpAndSettle();
    final homeState = tester.state<BluetoothTestPageState>(
      find.byType(BluetoothTestPage),
    );
    final context = tester.element(find.byType(BluetoothTestPage));

    // Clear TTS spoken logs
    VoiceService().clearSpokenTexts();

    // Push the CookingGuidanceScreen manually on the navigation stack
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CookingGuidanceScreen(
          recipe: kPredefinedRecipes.first,
          homeState: homeState,
          startSilently: true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final state = tester.state<CookingGuidanceScreenState>(
      find.byType(CookingGuidanceScreen),
    );

    // 1. Verify speak: false does NOT trigger TTS speak
    VoiceService().clearSpokenTexts();
    state.goToNextStep(speak: false);
    expect(VoiceService().spokenTexts.length, equals(0));

    // 2. Verify speak: true (default) DOES trigger TTS speak
    // Note: since currentStepIndex was advanced to 1 in step 1, this advances it to 2 (Step 3) and reads Step 3.
    state.goToNextStep(speak: true);
    expect(VoiceService().spokenTexts.length, equals(1));
    expect(
      VoiceService().spokenTexts.first,
      contains('tomato puree'),
    ); // Step 3 instruction

    // 3. Previous step speak: false
    VoiceService().clearSpokenTexts();
    state.goToPreviousStep(speak: false);
    expect(VoiceService().spokenTexts.length, equals(0));
  });

  testWidgets('CookingGuidanceScreen startSilently verification', (
    WidgetTester tester,
  ) async {
    BluetoothTestPage.isTesting = true;
    await tester.pumpWidget(const SafeCookBluetoothTestApp());
    await tester.pumpAndSettle();
    final homeState = tester.state<BluetoothTestPageState>(
      find.byType(BluetoothTestPage),
    );
    final context = tester.element(find.byType(BluetoothTestPage));

    // Case A: startSilently = true (Voice start)
    VoiceService().clearSpokenTexts();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CookingGuidanceScreen(
          recipe: kPredefinedRecipes.first,
          homeState: homeState,
          startSilently: true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      VoiceService().spokenTexts.length,
      equals(0),
    ); // Should remain silent

    // Pop the silent screen to restore stack
    Navigator.pop(context);
    await tester.pumpAndSettle();

    // Case B: startSilently = false (Touch start)
    VoiceService().clearSpokenTexts();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CookingGuidanceScreen(
          recipe: kPredefinedRecipes.first,
          homeState: homeState,
          startSilently: false,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      VoiceService().spokenTexts.length,
      equals(1),
    ); // Should speak step 1 instruction
  });

  testWidgets('Guidance screen step index transitions', (
    WidgetTester tester,
  ) async {
    BluetoothTestPage.isTesting = true;
    await tester.pumpWidget(const SafeCookBluetoothTestApp());
    await tester.pumpAndSettle();
    final homeState = tester.state<BluetoothTestPageState>(
      find.byType(BluetoothTestPage),
    );
    final context = tester.element(find.byType(BluetoothTestPage));

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CookingGuidanceScreen(
          recipe: kPredefinedRecipes.first, // 5 steps (Paneer Butter Masala)
          homeState: homeState,
          startSilently: true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final state = tester.state<CookingGuidanceScreenState>(
      find.byType(CookingGuidanceScreen),
    );

    // Starts at step 1 (index 0)
    expect(state.currentStepIndex, equals(0));

    // Step 1 + next = Step 2 (index 1)
    state.goToNextStep(speak: false);
    expect(state.currentStepIndex, equals(1));

    // Step 2 + next = Step 3 (index 2)
    state.goToNextStep(speak: false);
    expect(state.currentStepIndex, equals(2));

    // Step 3 + previous = Step 2 (index 1)
    state.goToPreviousStep(speak: false);
    expect(state.currentStepIndex, equals(1));

    // Step 2 + previous = Step 1 (index 0)
    state.goToPreviousStep(speak: false);
    expect(state.currentStepIndex, equals(0));

    // Step 1 + previous = Step 1 (index 0 - clamping)
    state.goToPreviousStep(speak: false);
    expect(state.currentStepIndex, equals(0));

    // Go to step 5 (index 4)
    state.testSetStepIndex(4);
    expect(state.currentStepIndex, equals(4));

    // Repeat step -> verifies it reads the same index
    VoiceService().clearSpokenTexts();
    state.speakCurrentStep(speak: true);
    expect(
      VoiceService().spokenTexts.first,
      contains('Finish by stirring in fresh cream'),
    ); // step 5 voice instruction
  });

  testWidgets('Safety interruption logical verification', (
    WidgetTester tester,
  ) async {
    BluetoothTestPage.isTesting = true;
    await tester.pumpWidget(const SafeCookBluetoothTestApp());
    await tester.pumpAndSettle();
    final homeState = tester.state<BluetoothTestPageState>(
      find.byType(BluetoothTestPage),
    );
    final context = tester.element(find.byType(BluetoothTestPage));

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CookingGuidanceScreen(
          recipe: kPredefinedRecipes.first,
          homeState: homeState,
          startSilently: true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final state = tester.state<CookingGuidanceScreenState>(
      find.byType(CookingGuidanceScreen),
    );

    // Set to step 3 (index 2)
    state.testSetStepIndex(2);

    // Simulate safety transition on home state using simulateSensorData helper
    homeState.connectedDeviceForTesting = BluetoothDevice(
      name: 'HC-05',
      address: 'FA:B8:03:6B:1F:57',
      bondState: 'bonded',
    );
    homeState.simulateSensorData('GAS:600,DIST:50.00');
    await tester.pump();

    // Trigger update
    state.onSensorUpdate();

    // Verify alert spoken
    expect(VoiceService().spokenTexts.last, contains('gas level is high'));

    // Verify recipe and step are preserved
    expect(state.widget.recipe, equals(kPredefinedRecipes.first));
    expect(state.currentStepIndex, equals(2));
    expect(
      SafeCookAgent().conversationState,
      equals(ConversationState.cooking),
    );

    // Wait for mock sound/vibration timers to complete
    await tester.pump(const Duration(milliseconds: 100));
  });

  testWidgets(
    'Bluetooth selection - Exact match HC-05 chosen over Buds/Watch',
    (WidgetTester tester) async {
      BluetoothTestPage.isTesting = true;
      await tester.pumpWidget(const SafeCookBluetoothTestApp());
      await tester.pumpAndSettle();

      final homeState = tester.state<BluetoothTestPageState>(
        find.byType(BluetoothTestPage),
      );

      // Set custom bonded devices list containing unrelated devices and HC-05
      homeState.bondedDevicesForTesting = [
        BluetoothDevice(
          name: 'Galaxy Buds',
          address: '00:11:22:33:44:55',
          bondState: 'bonded',
        ),
        BluetoothDevice(
          name: 'Some Watch',
          address: '66:77:88:99:AA:BB',
          bondState: 'bonded',
        ),
        BluetoothDevice(
          name: 'HC-05',
          address: 'FA:B8:03:6B:1F:57',
          bondState: 'bonded',
        ),
      ];

      // Trigger connectBluetoothFromVoice()
      final res = await homeState.connectBluetoothFromVoice();

      // Verify it succeeded and connected to HC-05
      expect(res.success, isTrue);
      expect(homeState.isBluetoothConnected, isTrue);
    },
  );

  testWidgets(
    'Bluetooth selection - Exact command connect to HC-05 target resolved',
    (WidgetTester tester) async {
      BluetoothTestPage.isTesting = true;
      await tester.pumpWidget(const SafeCookBluetoothTestApp());
      await tester.pumpAndSettle();

      final homeState = tester.state<BluetoothTestPageState>(
        find.byType(BluetoothTestPage),
      );

      homeState.bondedDevicesForTesting = [
        BluetoothDevice(
          name: 'Galaxy Buds',
          address: '00:11:22:33:44:55',
          bondState: 'bonded',
        ),
        BluetoothDevice(
          name: 'HC-05',
          address: 'FA:B8:03:6B:1F:57',
          bondState: 'bonded',
        ),
      ];

      final res = await homeState.connectBluetoothFromVoice();
      expect(res.success, isTrue);
      expect(homeState.isBluetoothConnected, isTrue);
    },
  );

  testWidgets('Bluetooth selection - No match found fail message', (
    WidgetTester tester,
  ) async {
    BluetoothTestPage.isTesting = true;
    await tester.pumpWidget(const SafeCookBluetoothTestApp());
    await tester.pumpAndSettle();

    final homeState = tester.state<BluetoothTestPageState>(
      find.byType(BluetoothTestPage),
    );

    homeState.bondedDevicesForTesting = [
      BluetoothDevice(
        name: 'Galaxy Buds',
        address: '00:11:22:33:44:55',
        bondState: 'bonded',
      ),
      BluetoothDevice(
        name: 'Smart Watch',
        address: '66:77:88:99:AA:BB',
        bondState: 'bonded',
      ),
    ];

    final res = await homeState.connectBluetoothFromVoice();

    // Verify it failed with the exact required failure message
    expect(res.success, isFalse);
    expect(
      res.message,
      contains(
        "I couldn't find the paired HC-05 stove sensor. Please make sure HC-05 is paired and powered on.",
      ),
    );
    expect(homeState.isBluetoothConnected, isFalse);
  });

  testWidgets(
    'Home screen production UI structure renders all required cards',
    (WidgetTester tester) async {
      BluetoothTestPage.isTesting = true;
      await tester.pumpWidget(const SafeCookBluetoothTestApp());
      await tester.pumpAndSettle();

      // 1. Header
      expect(find.text('SafeCook'), findsOneWidget);
      expect(find.text('SMART COOKING SAFETY'), findsOneWidget);

      // 2. Welcome section
      expect(find.text('Welcome, Chef'), findsOneWidget);

      // 3. Primary cooking / voice card
      expect(find.text('VOICE ASSISTANT'), findsOneWidget);
      expect(find.text('START COOKING'), findsOneWidget);

      // 4. Kitchen safety card
      expect(find.text('KITCHEN SAFETY STATUS'), findsOneWidget);
      expect(find.text('GAS LEVEL'), findsOneWidget);
      expect(find.text('DISTANCE'), findsOneWidget);
      expect(find.text('SENSOR LINK'), findsOneWidget);

      // 5. Quick actions
      expect(find.text('QUICK ACTIONS'), findsOneWidget);
      expect(find.text('Cook'), findsOneWidget);
      expect(find.text('Recipes'), findsOneWidget);
      expect(find.text('Memory'), findsOneWidget);

      // 6. Recent cooking section
      expect(find.text('RECENT COOKING'), findsOneWidget);

      // 7. Subordinate user preferences
      expect(find.text('USER PREFERENCES'), findsOneWidget);

      // 8. Subordinate sensor connection
      expect(find.text('SENSOR CONNECTION'), findsOneWidget);

      // 9. Diagnostics section
      expect(find.text('SENSOR TELEMETRY & LOGS'), findsOneWidget);
    },
  );
}
