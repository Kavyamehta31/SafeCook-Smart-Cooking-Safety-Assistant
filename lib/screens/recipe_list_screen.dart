import 'package:flutter/material.dart';
import '../data/recipes.dart';
import '../models/recipe.dart';
import 'recipe_detail_screen.dart';
import '../services/preference_service.dart';
import '../theme/safecook_theme.dart';
import '../widgets/safecook_widgets.dart';

class RecipeListScreen extends StatefulWidget {
  const RecipeListScreen({super.key});

  @override
  State<RecipeListScreen> createState() => _RecipeListScreenState();
}

class _RecipeListScreenState extends State<RecipeListScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _selectedCategory = 'All';
  String _searchQuery = '';
  bool _vegetarianOnly = PreferenceService().isVegetarian();

  final List<String> _categories = [
    'All',
    'Favourites',
    'Breakfast',
    'Indian Main Course',
    'Rice & Biryani',
    'Snacks',
    'Soups & Light Meals',
    'Pasta/Noodles',
    'Egg/Quick Meals',
  ];

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final allRecipes = <Recipe>[
      ...kPredefinedRecipes,
      ...PreferenceService().getDynamicRecipes(),
    ];
    final filteredRecipes = allRecipes.where((recipe) {
      if (_vegetarianOnly) {
        final nonVegKeywords = [
          'chicken',
          'egg',
          'fish',
          'mutton',
          'prawn',
          'meat',
          'lamb',
        ];
        final nameLower = recipe.name.toLowerCase();
        final descLower = recipe.description.toLowerCase();
        final isNonVeg = nonVegKeywords.any(
          (kw) => nameLower.contains(kw) || descLower.contains(kw),
        );
        if (isNonVeg) return false;
      }

      bool matchesCategory = false;
      if (_selectedCategory == 'All') {
        matchesCategory = true;
      } else if (_selectedCategory == 'Favourites') {
        matchesCategory = PreferenceService().isFavorite(recipe.id);
      } else {
        matchesCategory = recipe.category == _selectedCategory;
      }

      final matchesSearch =
          recipe.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          recipe.ingredients.any(
            (ing) => ing.toLowerCase().contains(_searchQuery.toLowerCase()),
          );
      return matchesCategory && matchesSearch;
    }).toList();

    return Scaffold(
      backgroundColor: SafeCookColors.background,
      appBar: AppBar(
        backgroundColor: SafeCookColors.background,
        title: const Text('Recipes'),
        actions: [
          // Veg-only toggle
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Row(
              children: [
                const Icon(
                  Icons.eco_rounded,
                  size: 16,
                  color: SafeCookColors.safe,
                ),
                const SizedBox(width: 4),
                const Text(
                  'Veg',
                  style: TextStyle(
                    fontFamily: 'Nunito',
                    fontSize: 13,
                    color: SafeCookColors.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Switch(
                  value: _vegetarianOnly,
                  onChanged: (val) async {
                    await PreferenceService().setVegetarian(val);
                    setState(() {
                      _vegetarianOnly = val;
                    });
                  },
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ],
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: TextField(
              controller: _searchController,
              onChanged: (val) => setState(() => _searchQuery = val),
              style: const TextStyle(
                fontFamily: 'Nunito',
                color: SafeCookColors.textPrimary,
              ),
              decoration: InputDecoration(
                hintText: 'Search recipes or ingredients…',
                prefixIcon: const Icon(
                  Icons.search_rounded,
                  color: SafeCookColors.textSecondary,
                  size: 20,
                ),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(
                          Icons.clear_rounded,
                          color: SafeCookColors.textSecondary,
                          size: 18,
                        ),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        },
                      )
                    : null,
              ),
            ),
          ),

          // Category chips
          SizedBox(
            height: 44,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: _categories.length,
              itemBuilder: (context, index) {
                final cat = _categories[index];
                final isSelected = _selectedCategory == cat;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    label: Text(cat),
                    selected: isSelected,
                    onSelected: (selected) =>
                        setState(() => _selectedCategory = cat),
                    selectedColor: SafeCookColors.primaryContainer,
                    checkmarkColor: SafeCookColors.primaryLight,
                    labelStyle: TextStyle(
                      fontFamily: 'Nunito',
                      color: isSelected
                          ? SafeCookColors.primaryLight
                          : SafeCookColors.textSecondary,
                      fontWeight: isSelected
                          ? FontWeight.w700
                          : FontWeight.w500,
                      fontSize: 13,
                    ),
                    backgroundColor: SafeCookColors.surfaceElevated,
                    side: BorderSide(
                      color: isSelected
                          ? SafeCookColors.primaryLight.withValues(alpha: 0.4)
                          : SafeCookColors.border,
                      width: 0.5,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(SafeCookRadius.xs),
                    ),
                    showCheckmark: false,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 0,
                    ),
                  ),
                );
              },
            ),
          ),

          const SizedBox(height: 4),

          // Recipe count
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
            child: Row(
              children: [
                Text(
                  '${filteredRecipes.length} recipe${filteredRecipes.length == 1 ? '' : 's'}',
                  style: SafeCookTextStyles.label,
                ),
              ],
            ),
          ),

          // Recipe list
          Expanded(
            child: filteredRecipes.isEmpty
                ? SCEmptyState(
                    icon: Icons.restaurant_menu_rounded,
                    title: _searchQuery.isNotEmpty
                        ? 'No matches found'
                        : 'No recipes in this category',
                    subtitle: _searchQuery.isNotEmpty
                        ? 'Try a different search term or category.'
                        : 'Switch category or turn off filters.',
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
                    itemCount: filteredRecipes.length,
                    itemBuilder: (context, index) {
                      final recipe = filteredRecipes[index];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _RecipeCard(
                          recipe: recipe,
                          onFavToggle: () => setState(() {}),
                          onSelect: () async {
                            final result = await Navigator.push<Recipe>(
                              context,
                              MaterialPageRoute(
                                builder: (context) =>
                                    RecipeDetailScreen(recipe: recipe),
                              ),
                            );
                            if (mounted) setState(() {});
                            if (result != null && context.mounted) {
                              Navigator.pop(context, result);
                            }
                          },
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _RecipeCard extends StatelessWidget {
  final Recipe recipe;
  final VoidCallback onFavToggle;
  final VoidCallback onSelect;

  const _RecipeCard({
    required this.recipe,
    required this.onFavToggle,
    required this.onSelect,
  });

  Color _difficultyColor(String d) {
    switch (d.toLowerCase()) {
      case 'easy':
        return SafeCookColors.safe;
      case 'medium':
        return SafeCookColors.caution;
      case 'hard':
        return SafeCookColors.danger;
      default:
        return SafeCookColors.textSecondary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isFav = PreferenceService().isFavorite(recipe.id);
    final diffColor = _difficultyColor(recipe.difficulty);

    return SCCard(
      padding: EdgeInsets.zero,
      onTap: onSelect,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row
            Row(
              children: [
                // Category tag
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: SafeCookColors.primaryContainer,
                    borderRadius: BorderRadius.circular(SafeCookRadius.xs),
                  ),
                  child: Text(
                    recipe.category,
                    style: const TextStyle(
                      fontFamily: 'Nunito',
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: SafeCookColors.primaryLight,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // Difficulty tag
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: diffColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(SafeCookRadius.xs),
                  ),
                  child: Text(
                    recipe.difficulty,
                    style: TextStyle(
                      fontFamily: 'Nunito',
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: diffColor,
                    ),
                  ),
                ),
                const Spacer(),
                // Favourite button
                Semantics(
                  button: true,
                  label: isFav
                      ? 'Remove from favourites'
                      : 'Add to favourites',
                  child: GestureDetector(
                    onTap: () async {
                      await PreferenceService().setFavorite(recipe.id, !isFav);
                      onFavToggle();
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(
                        isFav
                            ? Icons.favorite_rounded
                            : Icons.favorite_border_rounded,
                        color:
                            isFav ? SafeCookColors.danger : SafeCookColors.textMuted,
                        size: 20,
                      ),
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 10),

            // Recipe name
            Text(
              recipe.name,
              style: SafeCookTextStyles.titleMedium,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),

            const SizedBox(height: 6),

            // Description
            Text(
              recipe.description,
              style: SafeCookTextStyles.bodyMedium,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),

            const SizedBox(height: 12),

            // Meta row
            Row(
              children: [
                _metaPill(
                  Icons.access_time_rounded,
                  '${recipe.cookingTime} min',
                ),
                const SizedBox(width: 8),
                _metaPill(
                  Icons.people_outline_rounded,
                  '${recipe.servings} servings',
                ),
                const SizedBox(width: 8),
                _metaPill(
                  Icons.format_list_numbered_rounded,
                  '${recipe.steps.length} steps',
                ),
                const Spacer(),
                // Cook button
                Semantics(
                  button: true,
                  label: 'View recipe and start cooking',
                  child: ElevatedButton(
                    onPressed: onSelect,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: SafeCookColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 0,
                      ),
                      minimumSize: const Size(0, 36),
                      textStyle: const TextStyle(
                        fontFamily: 'Nunito',
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(SafeCookRadius.xs),
                      ),
                    ),
                    child: const Text('View'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _metaPill(IconData icon, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: SafeCookColors.textMuted),
        const SizedBox(width: 3),
        Text(
          label,
          style: const TextStyle(
            fontFamily: 'Nunito',
            fontSize: 11,
            color: SafeCookColors.textSecondary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
