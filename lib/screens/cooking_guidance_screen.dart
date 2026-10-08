// ignore_for_file: avoid_print
import 'package:flutter/material.dart';
import '../models/recipe.dart';
import '../models/cooking_history_entry.dart';
import '../services/voice_service.dart';
import '../main.dart';
import 'cooking_report_screen.dart';
import '../services/speech_service.dart';
import '../services/voice_assistant_service.dart';
import '../services/wake_word_service.dart';
import '../agent/safecook_agent.dart';
import '../agent/safecook_context.dart';
import '../agent/safecook_tools.dart';
import '../safety/safecook_safety_state.dart';
import '../safety/safecook_safety_event.dart';
import '../safety/safecook_safety_voice_controller.dart';
import '../services/preference_service.dart';
import '../theme/safecook_theme.dart';
import '../widgets/safecook_widgets.dart';

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

class CookingGuidanceScreenState extends State<CookingGuidanceScreen>
    implements SafetyVoiceDelegate {
  // -------------------------------------------------------------------------
  // Step navigation — this is the AUTHORITATIVE index for the UI.
  // Every change calls SafeCookAgent().confirmStepIndex(idx) to keep the
  // agent in sync.
  // -------------------------------------------------------------------------
  int get currentStepIndex => SafeCookAgent().memory.currentStepIndex;
  set currentStepIndex(int val) =>
      SafeCookAgent().memory.currentStepIndex = val;
  bool _autoReadSteps = true;

  // Voice assistant state
  String _assistantState = 'idle'; // 'idle' | 'listening' | 'processing'
  String _userSpokenText = '';
  String _assistantReplyText = '';
  int _consecutiveSilenceTurns = 0;
  final VoiceConversationMode _voiceConversation = VoiceConversationMode()
    ..activate();
  bool _voiceListenStarting = false;

  // Services (all singletons — share state across screens)
  final VoiceService _voiceService = VoiceService();
  final SpeechService _speechService = SpeechService();
  final VoiceAssistantService _assistantService = VoiceAssistantService();
  final WakeWordService _wakeWordService = WakeWordService();

  // Safety tracking
  String? _lastSpokenText;

  // Interruption tracking fields
  String? _interruptedText;
  bool _wasListeningBeforeAlert = false;
  int _interruptedStepIndex = -1;
  String _interruptedConvState = '';

  @override
  void initState() {
    super.initState();
    widget.homeState.addSensorListener(onSensorUpdate);
    SafetyVoiceController().registerCookingScreen(this);

    // Seed the single authoritative session owner with this recipe.
    SafeCookAgent().startCookingSession(widget.recipe);

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
    SafetyVoiceController().unregisterCookingScreen(this);
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
    // Stub kept for compatibility/rebuild notifications
    if (mounted) setState(() {});
  }

  @override
  void handleSafetyVoiceEvent(SafeCookSafetyEvent event) {
    if (!mounted) return;

    final newState = event.currentState;
    final oldState = event.previousState;

    String? voiceMsg;
    bool isAlert = false;

    if (newState == SafeCookSafetyState.critical) {
      voiceMsg = newState.voiceMessage;
      isAlert = true;
    } else if (newState == SafeCookSafetyState.gasAlert) {
      voiceMsg = newState.voiceMessage;
      isAlert = true;
    } else if (newState == SafeCookSafetyState.distanceAlert) {
      voiceMsg = newState.voiceMessage;
      isAlert = true;
    } else if (newState == SafeCookSafetyState.caution) {
      voiceMsg = newState.voiceMessage;
      isAlert = true;
    } else if (newState == SafeCookSafetyState.sensorUnavailable) {
      if (oldState != SafeCookSafetyState.sensorUnavailable) {
        voiceMsg = newState.voiceMessage;
        isAlert = true;
      }
    } else if (newState == SafeCookSafetyState.safe) {
      if (oldState == SafeCookSafetyState.critical ||
          oldState == SafeCookSafetyState.gasAlert ||
          oldState == SafeCookSafetyState.distanceAlert ||
          oldState == SafeCookSafetyState.caution ||
          oldState == SafeCookSafetyState.sensorUnavailable) {
        voiceMsg = newState.voiceMessage;
      }
    }

    if (voiceMsg != null) {
      if (isAlert) {
        // Capture context for interruption
        _wasListeningBeforeAlert = _speechService.isListening;
        _interruptedStepIndex = currentStepIndex;
        _interruptedConvState = SafeCookAgent().conversationState.name;
        _interruptedText = _voiceService.isSpeaking ? _lastSpokenText : null;

        // Stop TTS and microphone immediately
        _speechService.stopListening();
        _wakeWordService.stopWakeWordDetection();
        _voiceService.setCompletionCallback(null);
        _voiceService.stop();
      }

      // Speak safety warning
      _voiceService.setCompletionCallback(() {
        _voiceService.setCompletionCallback(null);
        _resumeInterruptedState();
      });
      _voiceService.speak(voiceMsg);
    }

    if (mounted) setState(() {});
  }

  void _resumeInterruptedState() {
    if (!mounted) return;

    final cookingStillActive = widget.homeState.isCookingActive;
    if (cookingStillActive &&
        _interruptedStepIndex == currentStepIndex &&
        _interruptedConvState == SafeCookAgent().conversationState.name) {
      if (_interruptedText != null && _interruptedText!.isNotEmpty) {
        _voiceService.setCompletionCallback(() {
          _voiceService.setCompletionCallback(null);
          _startVoiceCommandListening();
        });
        _voiceService.speak(_interruptedText!);
      } else if (_wasListeningBeforeAlert) {
        _startVoiceCommandListening();
      } else {
        _startVoiceCommandListening();
      }
    } else {
      _startVoiceCommandListening();
    }
  }

  // -------------------------------------------------------------------------
  // Wake word (fallback after consecutive silences)
  // -------------------------------------------------------------------------
  Future<void> _startWakeWordDetection() async {
    _voiceConversation.deactivate();
    await _speechService.initialize();
    await _wakeWordService.startWakeWordDetection(
      onWakeDetected: () async {
        _voiceConversation.activate();
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
        await _speakAndTrack('Hello! What would you like to do?');
      },
    );
  }

  // -------------------------------------------------------------------------
  // Main command listening loop
  // -------------------------------------------------------------------------
  Future<void> _startVoiceCommandListening() async {
    if (!mounted) return;
    if (_voiceListenStarting || _speechService.isListening) return;
    _voiceListenStarting = true;
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
          await _speakAndTrack(
            "I'll wait here. Say Hello SafeCook when you need me.",
          );
          _startWakeWordDetection();
        } else {
          await _speechService.stopListening();
          _startVoiceCommandListening();
        }
      },
      onDoneListening: () async {
        final query = _userSpokenText.trim();
        _userSpokenText =
            ''; // Clear immediately to prevent duplicate execution

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
            await _voiceService.speak(
              "I'll wait here. Say Hello SafeCook when you need me.",
            );
            _startWakeWordDetection();
          } else {
            await _speechService.stopListening();
            _startVoiceCommandListening();
          }
          return;
        }

        _consecutiveSilenceTurns = 0;
        if (mounted) setState(() => _assistantState = 'processing');

        final eventId = DateTime.now().millisecondsSinceEpoch;
        debugPrint(
          '[SafeCook VOICE]\n'
          'eventId=$eventId\n'
          'recognized="$query"\n'
          'processingStarted=true',
        );

        final voiceCtx = VoiceAssistantContext(
          gasValue: widget.homeState.currentGasValue,
          distanceValue: widget.homeState.currentDistanceValue,
          safetyState: widget.homeState.currentSafetyState,
          sessionDuration: widget.homeState.sessionDuration,
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
              'Step $stepNumber does not exist in this recipe',
            );
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

        if (_isVoiceExitPhrase(query)) _voiceConversation.deactivate();

        final agentState = SafeCookAgent().conversationState;
        final staysActive = agentState != ConversationState.idle;

        _voiceService.setCompletionCallback(null);
        _voiceService.setCompletionCallback(() {
          _voiceService.setCompletionCallback(null);
          if (!mounted) return;
          if (!_voiceConversation.shouldListenAfterTts()) {
            setState(() => _assistantState = 'idle');
            _startWakeWordDetection();
          } else if (staysActive && _voiceConversation.shouldListenAfterTts()) {
            _startVoiceCommandListening();
          } else {
            setState(() => _assistantState = 'idle');
            _startWakeWordDetection();
          }
        });

        await _speakAndTrack(reply);
      },
    );
    _voiceListenStarting = false;
  }

  bool _isVoiceExitPhrase(String text) {
    final q = text.toLowerCase().trim();
    return q == 'goodbye' ||
        q == 'bye' ||
        q == 'go to sleep' ||
        q == 'stop listening' ||
        q == 'end conversation' ||
        q == 'cancel conversation';
  }

  Future<void> _startVoiceListening() async {
    await _wakeWordService.stopWakeWordDetection();
    await _startVoiceCommandListening();
  }

  // -------------------------------------------------------------------------
  // Step navigation — UI-authoritative, always syncs agent
  // -------------------------------------------------------------------------
  RecipeStep get currentStep => widget.recipe.steps[currentStepIndex];

  Future<void> _speakAndTrack(String text) async {
    _lastSpokenText = text;
    await _voiceService.speak(text);
  }

  void speakCurrentStep({bool speak = true}) {
    if (!speak) return;
    _voiceService.setCompletionCallback(null);
    _voiceService.setCompletionCallback(() {
      _voiceService.setCompletionCallback(null);
      _startVoiceCommandListening();
    });
    _speakAndTrack(currentStep.voiceInstruction);
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
  Future<void> _endCooking() async {
    // Clear TTS callbacks first to stop any queued resumption
    _voiceService.setCompletionCallback(null);
    _voiceService.stop();
    _speechService.stopListening();
    _wakeWordService.stopWakeWordDetection();

    final totalSteps = widget.recipe.steps.length;
    final completedSteps = currentStepIndex + 1;
    final isCompleted = (currentStepIndex == totalSteps - 1);

    if (isCompleted) {
      await PreferenceService().incrementCookCount(widget.recipe.id);
      await PreferenceService().setLastCookedRecipeId(widget.recipe.id);
    }
    await PreferenceService().addToRecentRecipes(widget.recipe.id);
    await PreferenceService().addCookingHistoryEntry(
      CookingHistoryEntry(
        recipeId: widget.recipe.id,
        completedAt: DateTime.now(),
        duration: widget.homeState.sessionDuration,
        stepsCompleted: currentStepIndex + 1,
        totalSteps: totalSteps,
        completed: isCompleted,
      ),
    );

    widget.homeState.endCookingSessionOutside();

    if (!mounted) return;

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => CookingReportScreen(
          recipe: widget.recipe,
          stepsCompleted: completedSteps,
          duration: widget.homeState.sessionDuration,
          maxGas: widget.homeState.sessionMaxGas,
          minDistance: widget.homeState.sessionMinDistance,
          cautionCount: widget.homeState.sessionCautionCount,
          gasAlertCount: widget.homeState.sessionGasAlertCount,
          distanceAlertCount: widget.homeState.sessionDistanceAlertCount,
          criticalCount: widget.homeState.sessionCriticalCount,
          finalState: widget.homeState.sessionFinalState,
          sessionEvents: widget.homeState.sessionSafetyHistory,
          completed: isCompleted,
        ),
      ),
    );
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

    // Progress fraction
    final progress = (currentStepIndex + 1) / totalSteps;

    return Scaffold(
      backgroundColor: SafeCookColors.background,
      appBar: AppBar(
        backgroundColor: SafeCookColors.background,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.recipe.name,
              style: const TextStyle(
                fontFamily: 'Nunito',
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: SafeCookColors.textPrimary,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              'Step ${currentStepIndex + 1} of $totalSteps',
              style: const TextStyle(
                fontFamily: 'Nunito',
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: SafeCookColors.textSecondary,
              ),
            ),
          ],
        ),
        actions: [
          Semantics(
            button: true,
            label: 'End cooking session',
            child: TextButton(
              onPressed: _endCooking,
              child: const Text(
                'END COOKING',
                style: TextStyle(
                  fontFamily: 'Nunito',
                  color: SafeCookColors.danger,
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                ),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // ── Safety alert banner (non-safe states only) ──────────────────
          if (safetyState != 'SAFE' && safetyState != 'STANDBY')
            SafetyAlertBanner(
              status: safetyState,
              message: isCritical
                  ? 'Critical hazard! Secure the area and step back from the stove.'
                  : isAlert
                  ? 'Hazard detected! Check the stove environment immediately.'
                  : 'Elevated safety risk — stay attentive.',
            ),

          // ── Step progress bar ───────────────────────────────────────────
          Container(
            color: SafeCookColors.surface,
            padding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Progress',
                      style: SafeCookTextStyles.label,
                    ),
                    Text(
                      '${(progress * 100).round()}%',
                      style: const TextStyle(
                        fontFamily: 'Nunito',
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: SafeCookColors.primaryLight,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 6,
                    backgroundColor: SafeCookColors.surfaceHighest,
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      SafeCookColors.primaryLight,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── Scrollable content ──────────────────────────────────────────
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ── Current step card ─────────────────────────────────
                  SCCard(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Step indicator row
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: SafeCookColors.primaryContainer,
                                borderRadius:
                                    BorderRadius.circular(SafeCookRadius.full),
                              ),
                              child: Text(
                                'STEP ${currentStepIndex + 1}',
                                style: const TextStyle(
                                  fontFamily: 'Nunito',
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  color: SafeCookColors.primaryLight,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                            const Spacer(),
                            // Auto-read toggle (compact)
                            Tooltip(
                              message: 'Auto-read next step',
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.spatial_audio_rounded,
                                    size: 14,
                                    color: SafeCookColors.textMuted,
                                  ),
                                  const SizedBox(width: 4),
                                  Transform.scale(
                                    scale: 0.75,
                                    child: Switch(
                                      value: _autoReadSteps,
                                      onChanged: (val) =>
                                          setState(() => _autoReadSteps = val),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 16),

                        // Step instruction text — make this DOMINANT
                        Text(
                          step.instruction,
                          style: SafeCookTextStyles.stepInstruction,
                        ),

                        // Safety tip
                        if (step.safetyTip != null) ...[
                          const SizedBox(height: 16),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: SafeCookColors.cautionBg,
                              borderRadius:
                                  BorderRadius.circular(SafeCookRadius.xs),
                              border: Border.all(
                                color: SafeCookColors.cautionBorder,
                              ),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.shield_outlined,
                                  color: SafeCookColors.caution,
                                  size: 16,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    step.safetyTip!,
                                    style: const TextStyle(
                                      fontFamily: 'Nunito',
                                      color: SafeCookColors.caution,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      height: 1.4,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],

                        const SizedBox(height: 20),

                        // Read step aloud button
                        Semantics(
                          button: true,
                          label: 'Read current cooking step aloud',
                          child: OutlinedButton.icon(
                            onPressed: speakCurrentStep,
                            style: OutlinedButton.styleFrom(
                              foregroundColor: SafeCookColors.primaryLight,
                              side: const BorderSide(
                                color: SafeCookColors.primaryLight,
                                width: 0.8,
                              ),
                              minimumSize: const Size(double.infinity, 48),
                              shape: RoundedRectangleBorder(
                                borderRadius:
                                    BorderRadius.circular(SafeCookRadius.xs),
                              ),
                            ),
                            icon: const Icon(
                              Icons.volume_up_rounded,
                              size: 18,
                            ),
                            label: const Text(
                              'Read Step Aloud',
                              style: TextStyle(
                                fontFamily: 'Nunito',
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // ── Voice assistant card ──────────────────────────────
                  SCCard(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        VoiceStatusBar(
                          assistantState: _assistantState,
                          onTap: _assistantState == 'listening'
                              ? _speechService.stopListening
                              : _startVoiceListening,
                        ),

                        // Conversation transcript
                        if (_userSpokenText.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          ConversationLine(
                            speaker: 'YOU',
                            text: _userSpokenText,
                          ),
                        ],
                        if (_assistantReplyText.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          ConversationLine(
                            speaker: 'SAFECOOK',
                            text: _assistantReplyText,
                          ),
                        ],
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),

          // ── Bottom bar: sensors + navigation ───────────────────────────
          Container(
            decoration: BoxDecoration(
              color: SafeCookColors.surface,
              border: const Border(
                top: BorderSide(color: SafeCookColors.border, width: 0.5),
              ),
            ),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                child: Column(
                  children: [
                    // Sensor row
                    Row(
                      children: [
                        Expanded(
                          child: _buildSensorPill(
                            'Gas',
                            gasPercent != null ? '$gasPercent%' : '--',
                            Icons.gas_meter_outlined,
                            safetyState == 'GAS ALERT' ||
                                    safetyState == 'CRITICAL'
                                ? SafeCookColors.danger
                                : SafeCookColors.textSecondary,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _buildSensorPill(
                            'Chef Distance',
                            distVal ?? '--',
                            Icons.social_distance_outlined,
                            safetyState == 'DISTANCE ALERT' ||
                                    safetyState == 'CRITICAL'
                                ? SafeCookColors.danger
                                : SafeCookColors.textSecondary,
                          ),
                        ),
                        const SizedBox(width: 8),
                        // Safety state compact badge
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: safetyBgColor,
                            borderRadius:
                                BorderRadius.circular(SafeCookRadius.xs),
                            border: Border.all(color: safetyBorderColor),
                          ),
                          child: Column(
                            children: [
                              Icon(
                                safetyState == 'SAFE'
                                    ? Icons.verified_user_rounded
                                    : safetyState == 'CRITICAL'
                                    ? Icons.gpp_bad_rounded
                                    : Icons.warning_rounded,
                                color: safetyColor,
                                size: 16,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                safetyState == 'STANDBY'
                                    ? 'STANDBY'
                                    : safetyState == 'SAFE'
                                    ? 'SAFE'
                                    : '!',
                                style: TextStyle(
                                  fontFamily: 'Nunito',
                                  color: safetyColor,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 12),

                    // Navigation buttons
                    Row(
                      children: [
                        // Previous
                        Expanded(
                          child: Semantics(
                            button: true,
                            label: 'Go to previous cooking step',
                            child: OutlinedButton(
                              onPressed: currentStepIndex > 0
                                  ? goToPreviousStep
                                  : null,
                              style: OutlinedButton.styleFrom(
                                foregroundColor: SafeCookColors.textPrimary,
                                side: const BorderSide(
                                  color: SafeCookColors.border,
                                ),
                                minimumSize: const Size(0, 52),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(
                                    SafeCookRadius.xs,
                                  ),
                                ),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.arrow_back_ios_new_rounded,
                                      size: 14),
                                  const SizedBox(width: 4),
                                  const Flexible(
                                    child: Text(
                                      'Previous',
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontFamily: 'Nunito',
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(width: 12),

                        // Next / Finish
                        Expanded(
                          flex: 2,
                          child: Semantics(
                            button: true,
                            label: currentStepIndex < totalSteps - 1
                                ? 'Go to next cooking step'
                                : 'Finish cooking session',
                            child: ElevatedButton(
                              onPressed: currentStepIndex < totalSteps - 1
                                  ? goToNextStep
                                  : _endCooking,
                              style: ElevatedButton.styleFrom(
                                backgroundColor:
                                    currentStepIndex == totalSteps - 1
                                    ? SafeCookColors.safe
                                    : SafeCookColors.primary,
                                foregroundColor: Colors.white,
                                minimumSize: const Size(0, 52),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(
                                    SafeCookRadius.xs,
                                  ),
                                ),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Flexible(
                                    child: Text(
                                      currentStepIndex == totalSteps - 1
                                          ? 'Finish Cooking'
                                          : 'Next Step',
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontFamily: 'Nunito',
                                        fontSize: 15,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Icon(
                                    currentStepIndex == totalSteps - 1
                                        ? Icons.check_rounded
                                        : Icons.arrow_forward_ios_rounded,
                                    size: 14,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSensorPill(
    String label,
    String value,
    IconData icon,
    Color valueColor,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: SafeCookColors.surfaceElevated,
        borderRadius: BorderRadius.circular(SafeCookRadius.xs),
        border: Border.all(color: SafeCookColors.border, width: 0.5),
      ),
      child: Row(
        children: [
          Icon(icon, color: valueColor, size: 14),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontFamily: 'Nunito',
                    fontSize: 9,
                    color: SafeCookColors.textMuted,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                  ),
                ),
                Text(
                  value,
                  style: TextStyle(
                    fontFamily: 'Nunito',
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: valueColor,
                  ),
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
