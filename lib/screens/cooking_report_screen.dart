import 'package:flutter/material.dart';
import '../models/recipe.dart';
import '../main.dart'; // for SafetyEvent
import '../theme/safecook_theme.dart';
import '../widgets/safecook_widgets.dart';

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
  final bool completed;

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
    this.completed = true,
  });

  String _formatDuration(Duration d) {
    String two(int n) => n.toString().padLeft(2, '0');
    final m = two(d.inMinutes.remainder(60));
    final s = two(d.inSeconds.remainder(60));
    return '$m:$s';
  }

  String _resultText() {
    if (!completed) return 'Session Ended Early';
    if (criticalCount > 0) return 'Completed — Critical Incidents';
    if (cautionCount > 0 || gasAlertCount > 0 || distanceAlertCount > 0) {
      return 'Completed with Warnings';
    }
    return 'Completed Safely ✓';
  }

  Color _resultColor() {
    if (!completed) return SafeCookColors.caution;
    if (criticalCount > 0) return SafeCookColors.danger;
    if (cautionCount > 0 || gasAlertCount > 0 || distanceAlertCount > 0) {
      return SafeCookColors.caution;
    }
    return SafeCookColors.safe;
  }

  Color _resultBg() => _resultColor().withValues(alpha: 0.12);
  Color _resultBorder() => _resultColor().withValues(alpha: 0.35);

  IconData _resultIcon() {
    if (!completed) return Icons.stop_circle_outlined;
    if (criticalCount > 0) return Icons.cancel_rounded;
    if (cautionCount > 0 || gasAlertCount > 0 || distanceAlertCount > 0) {
      return Icons.warning_amber_rounded;
    }
    return Icons.check_circle_rounded;
  }

  Color _stateColor(String state) {
    switch (state) {
      case 'CRITICAL':
      case 'GAS ALERT':
      case 'DISTANCE ALERT':
        return SafeCookColors.danger;
      case 'CAUTION':
        return SafeCookColors.caution;
      case 'SAFE':
        return SafeCookColors.safe;
      default:
        return SafeCookColors.textSecondary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final totalAlerts = cautionCount + gasAlertCount + distanceAlertCount;

    return Scaffold(
      backgroundColor: SafeCookColors.background,
      appBar: AppBar(
        backgroundColor: SafeCookColors.background,
        automaticallyImplyLeading: false,
        title: const Row(
          children: [
            Icon(Icons.receipt_long_rounded, size: 20,
                color: SafeCookColors.primaryLight),
            SizedBox(width: 8),
            Text('Session Report'),
          ],
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 120),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),

            // ── Result hero card ─────────────────────────────────────────
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: _resultBg(),
                borderRadius: BorderRadius.circular(SafeCookRadius.lg),
                border: Border.all(color: _resultBorder()),
              ),
              child: Column(
                children: [
                  Icon(_resultIcon(), color: _resultColor(), size: 52),
                  const SizedBox(height: 12),
                  Text(
                    _resultText(),
                    style: TextStyle(
                      fontFamily: 'Nunito',
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: _resultColor(),
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    recipe.name,
                    style: SafeCookTextStyles.bodyMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),

                  // Quick stats row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _heroStat(
                        _formatDuration(duration),
                        'Duration',
                        Icons.timer_rounded,
                      ),
                      _dividerV(),
                      _heroStat(
                        '$stepsCompleted',
                        'Steps Done',
                        Icons.format_list_numbered_rounded,
                      ),
                      _dividerV(),
                      _heroStat(
                        '$totalAlerts',
                        'Alerts',
                        Icons.notifications_rounded,
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // ── Recipe info ──────────────────────────────────────────────
            const SCSection(label: 'Recipe'),
            SCCard(
              padding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 8,
              ),
              child: Column(
                children: [
                  StatRow(label: 'Name', value: recipe.name),
                  const Divider(height: 1),
                  StatRow(label: 'Category', value: recipe.category),
                  const Divider(height: 1),
                  StatRow(
                    label: 'Steps Completed',
                    value: '$stepsCompleted / ${recipe.steps.length}',
                    valueColor: completed
                        ? SafeCookColors.safe
                        : SafeCookColors.caution,
                  ),
                  const Divider(height: 1),
                  StatRow(
                    label: 'Est. Cooking Time',
                    value: '${recipe.cookingTime} min',
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // ── Safety & Sensor Summary ──────────────────────────────────
            const SCSection(label: 'Safety & Sensor Summary'),
            SCCard(
              padding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 8,
              ),
              child: Column(
                children: [
                  StatRow(
                    label: 'Final Safety Status',
                    value: finalState,
                    valueColor: _stateColor(finalState),
                  ),
                  const Divider(height: 1),
                  StatRow(
                    label: 'Session Duration',
                    value: _formatDuration(duration),
                  ),
                  const Divider(height: 1),
                  StatRow(
                    label: 'Peak Gas Reading',
                    value: maxGas != null ? '$maxGas raw ADC' : 'N/A',
                  ),
                  const Divider(height: 1),
                  StatRow(
                    label: 'Closest Chef Distance',
                    value: minDistance != null
                        ? '${minDistance!.toStringAsFixed(1)} cm'
                        : 'N/A',
                  ),
                  const SizedBox(height: 4),
                  const Divider(height: 8),
                  const SizedBox(height: 4),
                  StatRow(
                    label: 'Caution Events',
                    value: '$cautionCount',
                    valueColor: cautionCount > 0
                        ? SafeCookColors.caution
                        : SafeCookColors.textPrimary,
                  ),
                  const Divider(height: 1),
                  StatRow(
                    label: 'Gas Alerts',
                    value: '$gasAlertCount',
                    valueColor: gasAlertCount > 0
                        ? SafeCookColors.danger
                        : SafeCookColors.textPrimary,
                  ),
                  const Divider(height: 1),
                  StatRow(
                    label: 'Distance Alerts',
                    value: '$distanceAlertCount',
                    valueColor: distanceAlertCount > 0
                        ? SafeCookColors.danger
                        : SafeCookColors.textPrimary,
                  ),
                  const Divider(height: 1),
                  StatRow(
                    label: 'Critical Events',
                    value: '$criticalCount',
                    valueColor: criticalCount > 0
                        ? SafeCookColors.danger
                        : SafeCookColors.textPrimary,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // ── Session Safety Log ───────────────────────────────────────
            SCSection(
              label: 'Session Safety Log',
              trailing: Text(
                '${sessionEvents.length} event${sessionEvents.length == 1 ? '' : 's'}',
                style: SafeCookTextStyles.bodySmall,
              ),
            ),
            sessionEvents.isEmpty
                ? SCCard(
                    child: const SCEmptyState(
                      icon: Icons.verified_user_rounded,
                      title: 'No safety alerts',
                      subtitle:
                          'No safety events were triggered during this session.',
                    ),
                  )
                : SCCard(
                    padding: EdgeInsets.zero,
                    child: Column(
                      children: sessionEvents.asMap().entries.map((e) {
                        final event = e.value;
                        final stateColor = _stateColor(event.state);
                        final ts = event.timestamp;
                        final tsStr =
                            '${ts.hour.toString().padLeft(2, '0')}:${ts.minute.toString().padLeft(2, '0')}:${ts.second.toString().padLeft(2, '0')}';

                        return Column(
                          children: [
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 10,
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 4,
                                    height: 36,
                                    decoration: BoxDecoration(
                                      color: stateColor,
                                      borderRadius: BorderRadius.circular(2),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          event.state,
                                          style: TextStyle(
                                            fontFamily: 'Nunito',
                                            color: stateColor,
                                            fontWeight: FontWeight.w800,
                                            fontSize: 13,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          'Gas: ${event.gasValue ?? '--'} · '
                                          'Dist: ${event.distanceValue ?? '--'}',
                                          style: SafeCookTextStyles.bodySmall,
                                        ),
                                      ],
                                    ),
                                  ),
                                  Text(
                                    tsStr,
                                    style: const TextStyle(
                                      fontFamily: 'Nunito',
                                      color: SafeCookColors.textMuted,
                                      fontSize: 11,
                                      fontFeatures: [
                                        FontFeature.tabularFigures(),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (e.key < sessionEvents.length - 1)
                              const Divider(height: 1, indent: 32),
                          ],
                        );
                      }).toList(),
                    ),
                  ),
          ],
        ),
      ),

      // Done button
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
          child: ElevatedButton.icon(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(
              backgroundColor: SafeCookColors.primary,
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 56),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(SafeCookRadius.sm),
              ),
            ),
            icon: const Icon(Icons.home_rounded, size: 22),
            label: const Text(
              'Back to Home',
              style: TextStyle(
                fontFamily: 'Nunito',
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _heroStat(String value, String label, IconData icon) {
    return Column(
      children: [
        Icon(icon, color: _resultColor(), size: 18),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            fontFamily: 'Nunito',
            fontSize: 18,
            fontWeight: FontWeight.w900,
            color: SafeCookColors.textPrimary,
          ),
        ),
        Text(label, style: SafeCookTextStyles.bodySmall),
      ],
    );
  }

  Widget _dividerV() {
    return Container(
      width: 0.5,
      height: 48,
      color: SafeCookColors.divider,
    );
  }
}
