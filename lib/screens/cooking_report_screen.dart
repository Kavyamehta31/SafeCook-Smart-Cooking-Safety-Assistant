import 'package:flutter/material.dart';
import '../models/recipe.dart';
import '../main.dart'; // for SafetyEvent

class CookingReportScreen extends StatelessWidget {
  final Recipe recipe;
  final int stepsCompleted;
  final Duration duration;
  final int? maxGas;
  final double? minDistance;
  final int cautionCount;
  final int gasAlertCount;
  final int distanceAlertCount;
  final int criticalCount;
  final String finalState;
  final List<SafetyEvent> sessionEvents;

  const CookingReportScreen({
    super.key,
    required this.recipe,
    required this.stepsCompleted,
    required this.duration,
    required this.maxGas,
    required this.minDistance,
    required this.cautionCount,
    required this.gasAlertCount,
    required this.distanceAlertCount,
    required this.criticalCount,
    required this.finalState,
    required this.sessionEvents,
  });

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return '$minutes:$seconds';
  }

  String _getCookingResultText() {
    if (criticalCount > 0) {
      return 'Critical safety incident detected';
    } else if (cautionCount > 0 || gasAlertCount > 0 || distanceAlertCount > 0) {
      return 'Completed with warnings';
    } else {
      return 'Cooking completed safely';
    }
  }

  Color _getCookingResultColor() {
    if (criticalCount > 0) {
      return const Color(0xFFEF4444); // Red
    } else if (cautionCount > 0 || gasAlertCount > 0 || distanceAlertCount > 0) {
      return const Color(0xFFF59E0B); // Amber
    } else {
      return const Color(0xFF10B981); // Green
    }
  }

  Color _getCookingResultBgColor() {
    if (criticalCount > 0) {
      return const Color(0x1AEF4444); // Red 10%
    } else if (cautionCount > 0 || gasAlertCount > 0 || distanceAlertCount > 0) {
      return const Color(0x1AF59E0B); // Amber 10%
    } else {
      return const Color(0x1A10B981); // Green 10%
    }
  }

  Color _getCookingResultBorderColor() {
    if (criticalCount > 0) {
      return const Color(0x4DEF4444); // Red 30%
    } else if (cautionCount > 0 || gasAlertCount > 0 || distanceAlertCount > 0) {
      return const Color(0x4DF59E0B); // Amber 30%
    } else {
      return const Color(0x4D10B981); // Green 30%
    }
  }

  @override
  Widget build(BuildContext context) {
    final resultText = _getCookingResultText();
    final resultColor = _getCookingResultColor();
    final resultBgColor = _getCookingResultBgColor();
    final resultBorderColor = _getCookingResultBorderColor();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Cooking Report', style: TextStyle(fontWeight: FontWeight.bold)),
        automaticallyImplyLeading: false, // User should go back only via DONE button
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. Result Card
            Card(
              color: resultBgColor,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: resultBorderColor, width: 1.5),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  children: [
                    Icon(
                      criticalCount > 0
                          ? Icons.cancel_outlined
                          : (cautionCount > 0 || gasAlertCount > 0 || distanceAlertCount > 0)
                              ? Icons.warning_amber_rounded
                              : Icons.check_circle_outline,
                      color: resultColor,
                      size: 36,
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'COOKING RESULT',
                            style: TextStyle(fontSize: 10, color: Colors.white54, fontWeight: FontWeight.bold, letterSpacing: 1),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            resultText,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: resultColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 20),

            // 2. Recipe Info
            const Text(
              'RECIPE INFORMATION',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white70, letterSpacing: 1),
            ),
            const SizedBox(height: 8),
            Card(
              color: const Color(0xFF1E293B),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    _buildRowItem('Recipe Name', recipe.name),
                    _buildRowItem('Category', recipe.category),
                    _buildRowItem('Cooking Time', '${recipe.cookingTime} min (est)'),
                    _buildRowItem('Steps Completed', '$stepsCompleted / ${recipe.steps.length}'),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 20),

            // 3. Safety Stats
            const Text(
              'SAFETY & SENSOR SUMMARY',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white70, letterSpacing: 1),
            ),
            const SizedBox(height: 8),
            Card(
              color: const Color(0xFF1E293B),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    _buildRowItem('Final Safety Status', finalState, color: _getStateColor(finalState)),
                    _buildRowItem('Duration', _formatDuration(duration)),
                    _buildRowItem('Peak Gas Reading', maxGas != null ? '$maxGas' : 'N/A'),
                    _buildRowItem(
                      'Minimum Distance',
                      minDistance != null ? '${minDistance!.toStringAsFixed(2)} cm' : 'N/A (NO_ECHO)',
                    ),
                    const SizedBox(height: 8),
                    const Divider(color: Colors.white10, height: 1),
                    const SizedBox(height: 8),
                    _buildRowItem('Caution Events', '$cautionCount'),
                    _buildRowItem('Gas Alerts', '$gasAlertCount'),
                    _buildRowItem('Distance Alerts', '$distanceAlertCount'),
                    _buildRowItem('Critical Events', '$criticalCount'),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 20),

            // 4. Safety Event Log (this session)
            const Text(
              'SESSION SAFETY LOG',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white70, letterSpacing: 1),
            ),
            const SizedBox(height: 8),
            Card(
              color: const Color(0xFF1E293B),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: sessionEvents.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(16.0),
                      child: Center(
                        child: Text(
                          'No safety alerts triggered during this session.',
                          style: TextStyle(color: Colors.white24, fontSize: 13),
                        ),
                      ),
                    )
                  : ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: sessionEvents.length,
                      separatorBuilder: (context, index) => const Divider(color: Colors.white10, height: 1),
                      itemBuilder: (context, index) {
                        final event = sessionEvents[index];
                        final stateColor = _getStateColor(event.state);
                        final timestampStr = '${event.timestamp.hour.toString().padLeft(2, '0')}:${event.timestamp.minute.toString().padLeft(2, '0')}:${event.timestamp.second.toString().padLeft(2, '0')}';
                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                          title: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                event.state,
                                style: TextStyle(color: stateColor, fontWeight: FontWeight.bold, fontSize: 13),
                              ),
                              Text(
                                timestampStr,
                                style: const TextStyle(color: Colors.white24, fontSize: 11),
                              ),
                            ],
                          ),
                          subtitle: Text(
                            'Gas: ${event.gasValue ?? "--"} | Dist: ${event.distanceValue ?? "--"}',
                            style: const TextStyle(color: Colors.white54, fontSize: 12),
                          ),
                        );
                      },
                    ),
            ),

            const SizedBox(height: 30),

            // 5. Done Button
            ElevatedButton.icon(
              onPressed: () {
                Navigator.pop(context); // Goes back to the home screen
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0EA5E9),
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 50),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              icon: const Icon(Icons.done),
              label: const Text(
                'DONE / BACK TO HOME',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildRowItem(String label, String value, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.white54, fontSize: 13)),
          Text(
            value,
            style: TextStyle(
              color: color ?? Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  Color _getStateColor(String state) {
    switch (state) {
      case 'CRITICAL':
      case 'GAS ALERT':
      case 'DISTANCE ALERT':
        return const Color(0xFFEF4444);
      case 'CAUTION':
        return const Color(0xFFF59E0B);
      case 'SAFE':
        return const Color(0xFF10B981);
      default:
        return Colors.white38;
    }
  }
}
