import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/recipe.dart';
import '../models/cooking_history_entry.dart';

class PreferenceService {
  static final PreferenceService _instance = PreferenceService._internal();
  factory PreferenceService() => _instance;
  PreferenceService._internal();

  SharedPreferences? _prefs;
  bool _isInitialized = false;

  Future<void> init() async {
    if (_isInitialized) return;
    try {
      _prefs = await SharedPreferences.getInstance();
      _isInitialized = true;
    } catch (e) {
      debugPrint(
        '[SafeCook PREFS ERROR] Failed to initialize SharedPreferences: $e',
      );
    }
  }

  // --- Favorites ---
  List<String> getFavoriteRecipeIds() {
    if (!_isInitialized || _prefs == null) return [];
    try {
      return _prefs!.getStringList(_kFavoritesKey) ?? [];
    } catch (e) {
      debugPrint('[SafeCook PREFS ERROR] Failed to get favorites: $e');
      return [];
    }
  }

  Future<void> setFavorite(String recipeId, bool value) async {
    if (!_isInitialized || _prefs == null) return;
    try {
      final favs = getFavoriteRecipeIds().toSet();
      if (value) {
        favs.add(recipeId);
      } else {
        favs.remove(recipeId);
      }
      await _prefs!.setStringList(_kFavoritesKey, favs.toList());
    } catch (e) {
      debugPrint('[SafeCook PREFS ERROR] Failed to set favorite: $e');
    }
  }

  bool isFavorite(String recipeId) {
    return getFavoriteRecipeIds().contains(recipeId);
  }

  // --- Cook Counts ---
  int getCookCount(String recipeId) {
    if (!_isInitialized || _prefs == null) return 0;
    try {
      return _prefs!.getInt('$_kCookCountPrefix$recipeId') ?? 0;
    } catch (e) {
      debugPrint('[SafeCook PREFS ERROR] Failed to get cook count: $e');
      return 0;
    }
  }

  Future<void> incrementCookCount(String recipeId) async {
    if (!_isInitialized || _prefs == null) return;
    try {
      final count = getCookCount(recipeId);
      await _prefs!.setInt('$_kCookCountPrefix$recipeId', count + 1);
    } catch (e) {
      debugPrint('[SafeCook PREFS ERROR] Failed to increment cook count: $e');
    }
  }

  // --- Vegetarian Preference ---
  bool isVegetarian() {
    if (!_isInitialized || _prefs == null) return false;
    try {
      return _prefs!.getBool(_kVegetarianKey) ?? false;
    } catch (e) {
      debugPrint('[SafeCook PREFS ERROR] Failed to get vegetarian pref: $e');
      return false;
    }
  }

  Future<void> setVegetarian(bool value) async {
    if (!_isInitialized || _prefs == null) return;
    try {
      await _prefs!.setBool(_kVegetarianKey, value);
    } catch (e) {
      debugPrint('[SafeCook PREFS ERROR] Failed to set vegetarian pref: $e');
    }
  }

  // --- Cooking Preferences ---
  String getPreferredCuisine() {
    if (!_isInitialized || _prefs == null) return 'Any';
    return _prefs!.getString(_kPreferredCuisineKey) ?? 'Any';
  }

  Future<void> setPreferredCuisine(String cuisine) async {
    if (!_isInitialized || _prefs == null) return;
    await _prefs!.setString(_kPreferredCuisineKey, cuisine);
  }

  int getPreferredServings() {
    if (!_isInitialized || _prefs == null) return 2;
    return _prefs!.getInt(_kPreferredServingsKey) ?? 2;
  }

  Future<void> setPreferredServings(int servings) async {
    if (!_isInitialized || _prefs == null) return;
    await _prefs!.setInt(_kPreferredServingsKey, servings.clamp(1, 12));
  }

  // --- Last Cooked Recipe ---
  String? getLastCookedRecipeId() {
    if (!_isInitialized || _prefs == null) return null;
    try {
      return _prefs!.getString(_kLastCookedKey);
    } catch (e) {
      debugPrint('[SafeCook PREFS ERROR] Failed to get last cooked recipe: $e');
      return null;
    }
  }

  Future<void> setLastCookedRecipeId(String recipeId) async {
    if (!_isInitialized || _prefs == null) return;
    try {
      await _prefs!.setString(_kLastCookedKey, recipeId);
    } catch (e) {
      debugPrint('[SafeCook PREFS ERROR] Failed to set last cooked recipe: $e');
    }
  }

