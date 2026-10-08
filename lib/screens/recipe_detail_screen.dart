import 'package:flutter/material.dart';
import '../models/recipe.dart';
import '../services/preference_service.dart';
import '../theme/safecook_theme.dart';
import '../widgets/safecook_widgets.dart';

class RecipeDetailScreen extends StatefulWidget {
  final Recipe recipe;

  const RecipeDetailScreen({super.key, required this.recipe});

  @override
  State<RecipeDetailScreen> createState() => _RecipeDetailScreenState();
}

class _RecipeDetailScreenState extends State<RecipeDetailScreen> {
  @override
  Widget build(BuildContext context) {
    final recipe = widget.recipe;
    final isFav = PreferenceService().isFavorite(recipe.id);

    return Scaffold(
      backgroundColor: SafeCookColors.background,
      appBar: AppBar(
        backgroundColor: SafeCookColors.background,
        title: Text(
          recipe.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          Semantics(
            button: true,
            label: isFav ? 'Remove from favourites' : 'Add to favourites',
            child: IconButton(
              icon: Icon(
                isFav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                color: isFav ? SafeCookColors.danger : SafeCookColors.textSecondary,
              ),
              onPressed: () async {
                await PreferenceService().setFavorite(recipe.id, !isFav);
                setState(() {});
              },
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Hero card ───────────────────────────────────────────────
            SCCard(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Category label
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: SafeCookColors.primaryContainer,
                      borderRadius: BorderRadius.circular(SafeCookRadius.xs),
                    ),
                    child: Text(
                      recipe.category.toUpperCase(),
                      style: const TextStyle(
                        fontFamily: 'Nunito',
                        color: SafeCookColors.primaryLight,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.0,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(recipe.name, style: SafeCookTextStyles.titleLarge),
                  const SizedBox(height: 8),
                  Text(
                    recipe.description,
                    style: SafeCookTextStyles.bodyMedium,
                  ),
                  const SizedBox(height: 20),
                  const Divider(height: 1),
                  const SizedBox(height: 20),

                  // Meta row
                  Row(
                    children: [
                      Expanded(
                        child: _metaItem(
                          Icons.access_time_rounded,
                          '${recipe.cookingTime} min',
                          'Cook Time',
                        ),
                      ),
                      _verticalDivider(),
                      Expanded(
                        child: _metaItem(
                          Icons.speed_rounded,
                          recipe.difficulty,
                          'Difficulty',
                        ),
                      ),
                      _verticalDivider(),
                      Expanded(
                        child: _metaItem(
                          Icons.people_rounded,
                          '${recipe.servings}',
                          'Servings',
                        ),
                      ),
                      _verticalDivider(),
                      Expanded(
                        child: _metaItem(
                          Icons.format_list_numbered_rounded,
                          '${recipe.steps.length}',
                          'Steps',
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // ── Ingredients ─────────────────────────────────────────────
            const SCSection(label: 'Ingredients'),
            SCCard(
              padding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 12,
              ),
              child: Column(
                children: recipe.ingredients.asMap().entries.map((e) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          margin: const EdgeInsets.only(top: 6),
                          decoration: const BoxDecoration(
                            color: SafeCookColors.primaryLight,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            e.value,
                            style: SafeCookTextStyles.bodyLarge,
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),

            const SizedBox(height: 24),

            // ── Safety Precautions ──────────────────────────────────────
            const SCSection(label: 'Safety Precautions'),
            Container(
              decoration: BoxDecoration(
                color: SafeCookColors.dangerBg,
                borderRadius: BorderRadius.circular(SafeCookRadius.md),
                border: Border.all(color: SafeCookColors.dangerBorder),
              ),
              padding: const EdgeInsets.all(16),
              child: Column(
                children: recipe.safetyNotes.map((note) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.shield_rounded,
                          color: SafeCookColors.danger,
                          size: 16,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            note,
                            style: SafeCookTextStyles.bodyLarge.copyWith(
                              color: SafeCookColors.textPrimary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),

            const SizedBox(height: 24),

            // ── Cooking Steps ───────────────────────────────────────────
            Row(
              children: [
                const SCSection(label: 'Cooking Steps'),
                const Spacer(),
                Text(
                  '${recipe.steps.length} steps',
                  style: SafeCookTextStyles.bodySmall,
                ),
              ],
            ),
            const SizedBox(height: 12),

            SCCard(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: recipe.steps.asMap().entries.map((e) {
                  final step = e.value;
                  final isLast = e.key == recipe.steps.length - 1;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Step number bubble
                          Container(
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                              color: SafeCookColors.primaryContainer,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: SafeCookColors.primaryLight
                                    .withValues(alpha: 0.3),
                              ),
                            ),
                            child: Center(
                              child: Text(
                                '${step.stepNumber}',
                                style: const TextStyle(
                                  fontFamily: 'Nunito',
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                  color: SafeCookColors.primaryLight,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const SizedBox(height: 4),
                                Text(
                                  step.instruction,
                                  style: SafeCookTextStyles.bodyLarge,
                                ),
                                if (step.safetyTip != null) ...[
                                  const SizedBox(height: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: SafeCookColors.cautionBg,
                                      borderRadius: BorderRadius.circular(
                                        SafeCookRadius.xs,
                                      ),
                                      border: Border.all(
                                        color: SafeCookColors.cautionBorder,
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        const Icon(
                                          Icons.shield_outlined,
                                          color: SafeCookColors.caution,
                                          size: 14,
                                        ),
                                        const SizedBox(width: 6),
                                        Expanded(
                                          child: Text(
                                            step.safetyTip!,
                                            style: const TextStyle(
                                              fontFamily: 'Nunito',
                                              color: SafeCookColors.caution,
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                      if (!isLast) ...[
                        const SizedBox(height: 12),
                        const Divider(height: 1, indent: 40),
                        const SizedBox(height: 12),
                      ],
                    ],
                  );
                }).toList(),
              ),
            ),

            const SizedBox(height: 32),
          ],
        ),
      ),

      // Start cooking CTA
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
          child: Semantics(
            button: true,
            label: 'Start cooking this recipe',
            child: ElevatedButton.icon(
              onPressed: () => Navigator.pop(context, recipe),
              style: ElevatedButton.styleFrom(
                backgroundColor: SafeCookColors.safe,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 56),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(SafeCookRadius.sm),
                ),
              ),
              icon: const Icon(Icons.restaurant_menu_rounded, size: 22),
              label: const Text(
                'Start Cooking',
                style: TextStyle(
                  fontFamily: 'Nunito',
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _metaItem(IconData icon, String value, String label) {
    return Column(
      children: [
        Icon(icon, color: SafeCookColors.primaryLight, size: 20),
        const SizedBox(height: 6),
        Text(value, style: SafeCookTextStyles.titleSmall),
        const SizedBox(height: 2),
        Text(label, style: SafeCookTextStyles.bodySmall),
      ],
    );
  }

  Widget _verticalDivider() {
    return Container(width: 0.5, height: 48, color: SafeCookColors.divider);
  }
}
