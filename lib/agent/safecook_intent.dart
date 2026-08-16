// ignore_for_file: avoid_print

// ---------------------------------------------------------------------------
// SafeCookIntentType — every high-level action the agent can take.
// ---------------------------------------------------------------------------
enum SafeCookIntentType {
  greeting,
  findRecipe,
  selectRecipe,     // Resolve from a numbered / named list
  selectRecipeByName, // User said an exact or partial recipe name
  startCooking,
  nextStep,
  previousStep,
  goToStep,         // "go to step 4"
  readStep,
  readIngredients,
  readSafetyNotes,
  checkGas,
  checkDistance,
  checkSafety,
  checkTime,
  checkConnectionStatus,
  connectBluetooth,
  disconnectBluetooth,
  endCooking,
  confirmYes,
  confirmNo,
  help,
  cookingQuestion,
  webSearch,
  unknown,
}

// ---------------------------------------------------------------------------
// SafeCookIntent — parsed intent with typed entities.
// ---------------------------------------------------------------------------
class SafeCookIntent {
  final SafeCookIntentType type;
  final String rawQuery;         // Original user utterance
  final Map<String, dynamic> entities;

  const SafeCookIntent({
    required this.type,
    required this.rawQuery,
    this.entities = const {},
  });

  @override
  String toString() => 'SafeCookIntent(type=$type, entities=$entities)';
}

// ---------------------------------------------------------------------------
// SafeCookNLU — stateless NLU parser.
//
// Design rules:
// 1. Context-aware: conversation state is passed in so the same phrase
//    means different things in different states.
// 2. Uses entity extraction, not just contains() chains.
// 3. selectRecipe ONLY fires when the utterance is plausibly selecting from
//    a list — not when the user mentions ordinal words in other contexts.
// 4. Covers at least 40 natural language variants for common commands.
// ---------------------------------------------------------------------------
class SafeCookNLU {
  static const Map<String, int> numberWords = {
    'one': 1, 'first': 1,
    'two': 2, 'second': 2,
    'three': 3, 'third': 3,
    'four': 4, 'fourth': 4,
    'five': 5, 'fifth': 5,
    'six': 6, 'sixth': 6,
    'seven': 7, 'seventh': 7,
    'eight': 8, 'eighth': 8,
    'nine': 9, 'nineth': 9,
    'ten': 10, 'tenth': 10,
  };

  // Normalise: lowercase, collapse whitespace, strip harmless punctuation and filler words
  static String _norm(String s) {
    var q = s.toLowerCase().trim();
    // Normalize curly apostrophes to straight ones
    q = q.replaceAll('’', "'").replaceAll('‘', "'");
    // Remove harmless punctuation (commas, trailing question marks/periods)
    q = q.replaceAll(RegExp(r'[.,\/#!$%\^&\*;:{}=\-_`~()?]'), '');
    // Collapse repeated whitespace
    q = q.replaceAll(RegExp(r'\s+'), ' ');
    
    // Remove common conversational filler words if they appear at start/end or as words
    final fillers = [
      'please go to', 'can you please', 'could you please', 'can you',
      'could you', 'can we', 'let\'s', 'okay', 'ok', 'hey', 'hello', 'hi',
      'please'
    ];
    for (final filler in fillers) {
      q = q.replaceAll(RegExp('\\b$filler\\b', caseSensitive: false), '');
    }
    // Re-collapse whitespace after removing fillers
    q = q.replaceAll(RegExp(r'\s+'), ' ').trim();
    return q;
  }

