import 'package:flutter/material.dart';
import '../data/recipes.dart';
import '../models/cooking_history_entry.dart';
import '../models/recipe.dart';
import '../services/preference_service.dart';
import '../theme/safecook_theme.dart';
import '../widgets/safecook_widgets.dart';

class MemoryScreen extends StatefulWidget {
  const MemoryScreen({super.key});

  @override
  State<MemoryScreen> createState() => _MemoryScreenState();
}

class _MemoryScreenState extends State<MemoryScreen> {
  final _preferences = PreferenceService();

  List<Recipe> get _dynamicRecipes => _preferences.getDynamicRecipes();
  List<CookingHistoryEntry> get _history =>
      _preferences.getCookingHistory().reversed.toList();

  Recipe? _recipeForId(String id) {
    for (final recipe in [...kPredefinedRecipes, ..._dynamicRecipes]) {
      if (recipe.id == id) return recipe;
    }
    return null;
  }

  Future<void> _deleteDynamicRecipe(Recipe recipe) async {
    await _preferences.deleteDynamicRecipe(recipe.id);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final dynamicRecipes = _dynamicRecipes;
    final history = _history;
    final recentIds = _preferences.getRecentRecipeIds();
    final frequency = _preferences.getRecipeFrequency();
    final favoriteIds = _preferences.getFavoriteRecipeIds();
    final completedSessions = _preferences.getCompletedSessionCount();
    final endedEarlySessions = _preferences.getAbortedSessionCount();
    final frequentIds = frequency.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Scaffold(
      backgroundColor: SafeCookColors.background,
      appBar: AppBar(
        backgroundColor: SafeCookColors.background,
        title: const Row(
          children: [
            Icon(
              Icons.psychology_rounded,
              color: SafeCookColors.primaryLight,
              size: 22,
            ),
            SizedBox(width: 8),
            Text('Memory'),
          ],
        ),
        actions: [
          IconButton(
            onPressed: () => setState(() {}),
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh memory',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => setState(() {}),
        color: SafeCookColors.primaryLight,
        backgroundColor: SafeCookColors.surfaceElevated,
        child: ListView(
          padding: const EdgeInsets.only(
            left: 20,
            right: 20,
            top: 8,
            bottom: 40,
          ),
          children: [
            // ── Preferences & Stats ──────────────────────────────────────
            const SCSection(label: 'Profile & Preferences'),
            SCCard(
              child: Column(
                children: [
                  _preferenceTile(
                    Icons.restaurant_rounded,
                    'Diet',
                    _preferences.isVegetarian() ? 'Vegetarian' : 'All recipes',
                  ),
                  const Divider(height: 1),
                  _preferenceTile(
                    Icons.public_rounded,
                    'Cuisine',
                    _preferences.getPreferredCuisine(),
                  ),
                  const Divider(height: 1),
                  _preferenceTile(
                    Icons.people_rounded,
                    'Servings',
                    '${_preferences.getPreferredServings()} people',
                  ),
                ],
              ),
            ),

            const SizedBox(height: SafeCookSpacing.md),

            // ── Cooking stats ────────────────────────────────────────────
            const SCSection(label: 'Cooking Statistics'),
            Row(
              children: [
                Expanded(
                  child: _statCard(
                    icon: Icons.check_circle_rounded,
                    color: SafeCookColors.safe,
                    count: completedSessions,
                    label: 'Completed',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _statCard(
                    icon: Icons.cancel_rounded,
                    color: SafeCookColors.caution,
                    count: endedEarlySessions,
                    label: 'Ended Early',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _statCard(
                    icon: Icons.history_edu_rounded,
                    color: SafeCookColors.primaryLight,
                    count: history.length,
                    label: 'Total Sessions',
                  ),
                ),
              ],
            ),

            const SizedBox(height: SafeCookSpacing.lg),

            // ── Favourites & Frequently Cooked ───────────────────────────
            const SCSection(label: 'Favourites & Frequently Cooked'),
            if (favoriteIds.isEmpty && frequentIds.isEmpty)
              _emptySection(
                Icons.favorite_border_rounded,
                'No favourites yet',
                'Mark recipes as favourite and cook them regularly to see them here.',
              )
            else
              SCCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    ...favoriteIds.asMap().entries.map((e) {
                      final isLast = e.key == favoriteIds.length - 1 &&
                          frequentIds
                              .where((en) => !favoriteIds.contains(en.key))
                              .isEmpty;
                      return _recipeSummaryTile(
                        e.value,
                        'Favourite',
                        Icons.favorite_rounded,
                        SafeCookColors.danger,
                        showDivider: !isLast,
                      );
                    }),
                    ...frequentIds
                        .where((entry) => !favoriteIds.contains(entry.key))
                        .take(5)
                        .toList()
                        .asMap()
                        .entries
                        .map((e) {
                      final entries = frequentIds
                          .where((en) => !favoriteIds.contains(en.key))
                          .take(5)
                          .toList();
                      return _recipeSummaryTile(
                        e.value.key,
                        '${e.value.value}× completed',
                        Icons.bar_chart_rounded,
                        SafeCookColors.primaryLight,
                        showDivider: e.key < entries.length - 1,
                      );
                    }),
                  ],
                ),
              ),

            const SizedBox(height: SafeCookSpacing.lg),

            // ── Recent Recipes ───────────────────────────────────────────
            const SCSection(label: 'Recent Recipes'),
            if (recentIds.isEmpty)
              _emptySection(
                Icons.history_rounded,
                'No recent activity',
                'Recipes you cook will appear here for quick access.',
              )
            else
              SCCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: recentIds.asMap().entries.map((e) {
                    final recipe = _recipeForId(e.value);
                    final cookCount = _preferences.getCookCount(e.value);
                    return _recentRecipeTile(
                      recipe?.name ?? e.value,
                      recipe?.category ?? '',
                      cookCount,
                      showDivider: e.key < recentIds.length - 1,
                    );
                  }).toList(),
                ),
              ),

            const SizedBox(height: SafeCookSpacing.lg),

            // ── Cooking History ──────────────────────────────────────────
            const SCSection(label: 'Cooking History'),
            if (history.isEmpty)
              _emptySection(
                Icons.receipt_long_rounded,
                'No sessions recorded',
                'Completed cooking sessions will appear here.',
              )
            else
              SCCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: history.asMap().entries.map((e) {
                    return _historyTile(
                      e.value,
                      showDivider: e.key < history.length - 1,
                    );
                  }).toList(),
                ),
              ),

            const SizedBox(height: SafeCookSpacing.lg),

            // ── Saved Online Recipes ─────────────────────────────────────
            const SCSection(label: 'Saved Online Recipes'),
            if (dynamicRecipes.isEmpty)
              _emptySection(
                Icons.cloud_download_outlined,
                'No saved recipes',
                'Recipes acquired through voice search will appear here.',
              )
            else
              SCCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: dynamicRecipes.asMap().entries.map((e) {
                    final recipe = e.value;
                    return Column(
                      children: [
                        ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 4,
                          ),
                          leading: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: SafeCookColors.primaryContainer,
                              borderRadius:
                                  BorderRadius.circular(SafeCookRadius.xs),
                            ),
                            child: const Icon(
                              Icons.cloud_done_rounded,
                              color: SafeCookColors.primaryLight,
                              size: 18,
                            ),
                          ),
                          title: Text(
                            recipe.name,
                            style: SafeCookTextStyles.titleSmall,
                          ),
                          subtitle: Text(
                            '${recipe.category} · ${recipe.steps.length} steps',
                            style: SafeCookTextStyles.bodySmall,
                          ),
                          trailing: IconButton(
                            onPressed: () => _deleteDynamicRecipe(recipe),
                            icon: const Icon(
                              Icons.delete_outline_rounded,
                              color: SafeCookColors.danger,
                              size: 20,
                            ),
                            tooltip: 'Delete saved recipe',
                          ),
                        ),
                        if (e.key < dynamicRecipes.length - 1)
                          const Divider(height: 1, indent: 16, endIndent: 16),
                      ],
                    );
                  }).toList(),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _preferenceTile(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Icon(icon, color: SafeCookColors.primaryLight, size: 18),
          const SizedBox(width: 12),
          Text(label, style: SafeCookTextStyles.bodyMedium),
          const Spacer(),
          Text(
            value,
            style: const TextStyle(
              fontFamily: 'Nunito',
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: SafeCookColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _statCard({
    required IconData icon,
    required Color color,
    required int count,
    required String label,
  }) {
    return SCCard(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(height: 8),
          Text(
            '$count',
            style: TextStyle(
              fontFamily: 'Nunito',
              fontSize: 24,
              fontWeight: FontWeight.w900,
              color: color,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: SafeCookTextStyles.bodySmall,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _recipeSummaryTile(
    String id,
    String detail,
    IconData icon,
    Color color, {
    bool showDivider = true,
  }) {
    final recipe = _recipeForId(id);
    return Column(
      children: [
        ListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          leading: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(SafeCookRadius.xs),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          title: Text(
            recipe?.name ?? id,
            style: SafeCookTextStyles.titleSmall,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(detail, style: SafeCookTextStyles.bodySmall),
        ),
        if (showDivider) const Divider(height: 1, indent: 16, endIndent: 16),
      ],
    );
  }

  Widget _recentRecipeTile(
    String name,
    String category,
    int cookCount, {
    bool showDivider = true,
  }) {
    return Column(
      children: [
        ListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          leading: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: SafeCookColors.primaryContainer,
              borderRadius: BorderRadius.circular(SafeCookRadius.xs),
            ),
            child: const Icon(
              Icons.history_rounded,
              color: SafeCookColors.primaryLight,
              size: 18,
            ),
          ),
          title: Text(
            name,
            style: SafeCookTextStyles.titleSmall,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            category.isNotEmpty ? category : 'Recipe',
            style: SafeCookTextStyles.bodySmall,
          ),
          trailing: Text(
            '$cookCount×',
            style: const TextStyle(
              fontFamily: 'Nunito',
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: SafeCookColors.primaryLight,
            ),
          ),
        ),
        if (showDivider) const Divider(height: 1, indent: 16, endIndent: 16),
      ],
    );
  }

  Widget _historyTile(CookingHistoryEntry entry, {bool showDivider = true}) {
    final recipe = _recipeForId(entry.recipeId);
    final color = entry.completed ? SafeCookColors.safe : SafeCookColors.caution;
    final icon = entry.completed
        ? Icons.check_circle_rounded
        : Icons.remove_circle_outline_rounded;

    final date = entry.completedAt;
    final dateStr =
        '${date.day}/${date.month}/${date.year % 100} · ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';

    return Column(
      children: [
        ListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          leading: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(SafeCookRadius.xs),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          title: Text(
            recipe?.name ?? entry.recipeId,
            style: SafeCookTextStyles.titleSmall,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            '${entry.completed ? 'Completed' : 'Ended early'} · '
            '${entry.stepsCompleted}/${entry.totalSteps} steps · '
            '${entry.duration.inMinutes} min',
            style: SafeCookTextStyles.bodySmall,
          ),
          trailing: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                dateStr,
                style: const TextStyle(
                  fontFamily: 'Nunito',
                  color: SafeCookColors.textMuted,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
        if (showDivider) const Divider(height: 1, indent: 16, endIndent: 16),
      ],
    );
  }

  Widget _emptySection(IconData icon, String title, String subtitle) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: SafeCookColors.surfaceElevated,
              borderRadius: BorderRadius.circular(SafeCookRadius.sm),
              border: Border.all(color: SafeCookColors.border),
            ),
            child: Icon(icon, color: SafeCookColors.textMuted, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: SafeCookTextStyles.titleSmall),
                const SizedBox(height: 2),
                Text(subtitle, style: SafeCookTextStyles.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
