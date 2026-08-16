// ignore_for_file: avoid_print
import 'package:flutter/material.dart';
import '../models/recipe.dart';
import '../services/voice_service.dart';
import '../main.dart';
import 'cooking_report_screen.dart';
import '../services/speech_service.dart';
import '../services/voice_assistant_service.dart';
import '../services/wake_word_service.dart';
import '../agent/safecook_agent.dart';
import '../agent/safecook_context.dart';
import '../agent/safecook_tools.dart';

class CookingGuidanceScreen extends StatefulWidget {
  final Recipe recipe;
  final BluetoothTestPageState homeState;
  final bool startSilently;

  const CookingGuidanceScreen({
    super.key,
    required this.recipe,
    required this.homeState,
    this.startSilently = false,
  });

  @override
  State<CookingGuidanceScreen> createState() => CookingGuidanceScreenState();
}

class CookingGuidanceScreenState extends State<CookingGuidanceScreen> {
  // -------------------------------------------------------------------------
  // Step navigation — this is the AUTHORITATIVE index for the UI.
  // Every change calls SafeCookAgent().confirmStepIndex(idx) to keep the
  // agent in sync.
  // -------------------------------------------------------------------------
  int get currentStepIndex => SafeCookAgent().memory.currentStepIndex;
  set currentStepIndex(int val) => SafeCookAgent().memory.currentStepIndex = val;
  bool _autoReadSteps = true;

  // Voice assistant state
  String _assistantState = 'idle'; // 'idle' | 'listening' | 'processing'
  String _userSpokenText = '';
  String _assistantReplyText = '';
  int _consecutiveSilenceTurns = 0;

  // Services (all singletons — share state across screens)
  final VoiceService _voiceService = VoiceService();
  final SpeechService _speechService = SpeechService();
  final VoiceAssistantService _assistantService = VoiceAssistantService();
  final WakeWordService _wakeWordService = WakeWordService();

  // Safety tracking
  String _lastGuidanceSafetyState = 'STANDBY';