  static SafeCookIntent parse(
    String rawInput, {
    String conversationState = 'idle',
    bool isCookingActive = false,
  }) {
    final q = _norm(rawInput);
    print('[SafeCookNLU] raw="$rawInput" norm="$q" state=$conversationState');

    // ------------------------------------------------------------------
    // PRIORITY 0: Wake / greeting
    // ------------------------------------------------------------------
    if (_matchesAny(q, [
      'hello safecook', 'hey safecook', 'hello safe cook', 'hey safe cook',
      'hi safecook', 'wake up', 'are you there', 'hey', 'hello',
    ])) {
      return SafeCookIntent(type: SafeCookIntentType.greeting, rawQuery: rawInput);
    }

    // ------------------------------------------------------------------
    // PRIORITY 1: Help
    // ------------------------------------------------------------------
    if (_matchesAny(q, [
      'help', 'what can i say', 'what can i do', 'commands', 'guide me',
      'voice commands', 'how do you work', 'what are my options',
    ])) {
      return SafeCookIntent(type: SafeCookIntentType.help, rawQuery: rawInput);
    }

    // ------------------------------------------------------------------
    // PRIORITY 2: Navigation in active cooking (highest priority in cooking)
    // Checked BEFORE recipe selection to avoid "step", "next", "first" etc.
    // being misrouted during cooking.
    // ------------------------------------------------------------------

    // Go to specific step: "go to step 4", "step 3 please", "jump to step 2"
    final stepGoMatch = RegExp(
        r"(?:go to|jump to|skip to|open|show|take me to|move to|start|let's go to)?\s*step\s*(?:number)?\s*(\d+|one|two|three|four|five|six|seven|eight|nine|ten|first|second|third|fourth|fifth|sixth|seventh|eighth|nineth|tenth)",
        caseSensitive: false).firstMatch(q);
    if (stepGoMatch != null) {
      final valStr = stepGoMatch.group(1) ?? '';
      final num = int.tryParse(valStr) ?? numberWords[valStr];
      if (num != null) {
        return SafeCookIntent(
          type: SafeCookIntentType.goToStep,
          rawQuery: rawInput,
          entities: {'stepNumber': num},
        );
      }
    }

    // Next step
    if (_matchesAny(q, [
      'next step', 'next', 'continue', 'go ahead', 'move on', 'move forward',
      "what's next", 'what is next', "i'm done", 'i am done', 'done',
      'finished', 'i finished', 'i\'ve done that', 'ok next', 'proceed',
      'take me to the next step', 'go to the next step', 'go on',
      'carry on', 'all done', 'that\'s done', 'completed',
    ]) && !q.contains('cooking') && !q.contains('session')) {
      return SafeCookIntent(type: SafeCookIntentType.nextStep, rawQuery: rawInput);
    }

    // Previous step
    if (_matchesAny(q, [
      'previous step', 'previous', 'go back', 'back', 'step back',
      'last step', 'prior step', 'go to previous step', 'move back',
      'go back one step', 'take me back', 'rewind',
    ])) {
      return SafeCookIntent(type: SafeCookIntentType.previousStep, rawQuery: rawInput);
    }

    // Repeat/read current step
    if (_matchesAny(q, [
      'repeat', 'say that again', 'read step', 'read this step',
      'read the step', 'i missed that', 'what was that', 'again',
      'repeat that', 'tell me that again', 'can you repeat', 'say again',
      'pardon', 'sorry', 'one more time',
    ])) {
      return SafeCookIntent(type: SafeCookIntentType.readStep, rawQuery: rawInput);
    }

    // Read ingredients
    if (_matchesAny(q, [
      'ingredients', 'what do i need', 'show ingredients', 'read ingredients',
      'list ingredients', 'what ingredients', 'what are the ingredients',
      'what do i need for this', 'items needed', 'grocery list',
    ])) {
      return SafeCookIntent(type: SafeCookIntentType.readIngredients, rawQuery: rawInput);
    }

    // Read safety notes
    if (_matchesAny(q, [
      'safety notes', 'safety tips', 'safety precautions', 'precautions',
      'safety advice', 'is this safe to cook', 'any warnings',
    ])) {
      return SafeCookIntent(type: SafeCookIntentType.readSafetyNotes, rawQuery: rawInput);
    }

    // ------------------------------------------------------------------
    // PRIORITY 3: Start cooking
    // ------------------------------------------------------------------
    if (_matchesAny(q, [
      'start cooking', "let's start", "let's go", "let's begin",
      'begin cooking', 'start this recipe', 'start', 'begin',
      'start the recipe', 'cook this', 'begin the recipe',
      "yes let's start", "yes let's cook", 'okay start',
    ])) {
      return SafeCookIntent(type: SafeCookIntentType.startCooking, rawQuery: rawInput);
    }

    // ------------------------------------------------------------------
    // PRIORITY 4: End cooking
    // ------------------------------------------------------------------
    final isCooking = conversationState == 'cooking' || isCookingActive;
    final isEndCookingUtterance = _matchesAny(q, [
      'stop cooking', 'end cooking', 'finish cooking', 'end session',
      'stop session', "i'm finished cooking", 'i am finished cooking',
      "that's all", 'that is all', 'i am done cooking', "i'm done cooking",
      'quit cooking', 'abort cooking', 'stop the recipe', 'end the cooking',
      'end my cooking', 'finish the cooking', 'stop the cooking', 'that\'s all for cooking',
      'we\'re done', 'we are done', 'done cooking', 'done with cooking', 'cancel cooking',
      'terminate cooking session',
    ]) || (isCooking && _matchesAny(q, [
      'and cooking', 'and my cooking', 'and the cooking', 'hand cooking',
    ]));

    if (isEndCookingUtterance) {
      return SafeCookIntent(type: SafeCookIntentType.endCooking, rawQuery: rawInput);
    }

    // ------------------------------------------------------------------
    // PRIORITY 5: Confirm yes / no
    // (context-free — trust the conversation state to interpret meaning)
    // ------------------------------------------------------------------
    if (_matchesAny(q, [
      'yes', 'yep', 'yeah', 'sure', 'correct', 'ok', 'okay', 'do it',
      'confirm', 'go ahead', 'absolutely', 'of course', 'go for it',
      'sure thing', 'sounds good', "yes i'm ready", 'ready', "i'm ready",
    ])) {
      return SafeCookIntent(type: SafeCookIntentType.confirmYes, rawQuery: rawInput);
    }

    if (_matchesAny(q, [
      'no', 'nope', 'cancel', 'stop that', 'not now', 'never mind',
      'nevermind', 'forget it', 'abort', "don't", 'no thanks',
      'not yet', 'wait',
    ])) {
      return SafeCookIntent(type: SafeCookIntentType.confirmNo, rawQuery: rawInput);
    }

    // ------------------------------------------------------------------
    // PRIORITY 6: Sensor queries
    // ------------------------------------------------------------------
    // Gas queries — covers leak/danger/level phrasing
    if (_matchesAny(q, [
      'gas level', 'how much gas', 'what is the gas', 'check gas',
      'gas reading', 'flame level', 'burner level', 'gas percentage',
      'how high is the gas', 'gas sensor', 'what is the flame',
      'gas leak', 'is there a gas', 'is there gas', 'could there be gas',
      'smell gas', 'gas problem', 'gas danger', 'dangerous gas',
      'is the gas okay', 'is the gas', 'gas okay', 'gas level high', 'gas level low',
      'any gas', 'gas alert', 'is gas safe', 'gas safe',
    ])) {
      return SafeCookIntent(type: SafeCookIntentType.checkGas, rawQuery: rawInput);
    }

    if (q.contains('distance') || q.contains('how far am i') ||
        q.contains('how far') || q.contains('proximity') ||
        q.contains('am i too close') || q.contains('how close') ||
        q.contains('check distance') || q.contains('my distance') ||
        q.contains('stove distance') || q.contains('vessel distance') ||
        q.contains('should i step back') || q.contains('step back') ||
        (q.contains('close') && q.contains('vessel')) ||
        (q.contains('close') && q.contains('stove'))) {
      return SafeCookIntent(type: SafeCookIntentType.checkDistance, rawQuery: rawInput);
    }

    // Safety status — covers "stove dangerous", "am I in danger" etc.
    if (_matchesAny(q, [
      'is it safe', 'am i safe', 'safety status', 'check safety',
      'how is the safety', 'stove safe', 'is everything okay',
      'is it okay', 'any alerts', 'any warnings', 'how safe is it',
      'stove dangerous', 'stove is dangerous', 'is the stove dangerous',
      'is the stove safe', 'is the stove okay', 'stove okay',
      'is this dangerous', 'is this safe', 'am i in danger',
      'is it dangerous', 'should i be worried', 'is cooking safe',
      'is it safe to cook', 'are conditions safe', 'safe to cook',
      'stove not safe', 'not safe', 'danger alert', 'is there danger',
    ])) {
      return SafeCookIntent(type: SafeCookIntentType.checkSafety, rawQuery: rawInput);
    }

    // ------------------------------------------------------------------
    // PRIORITY 7: Cooking time query
    // Only fires if NOT a general cooking question (checked later)
    // ------------------------------------------------------------------
    if (_matchesAny(q, [
      'how long have i been cooking', 'time elapsed', 'cooking time elapsed',
      'how long has it been', 'how many minutes have i cooked',
      'session time', 'session duration',
    ])) {
      return SafeCookIntent(type: SafeCookIntentType.checkTime, rawQuery: rawInput);
    }

    // ------------------------------------------------------------------
    // PRIORITY 8: Bluetooth commands
    // ------------------------------------------------------------------
    if (_matchesAny(q, [
      'is bluetooth connected', 'is the sensor connected', 'sensor status',
      'check connection', 'connection status', 'bluetooth status',
      'is hc05 connected', 'is the stove sensor on', 'are we connected',
      'are you connected', 'is the sensor active', 'am i connected',
      'is hc-05 connected', 'is the stove sensor connected', 'check bluetooth',
      'check the sensor connection',
    ])) {
      return SafeCookIntent(type: SafeCookIntentType.checkConnectionStatus, rawQuery: rawInput);
    }

    if (_matchesAny(q, [
      'connect bluetooth', 'connect to bluetooth', 'connect sensor',
      'connect to sensor', 'connect hc05', 'connect to hc05', 'connect hc 05',
      'connect to hc 05', 'connect to stove', 'pair sensor', 'turn on sensor',
      'enable sensor', 'link sensor', 'connect to hc-05', 'connect to the hc05',
      'connect to the stove sensor', 'connect to the stove', 'connect the sensor',
      'pair the sensor', 'turn on the stove sensor connection',
    ])) {
      return SafeCookIntent(type: SafeCookIntentType.connectBluetooth, rawQuery: rawInput);
    }

    if (_matchesAny(q, [
      'disconnect bluetooth', 'disconnect sensor', 'disconnect hc05',
      'unlink sensor', 'disable sensor', 'turn off sensor', 'disconnect the bluetooth',
      'disconnect the sensor', 'disconnect the stove sensor', 'disconnect hc-05',
    ])) {
      return SafeCookIntent(type: SafeCookIntentType.disconnectBluetooth, rawQuery: rawInput);
    }

    // ------------------------------------------------------------------
    // PRIORITY 9: Explicit web search
    // ------------------------------------------------------------------
    if (q.startsWith('search the web') || q.startsWith('search online') ||
        q.startsWith('find online') || q.startsWith('google') ||
        q.contains('current food safety') || q.contains('look up online')) {
      final webQuery = q
          .replaceFirst(RegExp(r'^search the web (for )?'), '')
          .replaceFirst(RegExp(r'^search online (for )?'), '')
          .replaceFirst(RegExp(r'^google '), '')
          .trim();
      return SafeCookIntent(
        type: SafeCookIntentType.webSearch,
        rawQuery: rawInput,
        entities: {'webQuery': webQuery},
      );
    }

    // ------------------------------------------------------------------
    // PRIORITY 10: General cooking questions (handled by knowledge base)
    // ------------------------------------------------------------------
    if (q.contains('substitute') || q.contains('instead of') ||
        q.contains('replacement for') || q.contains('what can i replace') ||
        (q.contains('replace') && q.contains('with')) ||
        q.contains('how do i') ||
        q.contains('how to boil') || q.contains('how long should i boil') ||
        q.contains('how to chop') || q.contains('how to fry') ||
        q.contains('cooking tip') || q.contains('can i use') ||
        q.contains('what happens if i') || q.contains('is it okay to') ||
        // Method comparison queries
        (q.contains('difference between') && (q.contains('boil') || q.contains('steam') || q.contains('fry') || q.contains('bake') || q.contains('grill'))) ||
        (q.contains('vs') && (q.contains('boil') || q.contains('steam') || q.contains('fry') || q.contains('bake'))) ||
        (q.contains('versus') && (q.contains('boil') || q.contains('steam') || q.contains('fry'))) ||
        (q.contains('healthier') && (q.contains('boil') || q.contains('steam') || q.contains('fry'))) ||
        (q.contains('different') && (q.contains('boil') || q.contains('steam') || q.contains('cook'))) ||
        (q.contains('when should i') && (q.contains('boil') || q.contains('steam') || q.contains('fry') || q.contains('bake'))) ||
        q.contains('cooking method') || q.contains('how is') && q.contains('cooked') ||
        q.contains('what temperature') || q.contains('at what temperature') ||
        q.contains('how long to cook') || q.contains('how long does it take to cook')) {
      return SafeCookIntent(
        type: SafeCookIntentType.cookingQuestion,
        rawQuery: rawInput,
        entities: {'question': q},
      );
    }

    // ------------------------------------------------------------------
    // PRIORITY 11: Recipe selection by ordinal — ONLY valid when
    // conversationState == 'selecting_recipe' to prevent misfire during cooking.
    // ------------------------------------------------------------------
    final isSelectingRecipe = conversationState == 'selecting_recipe';

    if (isSelectingRecipe) {
      // Explicit ordinal selection: "the first one", "number two", "3"
      final ordinalMatch = _extractOrdinalIndex(q);
      if (ordinalMatch >= 0) {
        return SafeCookIntent(
          type: SafeCookIntentType.selectRecipe,
          rawQuery: rawInput,
          entities: {'index': ordinalMatch},
        );
      }
      // "the last one", "that one"
      if (q.contains('last one') || q == 'last') {
        return SafeCookIntent(
          type: SafeCookIntentType.selectRecipe,
          rawQuery: rawInput,
          entities: {'index': -2},
        );
      }
    }

    // ------------------------------------------------------------------
    // PRIORITY 12: Find / search recipes
    // ------------------------------------------------------------------
    final isRecipeSearchPhrase =
        q.contains('find') || q.contains('search') || q.contains('look for') ||
        q.contains('recipe') || q.contains('something with') ||
        q.contains('what can i make') || q.contains('what can i cook') ||
        q.contains('suggest') || q.contains('recommend') ||
        q.contains('give me') || q.contains('show me') ||
        q.contains('what can i') || q.contains('something to cook') ||
        q.contains('what to cook') || q.contains('what should i cook') ||
        q.contains('what to make');

    if (isRecipeSearchPhrase) {
      final entities = _extractRecipeSearchEntities(q);
      return SafeCookIntent(
        type: SafeCookIntentType.findRecipe,
        rawQuery: rawInput,
        entities: entities,
      );
    }

    // ------------------------------------------------------------------
    // PRIORITY 13: Implicit recipe name — the user just said a dish name.
    // This is our last resort before unknown.
    // ------------------------------------------------------------------
    // (Handled in the agent via the recipe index — return unknown here and
    //  let the agent's recipe resolution pipeline take care of it.)

    return SafeCookIntent(type: SafeCookIntentType.unknown, rawQuery: rawInput);
  }

