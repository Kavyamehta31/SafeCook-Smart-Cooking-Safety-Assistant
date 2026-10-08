import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'models/recipe.dart';
import 'data/recipes.dart';
import 'screens/recipe_list_screen.dart';
import 'screens/cooking_guidance_screen.dart';
import 'screens/memory_screen.dart';
import 'services/speech_service.dart';
import 'services/voice_service.dart';
import 'services/voice_assistant_service.dart';
import 'services/wake_word_service.dart';
import 'agent/safecook_agent.dart';
import 'agent/safecook_tools.dart';
import 'safety/safecook_safety_engine.dart';
import 'safety/safecook_safety_state.dart';
import 'safety/safecook_safety_event.dart';
import 'safety/safecook_safety_voice_controller.dart';
import 'services/preference_service.dart';
import 'theme/safecook_theme.dart';
import 'widgets/safecook_widgets.dart';

// SafeCook Safety Thresholds
const int kGasNormalMax = 300; // Gas levels < 300 are Normal
const int kGasWarningMax =
    600; // Gas levels 300 to 599 are Warning, >= 600 are Critical

const double kDistanceSafeMin = 30.0; // Distance > 30 cm is Safe
const double kDistanceWarningMin =
    15.0; // Distance 15 to 30 cm is Close, < 15 cm is Very Close

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await PreferenceService().init();
  runApp(const SafeCookBluetoothTestApp());
}

enum ClassicAdapterState { unknown, on, off }

class BluetoothDevice {
  final String name;
  final String address;
  final String bondState;

  BluetoothDevice({
    required this.name,
    required this.address,
    required this.bondState,
  });

  factory BluetoothDevice.fromMap(Map<dynamic, dynamic> map) {
    return BluetoothDevice(
      name: map['name'] as String? ?? 'Unknown Device',
      address: map['address'] as String? ?? '',
      bondState: map['bondState'] as String? ?? 'unknown',
    );
  }
}

class SafetyEvent {
  final DateTime timestamp;
  final String state;
  final int? gasValue;
  final String? distanceValue;

  SafetyEvent({
    required this.timestamp,
    required this.state,
    this.gasValue,
    this.distanceValue,
  });
}

class SensorDataPoint {
  final DateTime timestamp;
  final double value;

  SensorDataPoint({required this.timestamp, required this.value});
}

class MiniLineChartPainter extends CustomPainter {
  final List<SensorDataPoint> data;
  final Color lineColor;
  final double? minVal;
  final double? maxVal;

  MiniLineChartPainter({
    required this.data,
    required this.lineColor,
    this.minVal,
    this.maxVal,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;

    final paint = Paint()
      ..color = lineColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;

    double min = minVal ?? data.first.value;
    double max = maxVal ?? data.first.value;

    for (var pt in data) {
      if (pt.value < min) min = pt.value;
      if (pt.value > max) max = pt.value;
    }

    if (max == min) {
      max += 1.0;
      min -= 1.0;
    }

    final path = Path();
    final stepX = size.width / 59.0;

    for (int i = 0; i < data.length; i++) {
      final x = size.width - (data.length - 1 - i) * stepX;
      final ratio = (data[i].value - min) / (max - min);
      final y = size.height - (ratio * size.height);

      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant MiniLineChartPainter oldDelegate) {
    return oldDelegate.data != data;
  }
}

class SafeCookBluetoothTestApp extends StatelessWidget {
  const SafeCookBluetoothTestApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SafeCook Bluetooth Test',
      debugShowCheckedModeBanner: false,
      theme: buildSafeCookTheme(),
      home: const BluetoothTestPage(),
    );
  }
}

class BluetoothTestPage extends StatefulWidget {
  static bool isTesting = false;
  const BluetoothTestPage({super.key});

  @override
  State<BluetoothTestPage> createState() => BluetoothTestPageState();
}