  @override
  void initState() {
    super.initState();
    widget.homeState.addSensorListener(onSensorUpdate);

    // Seed agent with this recipe and cooking state
    SafeCookAgent().selectedRecipe = widget.recipe;
    SafeCookAgent().conversationState = ConversationState.cooking;
    SafeCookAgent().memory.isCookingActive = true;
    SafeCookAgent().confirmStepIndex(0);

    // Speak step 1 and then start listening
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _voiceService.setCompletionCallback(() {
        _voiceService.setCompletionCallback(null);
        _startVoiceCommandListening();
      });
      if (!widget.startSilently) {
        speakCurrentStep();
      }
    });
  }

  @override
  void dispose() {
    widget.homeState.removeSensorListener(onSensorUpdate);
    // Clear TTS callback FIRST to prevent any pending callbacks from firing
    _voiceService.setCompletionCallback(null);
    _voiceService.stop();
    _speechService.stopListening();
    _wakeWordService.stopWakeWordDetection();
    // Reset agent so next session starts clean
    SafeCookAgent().reset();
    super.dispose();
  }

  // -------------------------------------------------------------------------
  // Sensor safety interrupt — must not cause double listening
  // -------------------------------------------------------------------------
  void onSensorUpdate() {
    if (!mounted) return;
    final newState = widget.homeState.currentSafetyState;
    if (newState == _lastGuidanceSafetyState) return;

    final oldState = _lastGuidanceSafetyState;
    _lastGuidanceSafetyState = newState;

    String? alertMessage;
    if (newState == 'CRITICAL') {
      alertMessage = 'Critical warning! Please check the stove area immediately.';
    } else if (newState == 'GAS ALERT') {
      alertMessage = 'Warning. The gas level is high. Please check the stove environment.';
    } else if (newState == 'DISTANCE ALERT') {
      alertMessage =
          'Warning. You are too close to the cooking vessel. Please step back.';
    } else if (newState == 'CAUTION') {
      alertMessage = 'Caution. Elevated risk detected.';
    } else if (newState == 'SAFE' &&
        (oldState == 'CAUTION' ||
            oldState == 'GAS ALERT' ||
            oldState == 'DISTANCE ALERT' ||
            oldState == 'CRITICAL')) {
      alertMessage = 'The cooking environment is now safe again.';
    }

    if (alertMessage != null) {
      // Stop mic listening during safety alert speech to prevent feedback loop
      _speechService.stopListening();
      _wakeWordService.stopWakeWordDetection();

      // Phase 0 fix: clear callback BEFORE stopping to prevent race condition
      _voiceService.setCompletionCallback(null);
      _voiceService.stop();
      _voiceService.setCompletionCallback(() {
        _voiceService.setCompletionCallback(null);
        _startVoiceCommandListening();
      });
      _voiceService.speak(alertMessage);
    }

    if (mounted) setState(() {});
  }

  // -------------------------------------------------------------------------
  // Wake word (fallback after consecutive silences)
  // -------------------------------------------------------------------------
  Future<void> _startWakeWordDetection() async {
    await _speechService.initialize();
    await _wakeWordService.startWakeWordDetection(
      onWakeDetected: () async {
        if (!mounted) return;
        setState(() {
          _assistantState = 'processing';
          _assistantReplyText = 'Hello! What would you like to do?';
        });
        _voiceService.setCompletionCallback(null);
        _voiceService.setCompletionCallback(() {
          _voiceService.setCompletionCallback(null);
          _startVoiceCommandListening();
        });
        await _voiceService.speak('Hello! What would you like to do?');
      },
    );
  }

  // -------------------------------------------------------------------------
  // Main command listening loop
  // -------------------------------------------------------------------------
  Future<void> _startVoiceCommandListening() async {
    if (!mounted) return;
    setState(() {
      _assistantState = 'listening';
      _userSpokenText = '';
    });

    await _speechService.startListening(
      onResult: (text) {
        if (mounted) setState(() => _userSpokenText = text);
      },
      onError: (err) async {
        _consecutiveSilenceTurns++;
        const maxSilence = 5; // Cooking screen: stay listening longer
        if (_consecutiveSilenceTurns >= maxSilence) {
          _consecutiveSilenceTurns = 0;
          if (mounted) {
            setState(() {
              _assistantState = 'idle';
              _assistantReplyText =
                  "I'll wait here. Say Hello SafeCook when you need me.";
            });
          }
          _voiceService.setCompletionCallback(null);
          await _voiceService.speak(
              "I'll wait here. Say Hello SafeCook when you need me.");
          _startWakeWordDetection();
        } else {
          _startVoiceCommandListening();
        }
      },
      onDoneListening: () async {
        final query = _userSpokenText.trim();
        _userSpokenText = ''; // Clear immediately to prevent duplicate execution

        if (query.isEmpty) {
          _consecutiveSilenceTurns++;
          const maxSilence = 5;
          if (_consecutiveSilenceTurns >= maxSilence) {
            _consecutiveSilenceTurns = 0;
            if (mounted) {
              setState(() {
                _assistantState = 'idle';
                _assistantReplyText =
                    "I'll wait here. Say Hello SafeCook when you need me.";
              });
            }
            _voiceService.setCompletionCallback(null);
            await _voiceService
                .speak("I'll wait here. Say Hello SafeCook when you need me.");
            _startWakeWordDetection();
          } else {
            _startVoiceCommandListening();
          }
          return;
        }

        _consecutiveSilenceTurns = 0;
        if (mounted) setState(() => _assistantState = 'processing');

        final eventId = DateTime.now().millisecondsSinceEpoch;
        debugPrint('[SafeCook VOICE]\n'
            'eventId=$eventId\n'
            'recognized="$query"\n'
            'processingStarted=true');

        final voiceCtx = VoiceAssistantContext(
          recipe: widget.recipe,
          currentStepIndex: currentStepIndex,
          totalSteps: widget.recipe.steps.length,
          gasValue: widget.homeState.currentGasValue,
          distanceValue: widget.homeState.currentDistanceValue,
          safetyState: widget.homeState.currentSafetyState,
          sessionDuration: widget.homeState.sessionDuration,
          isCookingActive: true,
          isBluetoothConnected: widget.homeState.isBluetoothConnected,
        );

        final actions = VoiceAssistantActions(
          onNextStep: () async {
            if (currentStepIndex < widget.recipe.steps.length - 1) {
              goToNextStep(speak: false);
              return const ToolResult.ok('Advanced to next step');
            }
            return const ToolResult.fail('Already on last step');
          },
          onPreviousStep: () async {
            if (currentStepIndex > 0) {
              goToPreviousStep(speak: false);
              return const ToolResult.ok('Went back to previous step');
            }
            return const ToolResult.fail('Already on first step');
          },
          onRepeatStep: () async {
            // Agent's reply contains the instructions and will be spoken by outer voice loop
            return const ToolResult.ok('Repeating step');
          },
          onGoToStep: (stepNumber) async {
            final idx = stepNumber - 1;
            if (idx >= 0 && idx < widget.recipe.steps.length) {
              setState(() {
                SafeCookAgent().memory.goToStep(stepNumber);
              });
              // Agent's reply contains the instructions and will be spoken by outer voice loop
              return const ToolResult.ok('Navigated to step');
            }
            return ToolResult.fail(
                'Step $stepNumber does not exist in this recipe');
          },
          onEndCooking: () async {
            _endCooking();
            return const ToolResult.ok('Session ended');
          },
          onStartCooking: (recipe) async {
            // Already in cooking mode
            return const ToolResult.ok('Already cooking');
          },
          onConnectBluetooth: widget.homeState.connectBluetoothFromVoice,
          onDisconnectBluetooth: widget.homeState.disconnectBluetoothFromVoice,
          onBluetoothStatus: () => widget.homeState.bluetoothStatusResult(),
        );

        final reply = await _assistantService.processVoiceCommand(
          query,
          voiceCtx,
          actions,
        );

        if (mounted) setState(() => _assistantReplyText = reply);

        final agentState = SafeCookAgent().conversationState;
        final staysActive = agentState != ConversationState.idle;

        _voiceService.setCompletionCallback(null);
        _voiceService.setCompletionCallback(() {
          _voiceService.setCompletionCallback(null);
          if (!mounted) return;
          if (agentState == ConversationState.idle) {
            setState(() => _assistantState = 'idle');
            _startWakeWordDetection();
          } else if (staysActive) {
            _startVoiceCommandListening();
          } else {
            setState(() => _assistantState = 'idle');
            _startWakeWordDetection();
          }
        });

        await _voiceService.speak(reply);
      },
    );
  }

  Future<void> _startVoiceListening() async {
    await _wakeWordService.stopWakeWordDetection();
    await _startVoiceCommandListening();
  }

  // -------------------------------------------------------------------------
  // Step navigation — UI-authoritative, always syncs agent
  // -------------------------------------------------------------------------
  RecipeStep get currentStep => widget.recipe.steps[currentStepIndex];

  void speakCurrentStep({bool speak = true}) {
    if (!speak) return;
    _voiceService.setCompletionCallback(null);
    _voiceService.setCompletionCallback(() {
      _voiceService.setCompletionCallback(null);
      _startVoiceCommandListening();
    });
    _voiceService.speak(currentStep.voiceInstruction);
  }

  void goToNextStep({bool speak = true}) {
    if (currentStepIndex < widget.recipe.steps.length - 1) {
      setState(() {
        SafeCookAgent().memory.nextStep();
      });
      if (_autoReadSteps) speakCurrentStep(speak: speak);
    }
  }

  void goToPreviousStep({bool speak = true}) {
    if (currentStepIndex > 0) {
      setState(() {
        SafeCookAgent().memory.previousStep();
      });
      if (_autoReadSteps) speakCurrentStep(speak: speak);
    }
  }

  // -------------------------------------------------------------------------
  // End cooking — Phase 0 fix: always resets agent state
  // -------------------------------------------------------------------------
  void _endCooking() {
    // Clear TTS callbacks first to stop any queued resumption
    _voiceService.setCompletionCallback(null);
    _voiceService.stop();
    _speechService.stopListening();
    _wakeWordService.stopWakeWordDetection();

    widget.homeState.endCookingSessionOutside();

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => CookingReportScreen(
          recipe: widget.recipe,
          stepsCompleted: currentStepIndex + 1,
          duration: widget.homeState.sessionDuration,
          maxGas: widget.homeState.sessionMaxGas,
          minDistance: widget.homeState.sessionMinDistance,
          cautionCount: widget.homeState.sessionCautionCount,
          gasAlertCount: widget.homeState.sessionGasAlertCount,
          distanceAlertCount: widget.homeState.sessionDistanceAlertCount,
          criticalCount: widget.homeState.sessionCriticalCount,
          finalState: widget.homeState.sessionFinalState,
          sessionEvents: widget.homeState.sessionSafetyHistory,
        ),
      ),
    );
    // Note: agent reset happens in dispose() which is called after pushReplacement
  }

  // -------------------------------------------------------------------------
  // Build
  // -------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final step = currentStep;
    final totalSteps = widget.recipe.steps.length;

    final gasVal = widget.homeState.currentGasValue;
    final distVal = widget.homeState.currentDistanceValue;
    final safetyState = widget.homeState.currentSafetyState;
    final safetyColor = widget.homeState.currentSafetyColor;
    final safetyBgColor = widget.homeState.currentSafetyBgColor;
    final safetyBorderColor = widget.homeState.currentSafetyBorderColor;

    final isCritical = safetyState == 'CRITICAL';
    final isAlert =
        safetyState == 'GAS ALERT' || safetyState == 'DISTANCE ALERT';

    // Gas percentage for display
    final gasPercent = gasVal != null
        ? GasCalibration.toPercent(gasVal).toStringAsFixed(0)
        : null;

    return Scaffold(
      appBar: AppBar(
        title:
            Text(widget.recipe.name, style: const TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          TextButton(
            onPressed: _endCooking,
            child: const Text(
              'END COOKING',
              style: TextStyle(
                  color: Colors.redAccent, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // Safety alert banner
          if (safetyState != 'SAFE' && safetyState != 'STANDBY')
            Container(
              width: double.infinity,
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: safetyBgColor,
                border: Border(
                    bottom:
                        BorderSide(color: safetyBorderColor, width: 2)),
              ),
              child: Row(
                children: [
                  Icon(
                    isCritical
                        ? Icons.gpp_bad
                        : Icons.warning_amber_rounded,
                    color: safetyColor,
                    size: 28,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'SAFETY ALERT: $safetyState',
                          style: TextStyle(
                            color: safetyColor,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          isCritical
                              ? 'Critical hazard! Secure the vessel and clear the stove.'
                              : isAlert
                                  ? 'Hazard detected! Check the stove environment immediately.'
                                  : 'Caution: Elevated safety risk detected.',
                          style: const TextStyle(
                              color: Colors.white, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  const SizedBox(height: 10),
                  // Step counter
                  Text(
                    'Step ${currentStepIndex + 1} of $totalSteps',
                    style: const TextStyle(
                      color: Colors.white30,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Voice assistant card
                  Card(
                    color: const Color(0xFF1E293B),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Icon(
                                _assistantState == 'listening'
                                    ? Icons.mic
                                    : _assistantState == 'processing'
                                        ? Icons.query_stats
                                        : Icons.mic_none,
                                color: _assistantState == 'listening'
                                    ? Colors.redAccent
                                    : _assistantState == 'processing'
                                        ? const Color(0xFF38BDF8)
                                        : Colors.white54,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                _assistantState == 'listening'
                                    ? 'LISTENING...'
                                    : _assistantState == 'processing'
                                        ? 'UNDERSTANDING...'
                                        : 'SAFECOOK VOICE',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                  color: _assistantState == 'listening'
                                      ? Colors.redAccent
                                      : _assistantState == 'processing'
                                          ? const Color(0xFF38BDF8)
                                          : Colors.white54,
                                ),
                              ),
                            ],
                          ),
                          if (_userSpokenText.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('YOU: ',
                                    style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFF38BDF8),
                                        fontSize: 13)),
                                Expanded(
                                  child: Text('"$_userSpokenText"',
                                      style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 13,
                                          fontStyle: FontStyle.italic)),
                                ),
                              ],
                            ),
                          ],
                          if (_assistantReplyText.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('SAFECOOK: ',
                                    style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFF10B981),
                                        fontSize: 13)),
                                Expanded(
                                  child: Text(_assistantReplyText,
                                      style: const TextStyle(
                                          color: Colors.white70,
                                          fontSize: 13)),
                                ),
                              ],
                            ),
                          ],
                          const SizedBox(height: 14),
                          ElevatedButton.icon(
                            onPressed: _assistantState == 'listening'
                                ? _speechService.stopListening
                                : _startVoiceListening,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _assistantState == 'listening'
                                  ? Colors.red.shade900
                                  : const Color(0xFF0EA5E9),
                              foregroundColor: Colors.white,
                              minimumSize: const Size(double.infinity, 40),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8)),
                            ),
                            icon: Icon(_assistantState == 'listening'
                                ? Icons.stop
                                : Icons.mic),
                            label: Text(
                              _assistantState == 'listening'
                                  ? 'STOP LISTENING'
                                  : 'ASK SAFECOOK',
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Step instruction card
                  Card(
                    color: const Color(0xFF1E293B),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                    child: Padding(
                      padding: const EdgeInsets.all(20.0),
                      child: Column(
                        children: [
                          Text(
                            step.instruction.toUpperCase(),
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                              height: 1.4,
                            ),
                          ),
                          const SizedBox(height: 20),
                          if (step.safetyTip != null) ...[
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: const Color(0x1AF59E0B),
                                borderRadius: BorderRadius.circular(8),
                                border:
                                    Border.all(color: const Color(0x33F59E0B)),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.shield_outlined,
                                      color: Color(0xFFF59E0B), size: 18),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      step.safetyTip!,
                                      style: const TextStyle(
                                          color: Color(0xFFF59E0B),
                                          fontSize: 12),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 20),
                          ],
                          ElevatedButton.icon(
                            onPressed: speakCurrentStep,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.white10,
                              foregroundColor: Colors.white,
                              minimumSize: const Size(150, 44),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(22),
                              ),
                            ),
                            icon: const Icon(Icons.volume_up, size: 20),
                            label: const Text('READ STEP',
                                style:
                                    TextStyle(fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Auto-read toggle
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.spatial_audio_off,
                          size: 16, color: Colors.white30),
                      const SizedBox(width: 8),
                      const Text('Auto-read next step',
                          style:
                              TextStyle(color: Colors.white54, fontSize: 13)),
                      Switch(
                        value: _autoReadSteps,
                        onChanged: (val) =>
                            setState(() => _autoReadSteps = val),
                        activeThumbColor: const Color(0xFF38BDF8),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // Bottom bar — sensors + navigation
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              color: Color(0xFF1E293B),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
              ),
            ),
            child: SafeArea(
              top: false,
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'SAFETY MONITORING',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Colors.white54,
                            letterSpacing: 1),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: safetyBgColor,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: safetyBorderColor),
                        ),
                        child: Text(
                          safetyState,
                          style: TextStyle(
                              color: safetyColor,
                              fontSize: 10,
                              fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _buildSensorTile(
                          'Flame Level',
                          gasPercent != null
                              ? '$gasPercent%'
                              : (gasVal != null ? '$gasVal raw' : '--'),
                          Icons.local_fire_department_outlined,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildSensorTile(
                          'Distance to Vessel',
                          distVal ?? '--',
                          Icons.social_distance_outlined,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed:
                              currentStepIndex > 0 ? goToPreviousStep : null,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: const BorderSide(color: Colors.white10),
                            minimumSize: const Size(0, 44),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8)),
                          ),
                          child: const Text('PREVIOUS'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: currentStepIndex < totalSteps - 1
                              ? goToNextStep
                              : _endCooking,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF0EA5E9),
                            foregroundColor: Colors.white,
                            minimumSize: const Size(0, 44),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8)),
                          ),
                          child: Text(
                            currentStepIndex == totalSteps - 1
                                ? 'FINISH'
                                : 'NEXT',
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSensorTile(String label, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.white30, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(
                        fontSize: 10, color: Colors.white54)),
                Text(
                  value,
                  style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.white),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @visibleForTesting
  void testSetStepIndex(int index) {
    setState(() {
      currentStepIndex = index;
    });
  }
}