  // -------------------------------------------------------------------------
  // Helpers
  // -------------------------------------------------------------------------

  static bool _matchesAny(String q, List<String> patterns) {
    return patterns.any((p) => q == p || q.startsWith('$p ') || q.endsWith(' $p') || q.contains(' $p '));
  }

  static int _extractOrdinalIndex(String q) {
    if (q == '1' || q.contains(' 1') || q == 'one' || q.contains('first') || q.contains('number one')) return 0;
    if (q == '2' || q.contains(' 2') || q == 'two' || q.contains('second') || q.contains('number two')) return 1;
    if (q == '3' || q.contains(' 3') || q == 'three' || q.contains('third') || q.contains('number three')) return 2;
    if (q == '4' || q.contains(' 4') || q == 'four' || q.contains('fourth') || q.contains('number four')) return 3;
    if (q == '5' || q.contains(' 5') || q == 'five' || q.contains('fifth') || q.contains('number five')) return 4;
    // Number words up to ten
    final numWords = {'six': 5, 'seven': 6, 'eight': 7, 'nine': 8, 'ten': 9};
    for (final entry in numWords.entries) {
      if (q.contains(entry.key)) return entry.value;
    }
    // Bare digits
    final digitMatch = RegExp(r'^\d+$').firstMatch(q.trim());
    if (digitMatch != null) {
      final n = int.tryParse(q.trim());
      if (n != null && n >= 1 && n <= 50) return n - 1;
    }
    return -1;
  }