class BluetoothTestPageState extends State<BluetoothTestPage>
    implements SafetyVoiceDelegate {
  static const _methodChannel = MethodChannel('com.safecook.bluetooth/methods');
  static const _eventChannel = EventChannel('com.safecook.bluetooth/events');

  StreamSubscription? _eventChannelSub;
  StreamSubscription? _safetySubscription;

  ClassicAdapterState _adapterState = ClassicAdapterState.unknown;

  List<BluetoothDevice> _bondedDevices = [];
  final List<BluetoothDevice> _discoveredDevices = [];

  bool _isScanning = false;
  bool _isConnecting = false;

  BluetoothDevice? _connectedDevice;

  String _connectionStatus = 'Disconnected';
  String? _connectedDeviceAddress;
  String? _connectedDeviceName;

  Timer? _sensorFreshnessTimer;
  Completer<bool>? _connectionCompleter;

  bool _showPaired = true; // Tab toggle: true = Paired, false = Scanned
  bool _showBluetoothSettings = false;
  bool _showPreferences = false;
  bool _showDiagnostics = false;

  // Safety Listeners
  final List<VoidCallback> _sensorListeners = [];

  void addSensorListener(VoidCallback cb) {
    _sensorListeners.add(cb);
  }

  void removeSensorListener(VoidCallback cb) {
    _sensorListeners.remove(cb);
  }

  void _notifySensorListeners() {
    for (final cb in _sensorListeners) {
      cb();
    }
  }

  int? get currentGasValue => _gasValue;
  String? get currentDistanceValue => _distanceValue;
  bool get isBluetoothConnected => _connectedDevice != null;
  bool get isCookingActive => _isCookingActive;
  String get currentSafetyState => _getCombinedStatus();
  Color get currentSafetyColor => _getCombinedStatusColor();
  Color get currentSafetyBgColor => _getCombinedStatusBgColor();
  Color get currentSafetyBorderColor => _getCombinedStatusBorderColor();

  @visibleForTesting
  set bondedDevicesForTesting(List<BluetoothDevice> devices) {
    _bondedDevices = devices;
  }

  @visibleForTesting
  set connectedDeviceForTesting(BluetoothDevice? device) {
    _connectedDevice = device;
  }

  void endCookingSessionOutside() {
    _endCookingSession();
  }

  // -------------------------------------------------------------------------
  // Bluetooth voice tools — called by CookingGuidanceScreen via ToolResult
  // -------------------------------------------------------------------------
  Future<ToolResult> connectBluetoothFromVoice() async {
    final eventId = DateTime.now().millisecondsSinceEpoch;
    if (_connectedDevice != null) {
      debugPrint(
        '[SafeCook BT]\n'
        'eventId=$eventId\n'
        'recognized="connect sensor"\n'
        'intent=connectBluetooth\n'
        'tool=connectBluetooth\n'
        'nativeOperationStarted=false\n'
        'actualConnected=true',
      );
      return const ToolResult.ok('Already connected');
    }
    if (_bondedDevices.isEmpty) {
      debugPrint(
        '[SafeCook BT]\n'
        'eventId=$eventId\n'
        'recognized="connect sensor"\n'
        'intent=connectBluetooth\n'
        'tool=connectBluetooth\n'
        'nativeOperationStarted=false\n'
        'actualConnected=false\n'
        'failureStage=no_paired_devices',
      );
      return const ToolResult.fail(
        'No paired devices found. Pair the HC-05 in system settings first.',
      );
    }

    // Prioritized search:
    // 1. Exact normalized "hc-05" (Priority 1)
    // 2. Exact normalized "hc05" (Priority 2)
    // 3. Name containing "hc-05" (Priority 3)
    // 4. Name containing "hc05" (Priority 4)
    // 5. Name containing "stove" (Priority 5)
    // 6. Name containing "sensor" (Priority 6)

    BluetoothDevice? targetDevice;
    List<BluetoothDevice> candidates = [];
    int bestScore = 999;

    for (final d in _bondedDevices) {
      final name = d.name.toLowerCase().trim();
      int score = 999;
      if (name == 'hc-05') {
        score = 1;
      } else if (name == 'hc05') {
        score = 2;
      } else if (name.contains('hc-05')) {
        score = 3;
      } else if (name.contains('hc05')) {
        score = 4;
      } else if (name.contains('stove')) {
        score = 5;
      } else if (name.contains('sensor')) {
        score = 6;
      }

      if (score < 999) {
        if (score < bestScore) {
          bestScore = score;
          candidates = [d];
        } else if (score == bestScore) {
          candidates.add(d);
        }
      }
    }

    if (candidates.isEmpty) {
      debugPrint(
        '[SafeCook BT]\n'
        'eventId=$eventId\n'
        'recognized="connect sensor"\n'
        'intent=connectBluetooth\n'
        'tool=connectBluetooth\n'
        'nativeOperationStarted=false\n'
        'pairedDeviceFound=false\n'
        'actualConnected=false\n'
        'failureStage=no_matching_device',
      );
      return const ToolResult.fail(
        "I couldn't find the paired HC-05 stove sensor. Please make sure HC-05 is paired and powered on.",
      );
    }

    if (candidates.length > 1) {
      // Prefer exact "HC-05"
      final exactMatchList = candidates
          .where((d) => d.name.toLowerCase().trim() == 'hc-05')
          .toList();
      if (exactMatchList.length == 1) {
        targetDevice = exactMatchList.first;
      } else {
        debugPrint(
          '[SafeCook BT]\n'
          'eventId=$eventId\n'
          'recognized="connect sensor"\n'
          'intent=connectBluetooth\n'
          'tool=connectBluetooth\n'
          'nativeOperationStarted=false\n'
          'pairedDeviceFound=true\n'
          'actualConnected=false\n'
          'failureStage=ambiguous_matches',
        );
        return const ToolResult.fail(
          "Multiple matching stove sensors found. Please select or identify the stove sensor manually.",
        );
      }
    } else {
      targetDevice = candidates.first;
    }

    final matchedDevice = targetDevice;

    if (BluetoothTestPage.isTesting) {
      // Bypass native socket connection during automated tests
      setState(() {
        _connectedDevice = matchedDevice;
        _connectionStatus = 'Connected';
      });
      debugPrint(
        '[SafeCook BT]\n'
        'eventId=$eventId\n'
        'recognized="connect sensor"\n'
        'intent=connectBluetooth\n'
        'tool=connectBluetooth\n'
        'nativeOperationStarted=true\n'
        'targetDevice=${matchedDevice.name}\n'
        'targetAddress=${matchedDevice.address}\n'
        'pairedDeviceFound=true\n'
        'actualConnected=true',
      );
      return const ToolResult.ok('Connected to stove sensor');
    }

    try {
      _connectionCompleter = Completer<bool>();
      await _connectToDevice(matchedDevice);

      debugPrint(
        '[SafeCook BT]\n'
        'eventId=$eventId\n'
        'recognized="connect sensor"\n'
        'intent=connectBluetooth\n'
        'tool=connectBluetooth\n'
        'nativeOperationStarted=true\n'
        'targetDevice=${matchedDevice.name}\n'
        'targetAddress=${matchedDevice.address}\n'
        'pairedDeviceFound=true\n'
        'nativeMethod=connect',
      );

      final success = await _connectionCompleter!.future.timeout(
        const Duration(
          seconds: 10,
        ), // allow time for connection, discovery, and notification enable
        onTimeout: () => false,
      );
      _connectionCompleter = null;

      debugPrint(
        '[SafeCook BT]\n'
        'eventId=$eventId\n'
        'recognized="connect sensor"\n'
        'intent=connectBluetooth\n'
        'tool=connectBluetooth\n'
        'nativeOperationStarted=true\n'
        'targetDevice=${matchedDevice.name}\n'
        'targetAddress=${matchedDevice.address}\n'
        'pairedDeviceFound=true\n'
        'connectionEvent=${success ? "success" : "failed"}\n'
        'actualConnected=$success',
      );

      if (success) {
        return const ToolResult.ok('Connected to stove sensor');
      } else {
        return const ToolResult.fail(
          'Could not establish connection to the stove sensor.',
        );
      }
    } catch (e) {
      _connectionCompleter = null;
      debugPrint(
        '[SafeCook BT]\n'
        'eventId=$eventId\n'
        'recognized="connect sensor"\n'
        'intent=connectBluetooth\n'
        'tool=connectBluetooth\n'
        'nativeOperationStarted=true\n'
        'targetDevice=${matchedDevice.name}\n'
        'targetAddress=${matchedDevice.address}\n'
        'pairedDeviceFound=true\n'
        'connectionEvent=error\n'
        'actualConnected=false\n'
        'failureStage=exception',
      );
      return ToolResult.fail('Connection error: $e');
    }
  }

  Future<ToolResult> disconnectBluetoothFromVoice() async {
    if (_connectedDevice == null) {
      return const ToolResult.fail('Not connected');
    }
    try {
      await _disconnect();
      return const ToolResult.ok('Disconnected');
    } catch (e) {
      return ToolResult.fail('Error disconnecting: $e');
    }
  }

  ToolResult bluetoothStatusResult() {
    if (_connectedDevice != null) {
      return ToolResult.ok('Connected to ${_connectedDeviceName ?? "HC-05"}');
    }
    return const ToolResult.fail('Not connected');
  }

  // Sensor Parsing State Variables
  int? _gasValue;
  String? _distanceValue;
  String _gasStatus = 'Unknown';
  String _distanceStatus = 'Unknown';
  String _incomingAccumulator = '';
  final List<SafetyEvent> _safetyHistory = [];
  final List<SensorDataPoint> _gasChartData = [];
  final List<SensorDataPoint> _distChartData = [];

  // Cooking Session State Variables
  bool get _isCookingActive => SafeCookAgent().memory.isCookingActive;
  set _isCookingActive(bool val) =>
      SafeCookAgent().memory.isCookingActive = val;
  bool _showSessionSummary = false;
  Timer? _sessionTimer;
  Duration _sessionDuration = Duration.zero;
  int? _sessionMaxGas;
  double? _sessionMinDistance;
  int _sessionCautionCount = 0;
  int _sessionGasAlertCount = 0;
  int _sessionDistanceAlertCount = 0;
  int _sessionCriticalCount = 0;
  String _sessionFinalSafetyState = 'STANDBY';
  final List<SafetyEvent> _sessionSafetyHistory = [];

  Duration get sessionDuration => _sessionDuration;
  int? get sessionMaxGas => _sessionMaxGas;
  double? get sessionMinDistance => _sessionMinDistance;
  int get sessionCautionCount => _sessionCautionCount;
  int get sessionGasAlertCount => _sessionGasAlertCount;
  int get sessionDistanceAlertCount => _sessionDistanceAlertCount;
  int get sessionCriticalCount => _sessionCriticalCount;
  String get sessionFinalState => _sessionFinalSafetyState;
  List<SafetyEvent> get sessionSafetyHistory => _sessionSafetyHistory;

  // Voice Assistant variables for Home Screen
  String _assistantState = 'idle'; // 'idle', 'listening', 'processing'
  String _userSpokenText = '';
  String _assistantReplyText = '';
  int _consecutiveSilenceTurns = 0;
  final VoiceConversationMode _voiceConversation = VoiceConversationMode();
  bool _voiceListenStarting = false;
  final SpeechService _speechService = SpeechService();
  final VoiceAssistantService _assistantService = VoiceAssistantService();
  final VoiceService _voiceService = VoiceService();

  // Custom colors for status UI
  static const Color _greenAccent = Color(0xFF10B981);
  static const Color _greenBg = Color(0x2610B981); // 15% opacity
  static const Color _greenBorder = Color(0x8010B981); // 50% opacity

  static const Color _redAccent = Color(0xFFEF4444);
  static const Color _redBg = Color(0x26EF4444); // 15% opacity
  static const Color _redBorder = Color(0x80EF4444); // 50% opacity

  static const Color _amberAccent = Color(0xFFF59E0B);
  static const Color _amberBg = Color(0x26F59E0B); // 15% opacity
  static const Color _amberBorder = Color(0x80F59E0B); // 50% opacity

  Color _gasStatusColor = Colors.white54;
  Color _distanceStatusColor = Colors.white54;

  @override
  void initState() {
    super.initState();
    _resetDashboard();

    SafetyVoiceController().registerHomeScreen(this);
    _safetySubscription = SafeCookSafetyEngine().onSafetyEvent.listen((event) {
      if (mounted) {
        setState(() {
          final newEvent = SafetyEvent(
            timestamp: event.timestamp,
            state: _mapStateToString(event.currentState),
            gasValue: _gasValue,
            distanceValue: _distanceValue,
          );
          _safetyHistory.insert(0, newEvent);
          if (_safetyHistory.length > 50) {
            _safetyHistory.removeLast();
          }
          if (_isCookingActive) {
            _sessionSafetyHistory.add(newEvent);
            if (event.currentState == SafeCookSafetyState.caution) {
              _sessionCautionCount++;
            }
            if (event.currentState == SafeCookSafetyState.gasAlert) {
              _sessionGasAlertCount++;
            }
            if (event.currentState == SafeCookSafetyState.distanceAlert) {
              _sessionDistanceAlertCount++;
            }
            if (event.currentState == SafeCookSafetyState.critical) {
              _sessionCriticalCount++;
            }
          }
        });

        final stateStr = _mapStateToString(event.currentState);
        if (event.currentState != SafeCookSafetyState.safe &&
            event.currentState != SafeCookSafetyState.sensorUnavailable) {
          _triggerVibrationAndSound(stateStr);
        }
      }
    });

    if (!BluetoothTestPage.isTesting) {
      _initBluetooth();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _voiceService.speak(
          "Welcome to SafeCook. Say Hello SafeCook when you're ready.",
        );
        _startWakeWordDetection();
      });
    }
  }

  String _mapStateToString(SafeCookSafetyState state) {
    switch (state) {
      case SafeCookSafetyState.safe:
        return 'SAFE';
      case SafeCookSafetyState.caution:
        return 'CAUTION';
      case SafeCookSafetyState.distanceAlert:
        return 'DISTANCE ALERT';
      case SafeCookSafetyState.gasAlert:
        return 'GAS ALERT';
      case SafeCookSafetyState.critical:
        return 'CRITICAL';
      case SafeCookSafetyState.sensorUnavailable:
        return 'STANDBY';
    }
  }

  @override
  void handleSafetyVoiceEvent(SafeCookSafetyEvent event) {
    if (!mounted) return;
    if (!_isCookingActive) {
      final text = event.currentState.voiceMessage;
      _voiceService.speak(text);
    }
  }

  void _resetDashboard() {
    SafeCookSafetyEngine().reset();
    _gasValue = null;
    _distanceValue = null;
    _gasStatus = 'Unknown';
    _distanceStatus = 'Unknown';
    _gasStatusColor = Colors.white54;
    _distanceStatusColor = Colors.white54;
    _incomingAccumulator = '';
    _gasChartData.clear();
    _distChartData.clear();
    // Do NOT clear or reset session variables on Bluetooth reconnect,
    // only when a new cooking session starts.
  }

  String _getCombinedStatus() {
    return _mapStateToString(SafeCookSafetyEngine().currentState);
  }

  Color _getCombinedStatusColor() {
    final status = _getCombinedStatus();
    switch (status) {
      case 'CRITICAL':
      case 'GAS ALERT':
      case 'DISTANCE ALERT':
        return _redAccent;
      case 'CAUTION':
        return _amberAccent;
      case 'SAFE':
        return _greenAccent;
      default:
        return Colors.white38;
    }
  }

  Color _getCombinedStatusBgColor() {
    final status = _getCombinedStatus();
    switch (status) {
      case 'CRITICAL':
      case 'GAS ALERT':
      case 'DISTANCE ALERT':
        return _redBg;
      case 'CAUTION':
        return _amberBg;
      case 'SAFE':
        return _greenBg;
      default:
        return Colors.white10;
    }
  }

  Color _getCombinedStatusBorderColor() {
    final status = _getCombinedStatus();
    switch (status) {
      case 'CRITICAL':
      case 'GAS ALERT':
      case 'DISTANCE ALERT':
        return _redBorder;
      case 'CAUTION':
        return _amberBorder;
      case 'SAFE':
        return _greenBorder;
      default:
        return Colors.white24;
    }
  }

  IconData _getCombinedStatusIcon() {
    final status = _getCombinedStatus();
    switch (status) {
      case 'CRITICAL':
        return Icons.gpp_bad;
      case 'GAS ALERT':
        return Icons.gas_meter;
      case 'DISTANCE ALERT':
        return Icons.warning_amber;
      case 'CAUTION':
        return Icons.shield;
      case 'SAFE':
        return Icons.verified_user;
      default:
        return Icons.security;
    }
  }

  Future<void> _triggerVibrationAndSound(String state) async {
    try {
      await SystemSound.play(SystemSoundType.alert);
      if (state == 'CRITICAL') {
        await HapticFeedback.vibrate();
        await Future.delayed(const Duration(milliseconds: 200));
        await HapticFeedback.vibrate();
        await Future.delayed(const Duration(milliseconds: 200));
        await HapticFeedback.vibrate();
      } else {
        await HapticFeedback.vibrate();
      }
    } catch (e) {
      _log("Error triggering alert cues: $e");
    }
  }

  String _getSafetyMessage(String state) {
    switch (state) {
      case 'GAS ALERT':
        return 'High gas level detected; check for possible gas leakage.';
      case 'DISTANCE ALERT':
        return 'Unsafe proximity detected.';
      case 'CRITICAL':
        return 'Both gas and distance conditions are unsafe.';
      case 'CAUTION':
        return 'Elevated risk detected.';
      default:
        return '';
    }
  }

  Widget _buildAlertBanner() {
    final status = _getCombinedStatus();
    if (status == 'SAFE' || status == 'STANDBY') {
      return const SizedBox.shrink();
    }

    final message = _getSafetyMessage(status);
    final color = _getCombinedStatusColor();
    final bgColor = _getCombinedStatusBgColor();
    final borderColor = _getCombinedStatusBorderColor();

    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(SafeCookRadius.sm),
          border: Border.all(color: borderColor, width: 1.0),
        ),
        child: Row(
          children: [
            Icon(
              status == 'CRITICAL'
                  ? Icons.gpp_bad_rounded
                  : Icons.warning_amber_rounded,
              color: color,
              size: 24,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'SAFETY ALERT: $status',
                    style: TextStyle(
                      fontFamily: 'Nunito',
                      color: color,
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    message,
                    style: const TextStyle(
                      fontFamily: 'Nunito',
                      color: SafeCookColors.textPrimary,
                      fontSize: 13,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _clearSafetyHistory() {
    setState(() {
      _safetyHistory.clear();
    });
  }

  String _formatTime(DateTime dt) {
    final hour = dt.hour.toString().padLeft(2, '0');
    final minute = dt.minute.toString().padLeft(2, '0');
    final second = dt.second.toString().padLeft(2, '0');
    return '$hour:$minute:$second';
  }

  Color _getHistoryStateColor(String state) {
    switch (state) {
      case 'CRITICAL':
      case 'GAS ALERT':
      case 'DISTANCE ALERT':
        return _redAccent;
      case 'CAUTION':
        return _amberAccent;
      case 'SAFE':
        return _greenAccent;
      default:
        return Colors.white54;
    }
  }

  Color _getHistoryStateBgColor(String state) {
    switch (state) {
      case 'CRITICAL':
      case 'GAS ALERT':
      case 'DISTANCE ALERT':
        return _redBg;
      case 'CAUTION':
        return _amberBg;
      case 'SAFE':
        return _greenBg;
      default:
        return Colors.white10;
    }
  }

  Color _getHistoryStateBorderColor(String state) {
    switch (state) {
      case 'CRITICAL':
      case 'GAS ALERT':
      case 'DISTANCE ALERT':
        return _redBorder;
      case 'CAUTION':
        return _amberBorder;
      case 'SAFE':
        return _greenBorder;
      default:
        return Colors.white24;
    }
  }

  Widget _buildSafetyHistory() {
    return Padding(
      padding: const EdgeInsets.only(top: SafeCookSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'SAFETY EVENT HISTORY',
                style: SafeCookTextStyles.label,
              ),
              if (_safetyHistory.isNotEmpty)
                TextButton.icon(
                  onPressed: _clearSafetyHistory,
                  icon: const Icon(
                    Icons.clear_all_rounded,
                    size: 16,
                    color: SafeCookColors.textSecondary,
                  ),
                  label: const Text(
                    'Clear History',
                    style: TextStyle(
                      fontFamily: 'Nunito',
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: SafeCookColors.textSecondary,
                    ),
                  ),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          SCCard(
            padding: EdgeInsets.zero,
            child: _safetyHistory.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(24.0),
                    child: Center(
                      child: Text(
                        'No events logged yet.',
                        style: TextStyle(
                          fontFamily: 'Nunito',
                          color: SafeCookColors.textMuted,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  )
                : ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _safetyHistory.length,
                    separatorBuilder: (context, index) =>
                        const Divider(color: SafeCookColors.divider, height: 1),
                    itemBuilder: (context, index) {
                      final event = _safetyHistory[index];
                      final stateColor = _getHistoryStateColor(event.state);

                      return Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14.0,
                          vertical: 10.0,
                        ),
                        child: Row(
                          children: [
                            Text(
                              _formatTime(event.timestamp),
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 12,
                                color: SafeCookColors.textSecondary,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: _getHistoryStateBgColor(event.state),
                                border: Border.all(
                                  color: _getHistoryStateBorderColor(
                                    event.state,
                                  ),
                                ),
                                borderRadius: BorderRadius.circular(
                                  SafeCookRadius.xs,
                                ),
                              ),
                              child: Text(
                                event.state,
                                style: TextStyle(
                                  fontFamily: 'Nunito',
                                  color: stateColor,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.3,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'Gas: ${event.gasValue ?? '--'} | Dist: ${event.distanceValue ?? '--'}',
                                style: const TextStyle(
                                  fontFamily: 'Nunito',
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: SafeCookColors.textPrimary,
                                ),
                                textAlign: TextAlign.right,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  void _startCookingSession() {
    _sessionTimer?.cancel();
    setState(() {
      _isCookingActive = true;
      _showSessionSummary = false;
      _sessionDuration = Duration.zero;
      _sessionMaxGas = null;
      _sessionMinDistance = null;
      _sessionCautionCount = 0;
      _sessionGasAlertCount = 0;
      _sessionDistanceAlertCount = 0;
      _sessionCriticalCount = 0;
      _sessionFinalSafetyState = 'STANDBY';
      _sessionSafetyHistory.clear();
    });

    _sessionTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          _sessionDuration = Duration(seconds: timer.tick);
        });
      }
    });
  }

  void _endCookingSession() {
    _sessionTimer?.cancel();
    SafeCookAgent().endCookingSession();
    setState(() {
      _isCookingActive = false;
      _showSessionSummary = true;
      _sessionFinalSafetyState = _getCombinedStatus();
    });
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return '$minutes:$seconds';
  }

  Widget _buildCookingSessionControl() {
    return _buildSessionSummaryCard();
  }

  Widget _buildSummaryItem(String label, String value, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontFamily: 'Nunito',
              color: SafeCookColors.textSecondary,
              fontSize: 13,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontFamily: 'Nunito',
              color: color ?? SafeCookColors.textPrimary,
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  void _addGasChartData(double value) {
    setState(() {
      _gasChartData.add(
        SensorDataPoint(timestamp: DateTime.now(), value: value),
      );
      if (_gasChartData.length > 60) {
        _gasChartData.removeAt(0);
      }
    });
  }

  void _addDistChartData(double value) {
    setState(() {
      _distChartData.add(
        SensorDataPoint(timestamp: DateTime.now(), value: value),
      );
      if (_distChartData.length > 60) {
        _distChartData.removeAt(0);
      }
    });
  }

  Widget _buildLiveTrends() {
    return Padding(
      padding: const EdgeInsets.only(top: SafeCookSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'LIVE SENSOR TRENDS (LAST 60S)',
            style: SafeCookTextStyles.label,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: SCCard(
                  padding: const EdgeInsets.all(12.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Gas Trend (Raw)',
                        style: TextStyle(
                          fontFamily: 'Nunito',
                          color: SafeCookColors.textSecondary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        height: 80,
                        width: double.infinity,
                        child: _gasChartData.isEmpty
                            ? const Center(
                                child: Text(
                                  'No data yet',
                                  style: TextStyle(
                                    fontFamily: 'Nunito',
                                    color: SafeCookColors.textMuted,
                                    fontSize: 12,
                                  ),
                                ),
                              )
                            : CustomPaint(
                                painter: MiniLineChartPainter(
                                  data: _gasChartData,
                                  lineColor: SafeCookColors.primaryLight,
                                ),
                              ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: SCCard(
                  padding: const EdgeInsets.all(12.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Distance Trend (cm)',
                        style: TextStyle(
                          fontFamily: 'Nunito',
                          color: SafeCookColors.textSecondary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        height: 80,
                        width: double.infinity,
                        child: _distChartData.isEmpty
                            ? const Center(
                                child: Text(
                                  'No data yet',
                                  style: TextStyle(
                                    fontFamily: 'Nunito',
                                    color: SafeCookColors.textMuted,
                                    fontSize: 12,
                                  ),
                                ),
                              )
                            : CustomPaint(
                                painter: MiniLineChartPainter(
                                  data: _distChartData,
                                  lineColor: SafeCookColors.safe,
                                ),
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _log(String message) {
    debugPrint("[SafeCook Classic Debug] $message");
  }

  void _startEventChannelListener() {
    _eventChannelSub = _eventChannel.receiveBroadcastStream().listen(
      (data) {
        if (data is Map) {
          final event = data['event'] as String?;
          final value = data['value'];

          switch (event) {
            case 'status':
              final statusVal = value as String?;
              _log('[SafeCook BLE] status: $statusVal');
              if (statusVal == 'connecting') {
                setState(() {
                  _connectionStatus = 'Connecting...';
                  _isConnecting = true;
                });
              } else if (statusVal == 'connected') {
                setState(() {
                  _connectionStatus = 'Connected';
                  _isConnecting = false;
                  _connectedDevice = _bondedDevices.firstWhere(
                    (d) => d.address == _connectedDeviceAddress,
                    orElse: () => BluetoothDevice(
                      name: _connectedDeviceName ?? 'HC-05',
                      address: _connectedDeviceAddress ?? '',
                      bondState: 'bonded',
                    ),
                  );
                });
              } else if (statusVal == 'services_discovered') {
                setState(() {
                  _connectionStatus = 'Connected';
                });
              } else if (statusVal == 'notifications_enabled') {
                setState(() {
                  _connectionStatus = 'Connected';
                });
                if (_connectionCompleter != null &&
                    !_connectionCompleter!.isCompleted) {
                  _connectionCompleter!.complete(true);
                }
              } else if (statusVal == 'disconnected') {
                _handleDisconnect();
                if (_connectionCompleter != null &&
                    !_connectionCompleter!.isCompleted) {
                  _connectionCompleter!.complete(false);
                }
              }
              break;

            case 'read':
              final bytes = value as Uint8List?;
              if (bytes != null) {
                debugPrint('[SafeCook BLE] RX bytes: ${bytes.length}');

                final text = utf8.decode(bytes, allowMalformed: true);
                // Accumulate fragmented BLE packets without exposing raw serial
                // output in the normal home UI.
                if (mounted) {
                  _incomingAccumulator += text;
                  if (_incomingAccumulator.length > 4096) {
                    _incomingAccumulator = _incomingAccumulator.substring(
                      _incomingAccumulator.length - 1024,
                    );
                  }

                  while (_incomingAccumulator.contains('\n')) {
                    final index = _incomingAccumulator.indexOf('\n');
                    final line = _incomingAccumulator
                        .substring(0, index)
                        .trim();
                    _incomingAccumulator = _incomingAccumulator.substring(
                      index + 1,
                    );
                    if (line.isNotEmpty) {
                      _parseSensorData(line);
                    }
                  }
                }
              }
              break;

            case 'error':
              final errorMsg = value as String?;
              _log('[SafeCook BLE] Error: $errorMsg');
              if (_connectionCompleter != null &&
                  !_connectionCompleter!.isCompleted) {
                _connectionCompleter!.complete(false);
              }
              break;
          }
        }
      },
      onError: (err) {
        _log("[SafeCook Native BT] Stream error: $err");
      },
    );
  }

  Future<void> _initBluetooth() async {
    _log("Initializing native Bluetooth channels...");
    try {
      final isEnabled =
          await _methodChannel.invokeMethod<bool>('getBluetoothState') ?? false;
      if (mounted) {
        setState(() {
          _adapterState = isEnabled
              ? ClassicAdapterState.on
              : ClassicAdapterState.off;
        });
      }
      _startEventChannelListener();
    } catch (e) {
      _log("Error during Bluetooth initialization: $e");
    }

    // Fetch bonded list
    _getBondedDevices();
  }

  Future<void> _getBondedDevices() async {
    try {
      final isEnabled =
          await _methodChannel.invokeMethod<bool>('getBluetoothState') ?? false;
      _log("[SafeCook BT DEBUG] Bluetooth enabled: $isEnabled");

      final List? devicesList = await _methodChannel.invokeMethod<List>(
        'getBondedDevices',
      );
      final devices = (devicesList ?? [])
          .map((d) => BluetoothDevice.fromMap(d as Map))
          .toList();

      _log("[SafeCook BT DEBUG] getPairedDevices returned: ${devices.length}");

      for (var device in devices) {
        _log("[SafeCook BT DEBUG] name=${device.name}");
        _log("[SafeCook BT DEBUG] displayName=${device.name}");
        _log("[SafeCook BT DEBUG] address=${device.address}");
        _log("[SafeCook BT DEBUG] bondState=${device.bondState}");
      }

      if (mounted) {
        setState(() {
          _bondedDevices = devices;
        });
      }
    } catch (e) {
      _log("[SafeCook BT DEBUG] Error fetching paired devices: $e");
    }
  }

  void _startScan() {
    setState(() {
      _isScanning = true;
    });
    // Classic scanning/discovery is not utilized; we guide the user to system settings
    _showSnackBar("Please pair your HC-05 device in system settings first.");
    Timer(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() {
          _isScanning = false;
        });
      }
    });
  }

  void _stopScan() {
    setState(() {
      _isScanning = false;
    });
  }

  void _parseSensorData(String line) {
    try {
      // Expected formats:
      // GAS:263,DIST:78.50
      // GAS:263,DIST:NO_ECHO
      final regExp = RegExp(r'GAS:(\d+),DIST:(NO_ECHO|[\d\.]+)');
      final match = regExp.firstMatch(line);

      if (match != null) {
        _sensorFreshnessTimer?.cancel();
        _sensorFreshnessTimer = Timer(const Duration(seconds: 5), () {
          if (mounted) {
            SafeCookSafetyEngine().updateSensorData(
              gasPercentage: null,
              chefDistanceCm: null,
              isBluetoothConnected: _connectedDevice != null,
            );
            setState(() {
              _gasValue = null;
              _distanceValue = null;
              _gasStatus = 'Unknown';
              _distanceStatus = 'Unknown';
            });
            _notifySensorListeners();
          }
        });

        final gasStr = match.group(1);
        final distStr = match.group(2);

        bool hasChanges = false;

        if (gasStr != null) {
          final val = int.tryParse(gasStr);
          if (val != null) {
            if (_gasValue != val) {
              _gasValue = val;
              hasChanges = true;
            }
            if (val < kGasNormalMax) {
              if (_gasStatus != 'Normal') {
                _gasStatus = 'Normal';
                _gasStatusColor = _greenAccent;
                hasChanges = true;
              }
            } else if (val < kGasWarningMax) {
              if (_gasStatus != 'Warning') {
                _gasStatus = 'Warning';
                _gasStatusColor = _amberAccent;
                hasChanges = true;
              }
            } else {
              if (_gasStatus != 'Critical') {
                _gasStatus = 'Critical';
                _gasStatusColor = _redAccent;
                hasChanges = true;
              }
            }
            _addGasChartData(val.toDouble());
            if (_isCookingActive) {
              if (_sessionMaxGas == null || val > _sessionMaxGas!) {
                _sessionMaxGas = val;
              }
            }
          }
        }

        if (distStr != null) {
          if (distStr == 'NO_ECHO') {
            if (_distanceValue != 'No Echo') {
              _distanceValue = 'No Echo';
              _distanceStatus = 'No Echo';
              _distanceStatusColor = Colors.white54;
              hasChanges = true;
            }
          } else {
            final val = double.tryParse(distStr);
            if (val != null) {
              final formattedVal = '${val.toStringAsFixed(2)} cm';
              if (_distanceValue != formattedVal) {
                _distanceValue = formattedVal;
                hasChanges = true;
              }
              if (val > kDistanceSafeMin) {
                if (_distanceStatus != 'Safe') {
                  _distanceStatus = 'Safe';
                  _distanceStatusColor = _greenAccent;
                  hasChanges = true;
                }
              } else if (val >= kDistanceWarningMin) {
                if (_distanceStatus != 'Close') {
                  _distanceStatus = 'Close';
                  _distanceStatusColor = _amberAccent;
                  hasChanges = true;
                }
              } else {
                if (_distanceStatus != 'Very Close') {
                  _distanceStatus = 'Very Close';
                  _distanceStatusColor = _redAccent;
                  hasChanges = true;
                }
              }
              _addDistChartData(val);
              if (_isCookingActive) {
                if (_sessionMinDistance == null || val < _sessionMinDistance!) {
                  _sessionMinDistance = val;
                }
              }
            }
          }
        }

        final double? gasPercent = _gasValue != null
            ? GasCalibration.toPercent(_gasValue!)
            : null;
        final double? distanceCm = (distStr != null && distStr != 'NO_ECHO')
            ? double.tryParse(distStr)
            : null;

        final prevEngineState = SafeCookSafetyEngine().currentState;
        SafeCookSafetyEngine().updateSensorData(
          gasPercentage: gasPercent,
          chefDistanceCm: distanceCm,
          isBluetoothConnected: _connectedDevice != null,
        );
        if (SafeCookSafetyEngine().currentState != prevEngineState) {
          hasChanges = true;
        }

        if (hasChanges && mounted) {
          setState(() {});
        }
        _notifySensorListeners();
      }
    } catch (e) {
      debugPrint("Parsing error: $e");
    }
  }

  @visibleForTesting
  void simulateSensorData(String line) {
    _parseSensorData(line);
  }

  Future<void> _connectToDevice(BluetoothDevice device) async {
    if (_isConnecting) {
      _log(
        "Connection attempt ignored: another connection is already in progress.",
      );
      return;
    }

    _stopScan();

    setState(() {
      _isConnecting = true;
      _connectionStatus = 'Connecting...';
      _connectedDeviceAddress = device.address;
      _connectedDeviceName = device.name;
      _resetDashboard();
    });

    _log("[SafeCook Native BT]");
    _log("Connecting to HC-05");

    try {
      await _disconnect();
      await _methodChannel.invokeMethod('connect', {'address': device.address});
    } catch (e) {
      _log("[SafeCook Native BT] Connection error: $e");
      if (mounted) {
        setState(() {
          _isConnecting = false;
          _connectionStatus = 'Failed';
          _connectedDevice = null;
          _resetDashboard();
        });
      }
    }
  }

  void _handleDisconnect() {
    if (mounted) {
      _sensorFreshnessTimer?.cancel();
      // Reset Safety Engine on disconnect
      SafeCookSafetyEngine().reset();

      // Keep an active cooking session alive while safety moves to standby.
      // The user can continue navigation or end the session explicitly after
      // reconnecting or acknowledging the unavailable sensor state.
      setState(() {
        _isConnecting = false;
        _connectedDevice = null;
        _connectionStatus = 'Disconnected';
        _resetDashboard();
      });
      _notifySensorListeners();
    }
  }

  Future<void> _disconnect() async {
    _log('Closing BLE GATT connection...');
    try {
      await _methodChannel.invokeMethod('disconnect');
    } catch (e) {
      debugPrint("Error closing connection: $e");
    }

    if (mounted) {
      setState(() {
        _isConnecting = false;
        _connectedDevice = null;
        _connectionStatus = 'Disconnected';
        _resetDashboard();
      });
      _notifySensorListeners();
    }
  }

  void _showSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  void dispose() {
    SafetyVoiceController().unregisterHomeScreen(this);
    _safetySubscription?.cancel();
    _sensorFreshnessTimer?.cancel();
    _eventChannelSub?.cancel();
    _sessionTimer?.cancel();
    _voiceService.stop();
    _speechService.stopListening();
    super.dispose();
  }

  final WakeWordService _wakeWordService = WakeWordService();

  Future<void> _startWakeWordDetection() async {
    _voiceConversation.deactivate();
    await _speechService.initialize();
    await _wakeWordService.startWakeWordDetection(
      onWakeDetected: () async {
        _voiceConversation.activate();
        if (mounted) {
          setState(() {
            _assistantState = 'processing';
            _assistantReplyText = 'Hello! What would you like to do?';
          });
        }

        _voiceService.setCompletionCallback(() {
          _voiceService.setCompletionCallback(null);
          _startVoiceCommandListening();
        });

        await _voiceService.speak("Hello! What would you like to do?");
      },
    );
  }

  Future<void> _startVoiceCommandListening() async {
    if (_voiceListenStarting || _speechService.isListening) return;
    _voiceListenStarting = true;
    if (mounted) {
      setState(() {
        _assistantState = 'listening';
        _userSpokenText = '';
      });
    }

    await _speechService.startListening(
      onResult: (text) {
        if (mounted) {
          setState(() {
            _userSpokenText = text;
          });
        }
      },
      onError: (err) async {
        _consecutiveSilenceTurns++;
        final maxSilence = _isCookingActive ? 3 : 1;
        if (_consecutiveSilenceTurns >= maxSilence) {
          _consecutiveSilenceTurns = 0;
          if (mounted) {
            setState(() {
              _assistantState = 'idle';
              _assistantReplyText =
                  "I'll wait here. Say Hello SafeCook when you need me.";
            });
          }
          await _voiceService.speak(
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
          final maxSilence = _isCookingActive ? 3 : 1;
          _consecutiveSilenceTurns++;
          if (_consecutiveSilenceTurns >= maxSilence) {
            _consecutiveSilenceTurns = 0;
            if (mounted) {
              setState(() {
                _assistantState = 'idle';
                _assistantReplyText =
                    "I'll wait here. Say Hello SafeCook when you need me.";
              });
            }
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

        _consecutiveSilenceTurns =
            0; // Reset silence turns on valid user speech

        if (mounted) {
          setState(() {
            _assistantState = 'processing';
          });
        }

        final eventId = DateTime.now().millisecondsSinceEpoch;
        debugPrint(
          '[SafeCook VOICE]\n'
          'eventId=$eventId\n'
          'recognized="$query"\n'
          'processingStarted=true',
        );

        final voiceContext = VoiceAssistantContext(
          gasValue: _gasValue,
          distanceValue: _distanceValue,
          safetyState: _getCombinedStatus(),
          sessionDuration: _sessionDuration,
          isBluetoothConnected: _connectedDevice != null,
        );

        final actions = VoiceAssistantActions(
          onNextStep: () async => const ToolResult.fail('Not in cooking mode'),
          onPreviousStep: () async =>
              const ToolResult.fail('Not in cooking mode'),
          onRepeatStep: () async =>
              const ToolResult.fail('Not in cooking mode'),
          onGoToStep: (_) async => const ToolResult.fail('Not in cooking mode'),
          onEndCooking: () async {
            _endCookingSession();
            return const ToolResult.ok('Session ended');
          },
          onStartCooking: (recipe) async {
            if (!mounted) return const ToolResult.fail('Widget not mounted');
            final selected = SafeCookAgent().selectedRecipe ?? recipe;
            _voiceConversation.deactivate();
            _wakeWordService.stopWakeWordDetection();
            _speechService.stopListening();
            _startCookingSession();
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => CookingGuidanceScreen(
                  recipe: selected,
                  homeState: this,
                  startSilently: true,
                ),
              ),
            ).then((_) {
              if (mounted) {
                _startWakeWordDetection();
                setState(() {});
              }
            });
            return const ToolResult.ok(
              'Navigation to cooking screen initiated',
            );
          },
          onConnectBluetooth: connectBluetoothFromVoice,
          onDisconnectBluetooth: disconnectBluetoothFromVoice,
          onBluetoothStatus: bluetoothStatusResult,
        );

        final exitConversation = _isVoiceExitPhrase(query);
        final reply = await _assistantService.processVoiceCommand(
          query,
          voiceContext,
          actions,
        );

        if (mounted) {
          setState(() {
            _assistantReplyText = reply;
          });
        }

        if (exitConversation) _voiceConversation.deactivate();

        _voiceService.setCompletionCallback(() {
          _voiceService.setCompletionCallback(null);
          if (!_voiceConversation.shouldListenAfterTts()) {
            if (mounted) {
              setState(() {
                _assistantState = 'idle';
              });
            }
            _startWakeWordDetection();
          } else if (_voiceConversation.shouldListenAfterTts() && mounted) {
            _startVoiceCommandListening();
          } else {
            if (mounted) {
              setState(() {
                _assistantState = 'idle';
              });
            }
            _startWakeWordDetection();
          }
        });

        await _voiceService.speak(reply);
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
    _voiceConversation.activate();
    await _wakeWordService.stopWakeWordDetection();
    await _startVoiceCommandListening();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SafeCookColors.background,
      appBar: AppBar(
        titleSpacing: 16,
        backgroundColor: SafeCookColors.background,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: SafeCookColors.safe.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: SafeCookColors.safe.withValues(alpha: 0.3),
                  width: 1,
                ),
              ),
              child: const Icon(
                Icons.shield_rounded,
                color: SafeCookColors.safe,
                size: 18,
              ),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: const [
                Text(
                  'SafeCook',
                  style: TextStyle(
                    fontFamily: 'Nunito',
                    fontWeight: FontWeight.w900,
                    fontSize: 19,
                    letterSpacing: 0.2,
                    color: SafeCookColors.textPrimary,
                  ),
                ),
                Text(
                  'SMART COOKING SAFETY',
                  style: TextStyle(
                    fontFamily: 'Nunito',
                    fontWeight: FontWeight.w700,
                    fontSize: 9,
                    letterSpacing: 0.8,
                    color: SafeCookColors.primaryLight,
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.auto_awesome_motion),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const MemoryScreen()),
              );
            },
            tooltip: 'Open SafeCook memory',
          ),
          if (!_showPaired)
            IconButton(
              icon: Icon(_isScanning ? Icons.stop : Icons.search),
              onPressed: _isScanning ? _stopScan : _startScan,
              tooltip: _isScanning ? 'Stop Scan' : 'Scan for Devices',
            )
          else
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _getBondedDevices,
              tooltip: 'Refresh Paired List',
            ),
        ],
      ),
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onDoubleTap: () {
          if (_assistantState == 'listening') {
            _speechService.stopListening();
          } else {
            _startVoiceListening();
          }
        },
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildAlertBanner(),
              _buildWelcomeSection(),
              _buildPrimaryCookingCard(),
              _buildCookingSessionControl(),
              _buildKitchenSafetyCard(),
              _buildQuickActions(),
              _buildRecentCookingSection(),
              _buildSubordinatePreferences(),
              _buildSubordinateSensorSettings(),
              _buildDiagnosticsSection(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWelcomeSection() {
    final isConnected = _connectedDevice != null;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text(
                  'Welcome, Chef',
                  style: TextStyle(
                    fontFamily: 'Nunito',
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: SafeCookColors.textPrimary,
                    letterSpacing: -0.3,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Voice guidance & safety monitoring active',
                  style: TextStyle(
                    fontFamily: 'Nunito',
                    fontSize: 13,
                    color: SafeCookColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: isConnected
                  ? SafeCookColors.safeBg
                  : SafeCookColors.surfaceElevated,
              borderRadius: BorderRadius.circular(SafeCookRadius.full),
              border: Border.all(
                color: isConnected
                    ? SafeCookColors.safeBorder
                    : SafeCookColors.border,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isConnected
                      ? Icons.sensors_rounded
                      : Icons.sensors_off_rounded,
                  size: 13,
                  color: isConnected
                      ? SafeCookColors.safe
                      : SafeCookColors.textSecondary,
                ),
                const SizedBox(width: 5),
                Text(
                  isConnected ? 'Sensor Linked' : 'Sensor Offline',
                  style: TextStyle(
                    fontFamily: 'Nunito',
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: isConnected
                        ? SafeCookColors.safe
                        : SafeCookColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPrimaryCookingCard() {
    final isListening = _assistantState == 'listening';
    final isProcessing = _assistantState == 'processing';

    final Color statusColor = isListening
        ? SafeCookColors.danger
        : isProcessing
        ? SafeCookColors.primaryLight
        : SafeCookColors.safe;

    final String statusLabel = isListening
        ? 'Listening… Speak now'
        : isProcessing
        ? 'Understanding command…'
        : 'Say "Hello SafeCook" or tap to speak';

    final String formatDuration = _formatDuration(_sessionDuration);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 6.0),
      child: SCCard(
        borderRadius: SafeCookRadius.lg,
        borderColor: isListening
            ? SafeCookColors.dangerBorder
            : isProcessing
            ? SafeCookColors.primaryLight.withValues(alpha: 0.4)
            : SafeCookColors.border,
        padding: const EdgeInsets.all(18.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Voice status & interactive mic pill
            Semantics(
              button: true,
              label:
                  'Double tap anywhere to talk to SafeCook, or tap here to start voice assistant.',
              child: InkWell(
                onTap: () {
                  if (_assistantState == 'listening') {
                    _speechService.stopListening();
                  } else {
                    _startVoiceListening();
                  }
                },
                borderRadius: BorderRadius.circular(SafeCookRadius.md),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: isListening
                        ? SafeCookColors.dangerBg
                        : SafeCookColors.surfaceHighest,
                    borderRadius: BorderRadius.circular(SafeCookRadius.md),
                    border: Border.all(
                      color: isListening
                          ? SafeCookColors.dangerBorder
                          : SafeCookColors.border,
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: statusColor.withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          isListening
                              ? Icons.mic_rounded
                              : isProcessing
                              ? Icons.auto_fix_high_rounded
                              : Icons.mic_none_rounded,
                          color: statusColor,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              isListening
                                  ? 'LISTENING'
                                  : isProcessing
                                  ? 'PROCESSING'
                                  : 'VOICE ASSISTANT',
                              style: TextStyle(
                                fontFamily: 'Nunito',
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.8,
                                color: statusColor,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              statusLabel,
                              style: const TextStyle(
                                fontFamily: 'Nunito',
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: SafeCookColors.textPrimary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      if (isListening || isProcessing)
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: statusColor,
                            shape: BoxShape.circle,
                          ),
                        )
                      else
                        const Icon(
                          Icons.chevron_right_rounded,
                          color: SafeCookColors.textSecondary,
                          size: 18,
                        ),
                    ],
                  ),
                ),
              ),
            ),

            if (_userSpokenText.isNotEmpty) ...[
              const SizedBox(height: 10),
              ConversationLine(speaker: 'YOU', text: _userSpokenText),
            ],
            if (_assistantReplyText.isNotEmpty) ...[
              const SizedBox(height: 6),
              ConversationLine(speaker: 'SAFECOOK', text: _assistantReplyText),
            ],

            const SizedBox(height: 16),
            const Divider(color: SafeCookColors.divider, height: 1),
            const SizedBox(height: 16),

            // Active session timer if cooking is currently active
            if (_isCookingActive) ...[
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: SafeCookColors.primaryContainer,
                  borderRadius: BorderRadius.circular(SafeCookRadius.sm),
                  border: Border.all(
                    color: SafeCookColors.primaryLight.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: const [
                        Icon(
                          Icons.soup_kitchen_rounded,
                          color: SafeCookColors.primaryLight,
                          size: 18,
                        ),
                        SizedBox(width: 8),
                        Text(
                          'Cooking in progress',
                          style: TextStyle(
                            fontFamily: 'Nunito',
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: SafeCookColors.primaryLight,
                          ),
                        ),
                      ],
                    ),
                    Text(
                      formatDuration,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: SafeCookColors.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // Primary Start Cooking Button
            Semantics(
              button: true,
              label: 'Start cooking, touch route list',
              child: ElevatedButton.icon(
                onPressed: () async {
                  final selectedRecipe = await Navigator.push<Recipe>(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const RecipeListScreen(),
                    ),
                  );

                  if (selectedRecipe != null && mounted) {
                    _startCookingSession();
                    if (!context.mounted) return;
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => CookingGuidanceScreen(
                          recipe: selectedRecipe,
                          homeState: this,
                        ),
                      ),
                    );
                    if (mounted) {
                      setState(() {});
                    }
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: SafeCookColors.safe,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 52),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(SafeCookRadius.sm),
                  ),
                  elevation: 2,
                ),
                icon: const Icon(Icons.restaurant_menu_rounded, size: 22),
                label: Text(
                  _isCookingActive ? 'CHOOSE ANOTHER RECIPE' : 'START COOKING',
                  style: const TextStyle(
                    fontFamily: 'Nunito',
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ),

            if (_isCookingActive) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _endCookingSession,
                style: OutlinedButton.styleFrom(
                  foregroundColor: SafeCookColors.danger,
                  side: const BorderSide(color: SafeCookColors.dangerBorder),
                  minimumSize: const Size(double.infinity, 44),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(SafeCookRadius.sm),
                  ),
                ),
                icon: const Icon(Icons.stop_circle_outlined, size: 20),
                label: const Text(
                  'END ACTIVE SESSION',
                  style: TextStyle(
                    fontFamily: 'Nunito',
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSessionSummaryCard() {
    if (!_showSessionSummary) return const SizedBox.shrink();
    final formatDuration = _formatDuration(_sessionDuration);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 6.0),
      child: SCCard(
        borderRadius: SafeCookRadius.md,
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: const [
                Icon(
                  Icons.assessment_rounded,
                  color: SafeCookColors.primaryLight,
                  size: 20,
                ),
                SizedBox(width: 8),
                Text(
                  'COMPLETED SESSION SUMMARY',
                  style: SafeCookTextStyles.label,
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(color: SafeCookColors.divider, height: 1),
            const SizedBox(height: 10),
            _buildSummaryItem('Duration', formatDuration),
            _buildSummaryItem(
              'Maximum Gas',
              _sessionMaxGas != null ? '$_sessionMaxGas' : 'N/A',
            ),
            _buildSummaryItem(
              'Minimum Distance',
              _sessionMinDistance != null
                  ? '${_sessionMinDistance!.toStringAsFixed(2)} cm'
                  : 'N/A',
            ),
            _buildSummaryItem(
              'Total Alerts',
              '${_sessionCautionCount + _sessionGasAlertCount + _sessionDistanceAlertCount}',
            ),
            _buildSummaryItem('Critical Events', '$_sessionCriticalCount'),
            _buildSummaryItem(
              'Final Safety State',
              _sessionFinalSafetyState,
              color: _getHistoryStateColor(_sessionFinalSafetyState),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildKitchenSafetyCard() {
    final status = _getCombinedStatus();
    final isConnected = _connectedDevice != null;

    String explanation;
    switch (status) {
      case 'SAFE':
        explanation = "Cooking conditions look safe.";
        break;
      case 'CAUTION':
        explanation = "Please pay attention to the cooking area.";
        break;
      case 'GAS ALERT':
        explanation = "Gas level is high. Check cooking area.";
        break;
      case 'DISTANCE ALERT':
        explanation = "Vessel or chef proximity warning.";
        break;
      case 'CRITICAL':
        explanation = "Immediate hazard detected! Turn off heat.";
        break;
      default:
        explanation = "Sensor standby — monitoring offline.";
    }

    final gasPercent = _gasValue != null
        ? '${GasCalibration.toPercent(_gasValue!).toStringAsFixed(0)}%'
        : '--';
    final distanceDisplay = _distanceValue != null
        ? '$_distanceValue cm'
        : '--';
    final sensorDisplay = isConnected
        ? (_connectedDeviceName ?? 'HC-05')
        : 'Offline';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 6.0),
      child: SCCard(
        borderRadius: SafeCookRadius.lg,
        padding: const EdgeInsets.all(18.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header Row: Icon + State + Pill
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: _getCombinedStatusBgColor(),
                    shape: BoxShape.circle,
                    border: Border.all(color: _getCombinedStatusBorderColor()),
                  ),
                  child: Icon(
                    _getCombinedStatusIcon(),
                    color: _getCombinedStatusColor(),
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'KITCHEN SAFETY STATUS',
                        style: SafeCookTextStyles.label,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        status,
                        style: TextStyle(
                          fontFamily: 'Nunito',
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          color: _getCombinedStatusColor(),
                          letterSpacing: 0.2,
                        ),
                      ),
                      Text(
                        explanation,
                        style: const TextStyle(
                          fontFamily: 'Nunito',
                          fontSize: 12,
                          color: SafeCookColors.textSecondary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                SafetyStatusBadge(status: status),
              ],
            ),

            const SizedBox(height: 16),
            const Divider(color: SafeCookColors.divider, height: 1),
            const SizedBox(height: 14),

            // 3-Column Metrics Row
            Row(
              children: [
                // Gas Level (No raw ADC value exposed)
                Expanded(
                  child: _buildMetricTile(
                    label: 'GAS LEVEL',
                    value: gasPercent,
                    statusText: _gasStatus,
                    statusColor: _gasStatusColor,
                    icon: Icons.gas_meter_rounded,
                  ),
                ),
                const SizedBox(width: 8),
                // Chef Distance
                Expanded(
                  child: _buildMetricTile(
                    label: 'DISTANCE',
                    value: distanceDisplay,
                    statusText: _distanceStatus,
                    statusColor: _distanceStatusColor,
                    icon: Icons.accessibility_new_rounded,
                  ),
                ),
                const SizedBox(width: 8),
                // Bluetooth / Sensor Link
                Expanded(
                  child: _buildMetricTile(
                    label: 'SENSOR LINK',
                    value: sensorDisplay,
                    statusText: isConnected ? 'Connected' : 'Offline',
                    statusColor: isConnected
                        ? SafeCookColors.safe
                        : SafeCookColors.textSecondary,
                    icon: Icons.bluetooth_rounded,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricTile({
    required String label,
    required String value,
    required String statusText,
    required Color statusColor,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      decoration: BoxDecoration(
        color: SafeCookColors.surfaceHighest,
        borderRadius: BorderRadius.circular(SafeCookRadius.sm),
        border: Border.all(color: SafeCookColors.border.withValues(alpha: 0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontFamily: 'Nunito',
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.6,
                  color: SafeCookColors.textSecondary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Icon(icon, size: 14, color: SafeCookColors.textSecondary),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              fontFamily: 'Nunito',
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: SafeCookColors.textPrimary,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: statusColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  statusText,
                  style: TextStyle(
                    fontFamily: 'Nunito',
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: statusColor,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActions() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SCSection(
            label: 'Quick Actions',
            padding: EdgeInsets.only(bottom: 8),
          ),
          Row(
            children: [
              // Cook action
              Expanded(
                child: _buildActionTile(
                  icon: Icons.outdoor_grill_rounded,
                  iconColor: SafeCookColors.safe,
                  iconBg: SafeCookColors.safeBg,
                  title: 'Cook',
                  subtitle: 'Start session',
                  onTap: () async {
                    final selectedRecipe = await Navigator.push<Recipe>(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const RecipeListScreen(),
                      ),
                    );
                    if (selectedRecipe != null && mounted) {
                      _startCookingSession();
                      if (!context.mounted) return;
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => CookingGuidanceScreen(
                            recipe: selectedRecipe,
                            homeState: this,
                          ),
                        ),
                      );
                      if (mounted) setState(() {});
                    }
                  },
                ),
              ),
              const SizedBox(width: 10),
              // Recipes action
              Expanded(
                child: _buildActionTile(
                  icon: Icons.menu_book_rounded,
                  iconColor: SafeCookColors.primaryLight,
                  iconBg: SafeCookColors.primaryContainer,
                  title: 'Recipes',
                  subtitle: 'Explore dishes',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const RecipeListScreen(),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(width: 10),
              // Memory action
              Expanded(
                child: _buildActionTile(
                  icon: Icons.psychology_rounded,
                  iconColor: const Color(0xFFA78BFA),
                  iconBg: const Color(0x26A78BFA),
                  title: 'Memory',
                  subtitle: 'Safety notes',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const MemoryScreen(),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActionTile({
    required IconData icon,
    required Color iconColor,
    required Color iconBg,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return SCCard(
      borderRadius: SafeCookRadius.md,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: iconBg,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: iconColor, size: 20),
          ),
          const SizedBox(height: 10),
          Text(
            title,
            style: const TextStyle(
              fontFamily: 'Nunito',
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: SafeCookColors.textPrimary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: const TextStyle(
              fontFamily: 'Nunito',
              fontSize: 11,
              color: SafeCookColors.textSecondary,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildRecentCookingSection() {
    final lastCookedId = PreferenceService().getLastCookedRecipeId();
    final allRecipes = [
      ...kPredefinedRecipes,
      ...PreferenceService().getDynamicRecipes(),
    ];
    Recipe? lastCookedRecipe;
    if (lastCookedId != null) {
      try {
        lastCookedRecipe = allRecipes.firstWhere((r) => r.id == lastCookedId);
      } catch (_) {
        lastCookedRecipe = null;
      }
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 6.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SCSection(
            label: 'Recent Cooking',
            padding: EdgeInsets.only(bottom: 8),
          ),
          if (lastCookedRecipe != null)
            SCCard(
              borderRadius: SafeCookRadius.md,
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: SafeCookColors.primaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.restaurant_rounded,
                      color: SafeCookColors.primaryLight,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'CONTINUE COOKING',
                          style: TextStyle(
                            fontFamily: 'Nunito',
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.8,
                            color: SafeCookColors.primaryLight,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          lastCookedRecipe.name,
                          style: const TextStyle(
                            fontFamily: 'Nunito',
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: SafeCookColors.textPrimary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${lastCookedRecipe.cookingTime} mins • ${lastCookedRecipe.difficulty} • ${lastCookedRecipe.category}',
                          style: const TextStyle(
                            fontFamily: 'Nunito',
                            fontSize: 12,
                            color: SafeCookColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () async {
                      _startCookingSession();
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => CookingGuidanceScreen(
                            recipe: lastCookedRecipe!,
                            homeState: this,
                          ),
                        ),
                      );
                      if (mounted) setState(() {});
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: SafeCookColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: const Text(
                      'COOK AGAIN',
                      style: TextStyle(
                        fontFamily: 'Nunito',
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
            )
          else
            SCCard(
              borderRadius: SafeCookRadius.md,
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: SafeCookColors.surfaceHighest,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.history_rounded,
                      color: SafeCookColors.textMuted,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'No recent cooking sessions',
                          style: TextStyle(
                            fontFamily: 'Nunito',
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: SafeCookColors.textSecondary,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Start your first recipe with voice guidance.',
                          style: TextStyle(
                            fontFamily: 'Nunito',
                            fontSize: 11,
                            color: SafeCookColors.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const RecipeListScreen(),
                        ),
                      );
                    },
                    child: const Text(
                      'Browse',
                      style: TextStyle(
                        fontFamily: 'Nunito',
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: SafeCookColors.primaryLight,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSubordinatePreferences() {
    final isVeg = PreferenceService().isVegetarian();
    final preferredCuisine = PreferenceService().getPreferredCuisine();
    final preferredServings = PreferenceService().getPreferredServings();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 6.0),
      child: SCCard(
        borderRadius: SafeCookRadius.md,
        padding: const EdgeInsets.all(14.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              onTap: () {
                setState(() {
                  _showPreferences = !_showPreferences;
                });
              },
              borderRadius: BorderRadius.circular(SafeCookRadius.sm),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: SafeCookColors.surfaceHighest,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.tune_rounded,
                      color: SafeCookColors.primaryLight,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'USER PREFERENCES',
                          style: SafeCookTextStyles.label,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${isVeg ? 'Vegetarian' : 'All diets'} • $preferredCuisine • $preferredServings servings',
                          style: const TextStyle(
                            fontFamily: 'Nunito',
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: SafeCookColors.textPrimary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    _showPreferences
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    color: SafeCookColors.textSecondary,
                  ),
                ],
              ),
            ),
            if (_showPreferences) ...[
              const SizedBox(height: 12),
              const Divider(color: SafeCookColors.divider, height: 1),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  'Vegetarian Mode Only',
                  style: TextStyle(
                    fontFamily: 'Nunito',
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: SafeCookColors.textPrimary,
                  ),
                ),
                value: isVeg,
                activeThumbColor: SafeCookColors.safe,
                onChanged: (val) async {
                  await PreferenceService().setVegetarian(val);
                  setState(() {});
                },
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: preferredCuisine,
                decoration: InputDecoration(
                  labelText: 'Preferred cuisine',
                  labelStyle: const TextStyle(
                    fontFamily: 'Nunito',
                    color: SafeCookColors.textSecondary,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(SafeCookRadius.sm),
                    borderSide: const BorderSide(color: SafeCookColors.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(SafeCookRadius.sm),
                    borderSide: const BorderSide(color: SafeCookColors.border),
                  ),
                ),
                dropdownColor: SafeCookColors.surfaceElevated,
                items:
                    const [
                          'Any',
                          'Indian',
                          'Mediterranean',
                          'Italian',
                          'East Asian',
                        ]
                        .map(
                          (cuisine) => DropdownMenuItem(
                            value: cuisine,
                            child: Text(
                              cuisine,
                              style: const TextStyle(fontFamily: 'Nunito'),
                            ),
                          ),
                        )
                        .toList(),
                onChanged: (cuisine) async {
                  if (cuisine == null) return;
                  await PreferenceService().setPreferredCuisine(cuisine);
                  if (mounted) setState(() {});
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                initialValue: preferredServings,
                decoration: InputDecoration(
                  labelText: 'Preferred servings',
                  labelStyle: const TextStyle(
                    fontFamily: 'Nunito',
                    color: SafeCookColors.textSecondary,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(SafeCookRadius.sm),
                    borderSide: const BorderSide(color: SafeCookColors.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(SafeCookRadius.sm),
                    borderSide: const BorderSide(color: SafeCookColors.border),
                  ),
                ),
                dropdownColor: SafeCookColors.surfaceElevated,
                items: [1, 2, 3, 4, 5, 6, 8, 10, 12]
                    .map(
                      (servings) => DropdownMenuItem(
                        value: servings,
                        child: Text(
                          '$servings',
                          style: const TextStyle(fontFamily: 'Nunito'),
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (servings) async {
                  if (servings == null) return;
                  await PreferenceService().setPreferredServings(servings);
                  if (mounted) setState(() {});
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSubordinateSensorSettings() {
    final isConnected = _connectedDevice != null;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 6.0),
      child: SCCard(
        borderRadius: SafeCookRadius.md,
        padding: const EdgeInsets.all(14.0),
        child: Column(
          children: [
            InkWell(
              onTap: () {
                setState(() {
                  _showBluetoothSettings = !_showBluetoothSettings;
                });
                if (_showBluetoothSettings) {
                  _getBondedDevices();
                }
              },
              borderRadius: BorderRadius.circular(SafeCookRadius.sm),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: isConnected
                          ? SafeCookColors.safeBg
                          : SafeCookColors.surfaceHighest,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      isConnected
                          ? Icons.bluetooth_connected_rounded
                          : Icons.settings_bluetooth_rounded,
                      color: isConnected
                          ? SafeCookColors.safe
                          : SafeCookColors.primaryLight,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'SENSOR CONNECTION',
                          style: SafeCookTextStyles.label,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          isConnected
                              ? '${_connectedDeviceName ?? 'HC-05'} (${_connectedDeviceAddress ?? 'Connected'})'
                              : 'Adapter: ${_adapterState.name.toUpperCase()} • Disconnected',
                          style: const TextStyle(
                            fontFamily: 'Nunito',
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: SafeCookColors.textPrimary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    _showBluetoothSettings
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    color: SafeCookColors.textSecondary,
                  ),
                ],
              ),
            ),
            if (_showBluetoothSettings) ...[
              const SizedBox(height: 12),
              const Divider(color: SafeCookColors.divider, height: 1),
              const SizedBox(height: 12),
              // Status indicators
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Bluetooth Adapter:',
                    style: TextStyle(
                      fontFamily: 'Nunito',
                      fontSize: 13,
                      color: SafeCookColors.textSecondary,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: _adapterState == ClassicAdapterState.on
                          ? SafeCookColors.safeBg
                          : SafeCookColors.dangerBg,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: _adapterState == ClassicAdapterState.on
                            ? SafeCookColors.safeBorder
                            : SafeCookColors.dangerBorder,
                      ),
                    ),
                    child: Text(
                      _adapterState.name.toUpperCase(),
                      style: TextStyle(
                        fontFamily: 'Nunito',
                        color: _adapterState == ClassicAdapterState.on
                            ? SafeCookColors.safe
                            : SafeCookColors.danger,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Connection Status:',
                    style: TextStyle(
                      fontFamily: 'Nunito',
                      fontSize: 13,
                      color: SafeCookColors.textSecondary,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color:
                          (_connectionStatus == 'Connected' ||
                              _connectionStatus == 'GATT Connected' ||
                              _connectionStatus == 'Receiving Data')
                          ? SafeCookColors.safeBg
                          : (_connectionStatus.startsWith('Connecting') ||
                                _connectionStatus == 'Services Discovered' ||
                                _connectionStatus == 'Notifications Enabled')
                          ? SafeCookColors.cautionBg
                          : SafeCookColors.dangerBg,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color:
                            (_connectionStatus == 'Connected' ||
                                _connectionStatus == 'GATT Connected' ||
                                _connectionStatus == 'Receiving Data')
                            ? SafeCookColors.safeBorder
                            : (_connectionStatus.startsWith('Connecting') ||
                                  _connectionStatus == 'Services Discovered' ||
                                  _connectionStatus == 'Notifications Enabled')
                            ? SafeCookColors.cautionBorder
                            : SafeCookColors.dangerBorder,
                      ),
                    ),
                    child: Text(
                      _connectionStatus,
                      style: TextStyle(
                        fontFamily: 'Nunito',
                        color:
                            (_connectionStatus == 'Connected' ||
                                _connectionStatus == 'GATT Connected' ||
                                _connectionStatus == 'Receiving Data')
                            ? SafeCookColors.safe
                            : (_connectionStatus.startsWith('Connecting') ||
                                  _connectionStatus == 'Services Discovered' ||
                                  _connectionStatus == 'Notifications Enabled')
                            ? SafeCookColors.caution
                            : SafeCookColors.danger,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
              if (isConnected) ...[
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _connectedDeviceName ?? 'HC-05',
                            style: const TextStyle(
                              fontFamily: 'Nunito',
                              fontWeight: FontWeight.w800,
                              fontSize: 14,
                              color: SafeCookColors.textPrimary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            _connectedDeviceAddress ?? '',
                            style: const TextStyle(
                              fontFamily: 'Nunito',
                              color: SafeCookColors.textSecondary,
                              fontSize: 11,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    ElevatedButton.icon(
                      onPressed: _disconnect,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: SafeCookColors.danger,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      icon: const Icon(Icons.link_off_rounded, size: 15),
                      label: const Text(
                        'Disconnect',
                        style: TextStyle(
                          fontFamily: 'Nunito',
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 12),
              const Divider(color: SafeCookColors.divider, height: 1),
              // Tabs for Paired and Scanned
              Row(
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: () {
                        setState(() {
                          _showPaired = true;
                        });
                        _getBondedDevices();
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          border: Border(
                            bottom: BorderSide(
                              color: _showPaired
                                  ? SafeCookColors.primaryLight
                                  : Colors.transparent,
                              width: 2,
                            ),
                          ),
                        ),
                        child: Center(
                          child: Text(
                            'PAIRED (${_bondedDevices.length})',
                            style: TextStyle(
                              fontFamily: 'Nunito',
                              fontSize: 12,
                              fontWeight: _showPaired
                                  ? FontWeight.w800
                                  : FontWeight.w600,
                              color: _showPaired
                                  ? SafeCookColors.primaryLight
                                  : SafeCookColors.textSecondary,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: InkWell(
                      onTap: () {
                        setState(() {
                          _showPaired = false;
                        });
                        _startScan();
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          border: Border(
                            bottom: BorderSide(
                              color: !_showPaired
                                  ? SafeCookColors.primaryLight
                                  : Colors.transparent,
                              width: 2,
                            ),
                          ),
                        ),
                        child: Center(
                          child: Text(
                            'SCANNED (${_discoveredDevices.length})',
                            style: TextStyle(
                              fontFamily: 'Nunito',
                              fontSize: 12,
                              fontWeight: !_showPaired
                                  ? FontWeight.w800
                                  : FontWeight.w600,
                              color: !_showPaired
                                  ? SafeCookColors.primaryLight
                                  : SafeCookColors.textSecondary,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const Divider(color: SafeCookColors.divider, height: 1),
              _showPaired ? _buildPairedList() : _buildScannedList(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDiagnosticsSection() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 6.0),
      child: SCCard(
        borderRadius: SafeCookRadius.md,
        padding: const EdgeInsets.all(14.0),
        child: Column(
          children: [
            InkWell(
              onTap: () {
                setState(() {
                  _showDiagnostics = !_showDiagnostics;
                });
              },
              borderRadius: BorderRadius.circular(SafeCookRadius.sm),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: SafeCookColors.surfaceHighest,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.analytics_rounded,
                      color: SafeCookColors.primaryLight,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'SENSOR TELEMETRY & LOGS',
                          style: SafeCookTextStyles.label,
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Live trends, real-time charts & event history',
                          style: TextStyle(
                            fontFamily: 'Nunito',
                            fontSize: 12,
                            color: SafeCookColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    _showDiagnostics
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    color: SafeCookColors.textSecondary,
                  ),
                ],
              ),
            ),
            if (_showDiagnostics) ...[
              const SizedBox(height: 12),
              const Divider(color: SafeCookColors.divider, height: 1),
              _buildLiveTrends(),
              _buildSafetyHistory(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPairedList() {
    if (_bondedDevices.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.bluetooth_disabled,
                size: 48,
                color: Colors.white24,
              ),
              const SizedBox(height: 12),
              const Text(
                'No paired devices found',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.white70,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Make sure the HC-05 is paired in your system settings, or switch to "Scanned Devices" to search for it.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: Colors.white38),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _getBondedDevices,
                icon: const Icon(Icons.refresh),
                label: const Text('Refresh Paired List'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1E293B),
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      itemCount: _bondedDevices.length,
      itemBuilder: (context, index) {
        final device = _bondedDevices[index];
        return _buildDeviceItem(device);
      },
    );
  }

  Widget _buildScannedList() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.bluetooth_searching,
              size: 48,
              color: Colors.white24,
            ),
            const SizedBox(height: 12),
            const Text(
              'BLE Mode',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.white70,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'HC-05 V2.3 LE is a BLE device. Use the Paired Devices tab to connect.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Colors.white38),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDeviceItem(BluetoothDevice device) {
    final isConnecting =
        _connectionStatus == 'Connecting...' &&
        _connectedDeviceAddress == device.address;
    final isConnected =
        _connectedDevice != null && _connectedDeviceAddress == device.address;

    return Card(
      color: const Color(0xFF1E293B),
      margin: const EdgeInsets.symmetric(vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: const CircleAvatar(
          backgroundColor: Color(0x260EA5E9), // 15% opacity
          child: Icon(Icons.bluetooth, color: Color(0xFF38BDF8)),
        ),
        title: Text(
          device.name,
          style: const TextStyle(fontWeight: FontWeight.bold),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Row(
          children: [
            Flexible(
              child: Text(
                device.address,
                style: const TextStyle(color: Colors.white54, fontSize: 12),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.white10,
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Text(
                'PAIRED',
                style: TextStyle(
                  fontSize: 9,
                  color: Colors.white70,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        trailing: isConnected
            ? const Icon(Icons.check_circle, color: _greenAccent)
            : isConnecting
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Color(0xFF38BDF8),
                ),
              )
            : ElevatedButton(
                onPressed: _isConnecting
                    ? null
                    : () => _connectToDevice(device),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0EA5E9),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: const Text(
                  'Connect',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ),
      ),
    );
  }
}

class SLocationSizeBox extends StatelessWidget {
  final String title;
  const SLocationSizeBox({super.key, required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: Colors.white70,
          letterSpacing: 1,
        ),
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}
