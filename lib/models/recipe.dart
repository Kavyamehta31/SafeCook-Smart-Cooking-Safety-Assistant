class RecipeStep {
  final int stepNumber;
  final String instruction;
  final String voiceInstruction;
  final Duration? duration;
  final String? safetyTip;

  RecipeStep({
    required this.stepNumber,
    required this.instruction,
    required this.voiceInstruction,
    this.duration,
    this.safetyTip,
  });

  Map<String, dynamic> toJson() => {
        'stepNumber': stepNumber,
        'instruction': instruction,
        'voiceInstruction': voiceInstruction,
        'durationMs': duration?.inMilliseconds,
        'safetyTip': safetyTip,
      };

  factory RecipeStep.fromJson(Map<String, dynamic> json) => RecipeStep(
        stepNumber: json['stepNumber'] as int,
        instruction: json['instruction'] as String,
        voiceInstruction: json['voiceInstruction'] as String,
        duration: json['durationMs'] != null
            ? Duration(milliseconds: json['durationMs'] as int)
            : null,
        safetyTip: json['safetyTip'] as String?,
      );
}

class Recipe {
  final String id;
  final String name;
  final String category;
  final String description;
  final int cookingTime; // in minutes
  final String difficulty; // Easy, Medium, Hard
  final int servings;
  final List<String> ingredients;
  final List<RecipeStep> steps;
  final List<String> safetyNotes;

  Recipe({
    required this.id,
    required this.name,
    required this.category,
    required this.description,
    required this.cookingTime,
    required this.difficulty,
    required this.servings,
    required this.ingredients,
    required this.steps,
    required this.safetyNotes,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'category': category,
        'description': description,
        'cookingTime': cookingTime,
        'difficulty': difficulty,
        'servings': servings,
        'ingredients': ingredients,
        'steps': steps.map((s) => s.toJson()).toList(),
        'safetyNotes': safetyNotes,
      };

  factory Recipe.fromJson(Map<String, dynamic> json) => Recipe(
        id: json['id'] as String,
        name: json['name'] as String,
        category: json['category'] as String,
        description: json['description'] as String,
        cookingTime: json['cookingTime'] as int,
        difficulty: json['difficulty'] as String,
        servings: json['servings'] as int,
        ingredients: List<String>.from(json['ingredients'] as List),
        steps: (json['steps'] as List)
            .map((s) => RecipeStep.fromJson(s as Map<String, dynamic>))
            .toList(),
        safetyNotes: List<String>.from(json['safetyNotes'] as List),
      );
}