  static Map<String, dynamic> _extractRecipeSearchEntities(String q) {
    bool vegetarian = q.contains('vegetarian') || q.contains(' veg ') || q == 'veg';
    bool quick = q.contains('quick') || q.contains('fast') || q.contains('easy') ||
                 q.contains('under 30') || q.contains('under 20') || q.contains('under 15');

    // Extract requested count: "two recipes", "3 recipes", etc.
    int count = 0;
    final countWords = {'one': 1, 'two': 2, 'three': 3, 'four': 4, 'five': 5,
                        'six': 6, 'seven': 7, 'eight': 8, 'nine': 9, 'ten': 10};
    final numMatch = RegExp(r'\b(\d+)\b').firstMatch(q);
    if (numMatch != null) {
      count = int.tryParse(numMatch.group(1) ?? '') ?? 0;
    }
    if (count == 0) {
      for (final entry in countWords.entries) {
        if (q.contains(entry.key)) { count = entry.value; break; }
      }
    }

    String ingredient = '';
    const ingredients = [
      'potato', 'onion', 'paneer', 'egg', 'rice', 'noodle', 'chicken',
      'tomato', 'dal', 'lentil', 'peas', 'carrot', 'cauliflower', 'spinach',
      'mushroom', 'bread', 'pasta', 'corn',
    ];
    for (final ing in ingredients) {
      if (q.contains(ing)) {
        ingredient = ing;
        break;
      }
    }

    String category = '';
    const categories = [
      'breakfast', 'lunch', 'dinner', 'snack', 'dessert', 'soup',
      'curry', 'biryani', 'pulao', 'dosa', 'paratha', 'sandwich',
    ];
    for (final cat in categories) {
      if (q.contains(cat)) {
        category = cat;
        break;
      }
    }

    return {
      'vegetarian': vegetarian,
      'quick': quick,
      'ingredient': ingredient,
      'category': category,
      'count': count,          // 0 = no count specified
      'rawText': q,
    };
  }
}