  // --- Dynamic Recipes ---
  List<Recipe> getDynamicRecipes() {
    if (!_isInitialized || _prefs == null) return [];
    try {
      final list = _prefs!.getStringList(_kDynamicRecipesKey) ?? [];
      return list
          .map((item) {
            try {
              return Recipe.fromJson(jsonDecode(item) as Map<String, dynamic>);
            } catch (e) {
              debugPrint(
                '[SafeCook PREFS ERROR] Failed to decode dynamic recipe: $e',
              );
              return null;
            }
          })
          .whereType<Recipe>()
          .toList();
    } catch (e) {
      debugPrint('[SafeCook PREFS ERROR] Failed to get dynamic recipes: $e');
      return [];
    }
  }

  Future<void> saveDynamicRecipe(Recipe recipe) async {
    if (!_isInitialized || _prefs == null) return;
    try {
      final recipes = getDynamicRecipes();
      recipes.removeWhere((r) => r.id == recipe.id);
      recipes.add(recipe);
      final list = recipes.map((r) => jsonEncode(r.toJson())).toList();
      await _prefs!.setStringList(_kDynamicRecipesKey, list);
    } catch (e) {
      debugPrint('[SafeCook PREFS ERROR] Failed to save dynamic recipe: $e');
    }
  }

  Future<void> deleteDynamicRecipe(String recipeId) async {
    if (!_isInitialized || _prefs == null) return;
    try {
      final recipes = getDynamicRecipes();
      recipes.removeWhere((r) => r.id == recipeId);
      final list = recipes.map((r) => jsonEncode(r.toJson())).toList();
      await _prefs!.setStringList(_kDynamicRecipesKey, list);
    } catch (e) {
      debugPrint('[SafeCook PREFS ERROR] Failed to delete dynamic recipe: $e');
    }
  }

  // --- Recent Recipes ---
  List<String> getRecentRecipeIds() {
    if (!_isInitialized || _prefs == null) return [];
    try {
      return _prefs!.getStringList(_kRecentRecipesKey) ?? [];
    } catch (e) {
      debugPrint('[SafeCook PREFS ERROR] Failed to get recent recipes: $e');
      return [];
    }
  }

  Future<void> addToRecentRecipes(String recipeId) async {
    if (!_isInitialized || _prefs == null) return;
    try {
      final recent = getRecentRecipeIds();
      recent.remove(recipeId);
      recent.insert(0, recipeId);
      await _prefs!.setStringList(_kRecentRecipesKey, recent);
    } catch (e) {
      debugPrint('[SafeCook PREFS ERROR] Failed to add to recent recipes: $e');
    }
  }

  // --- Cooking History ---
  List<CookingHistoryEntry> getCookingHistory() {
    if (!_isInitialized || _prefs == null) return [];
    try {
      final list = _prefs!.getStringList(_kCookingHistoryKey) ?? [];
      return list
          .map((item) {
            try {
              return CookingHistoryEntry.fromJson(
                jsonDecode(item) as Map<String, dynamic>,
              );
            } catch (e) {
              debugPrint(
                '[SafeCook PREFS ERROR] Failed to decode cooking history: $e',
              );
              return null;
            }
          })
          .whereType<CookingHistoryEntry>()
          .toList();
    } catch (e) {
      debugPrint('[SafeCook PREFS ERROR] Failed to get cooking history: $e');
      return [];
    }
  }

  Future<void> addCookingHistoryEntry(CookingHistoryEntry entry) async {
    if (!_isInitialized || _prefs == null) return;
    try {
      final history = getCookingHistory();
      history.add(entry);
      final list = history.map((e) => jsonEncode(e.toJson())).toList();
      await _prefs!.setStringList(_kCookingHistoryKey, list);
    } catch (e) {
      debugPrint('[SafeCook PREFS ERROR] Failed to add cooking history: $e');
    }
  }

  int getCompletedSessionCount() =>
      getCookingHistory().where((entry) => entry.completed).length;

  int getAbortedSessionCount() =>
      getCookingHistory().where((entry) => !entry.completed).length;

  Map<String, int> getRecipeFrequency() {
    final frequency = <String, int>{};
    for (final entry in getCookingHistory().where((entry) => entry.completed)) {
      frequency.update(entry.recipeId, (count) => count + 1, ifAbsent: () => 1);
    }
    return frequency;
  }

  // Helper method to clear/reset mock for testing
  @visibleForTesting
  Future<void> resetForTesting() async {
    _isInitialized = false;
    _prefs = null;
    await init();
  }

  // Keys
  static const _kFavoritesKey = 'safecook_favorites';
  static const _kVegetarianKey = 'safecook_vegetarian';
  static const _kPreferredCuisineKey = 'safecook_preferred_cuisine';
  static const _kPreferredServingsKey = 'safecook_preferred_servings';
  static const _kLastCookedKey = 'safecook_last_cooked';
  static const _kCookCountPrefix = 'safecook_cook_count_';
  static const _kDynamicRecipesKey = 'safecook_dynamic_recipes';
  static const _kRecentRecipesKey = 'safecook_recent_recipes';
  static const _kCookingHistoryKey = 'safecook_cooking_history';
}
