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
}
