import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
      debugPrint('[SafeCook PREFS ERROR] Failed to initialize SharedPreferences: $e');
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
  static const _kLastCookedKey = 'safecook_last_cooked';
  static const _kCookCountPrefix = 'safecook_cook_count_';
}
