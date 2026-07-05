// FILE 1: emo_model.dart — Architecture & State Schema
// Zero pre-seeded data. Every field starts neutral and is shaped only by feedback.

/// A single learned word/token. Weights live in [-1.0, 1.0] and map directly
/// onto facial parameters. `links` is the implicit co-occurrence graph used
/// to spread meaning between words that appear together ("synonym mapping").
class EmoWordNode {
  final String word;
  double eyebrows;    // -1 = furrowed/angry, 1 = raised/surprised
  double eyeOpenness; // -1 = squinted, 1 = wide open
  double mouthCurve;  // -1 = frown, 1 = smile
  double colorShift;  // -1 = pale blue (calm/sad), 0 = amber (neutral), 1 = crimson (agitated)
  Map<String, double> answerProb; // {'Ya':.., 'Tidak':.., 'Mungkin':..} sums to ~1.0
  Map<String, double> links;      // other word -> co-occurrence strength
  int freq;

  EmoWordNode(
    this.word, {
    this.eyebrows = 0.0,
    this.eyeOpenness = 0.0,
    this.mouthCurve = 0.0,
    this.colorShift = 0.0,
    Map<String, double>? answerProb,
    Map<String, double>? links,
    this.freq = 0,
  })  : answerProb = answerProb ?? {'Ya': 0.33, 'Tidak': 0.33, 'Mungkin': 0.34},
        links = links ?? {};

  factory EmoWordNode.fromJson(Map<String, dynamic> j) => EmoWordNode(
        j['word'] as String,
        eyebrows: (j['eyebrows'] as num).toDouble(),
        eyeOpenness: (j['eyeOpenness'] as num).toDouble(),
        mouthCurve: (j['mouthCurve'] as num).toDouble(),
        colorShift: (j['colorShift'] as num).toDouble(),
        answerProb: (j['answerProb'] as Map).map(
          (k, v) => MapEntry(k as String, (v as num).toDouble()),
        ),
        links: (j['links'] as Map).map(
          (k, v) => MapEntry(k as String, (v as num).toDouble()),
        ),
        freq: j['freq'] as int,
      );

  Map<String, dynamic> toJson() => {
        'word': word,
        'eyebrows': eyebrows,
        'eyeOpenness': eyeOpenness,
        'mouthCurve': mouthCurve,
        'colorShift': colorShift,
        'answerProb': answerProb,
        'links': links,
        'freq': freq,
      };
}

/// Global emotional homeostasis state of the AI (not tied to any single word).
class EmoState {
  double boredom;     // 0..1, rises with idle/repetitive input
  double stress;      // 0..1, rises on "Tidak" / conflict
  double homeostasis; // 0..1, the equilibrium the AI is trying to hold onto
  int level;
  int interactionCount;

  EmoState({
    this.boredom = 0.0,
    this.stress = 0.0,
    this.homeostasis = 0.5,
    this.level = 1,
    this.interactionCount = 0,
  });

  factory EmoState.fromJson(Map<String, dynamic> j) => EmoState(
        boredom: (j['boredom'] as num).toDouble(),
        stress: (j['stress'] as num).toDouble(),
        homeostasis: (j['homeostasis'] as num).toDouble(),
        level: j['level'] as int,
        interactionCount: j['interactionCount'] as int,
      );

  Map<String, dynamic> toJson() => {
        'boredom': boredom,
        'stress': stress,
        'homeostasis': homeostasis,
        'level': level,
        'interactionCount': interactionCount,
      };
}
