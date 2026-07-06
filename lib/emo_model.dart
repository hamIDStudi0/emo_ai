// FILE 1: emo_model.dart — Architecture & State Schema
//
// Pure data only. The "brain" here is a classic tabular Q-table: each key
// (a single word, or a "w1|w2" bigram) owns a map of emoji -> score.
// Nothing is pre-seeded — a key's score map starts empty and every entry in
// it is written only by reviewPending() in emo_engine.dart, in response to
// a real Like/Dislike.

/// One row of the Q-table: `key` is a word or a "w1|w2" bigram; `scores`
/// maps an emoji glyph to its learned value for that key; `freq` counts how
/// many times this key has ever been sampled (drives the explore/exploit
/// epsilon — see emo_engine.dart).
class EmoMemoryEntry {
  final String key;
  Map<String, double> scores;
  int freq;

  EmoMemoryEntry(this.key, {Map<String, double>? scores, this.freq = 0}) : scores = scores ?? {};

  factory EmoMemoryEntry.fromJson(String key, Map<String, dynamic> j) => EmoMemoryEntry(
        key,
        scores: (j['scores'] as Map).map((k, v) => MapEntry(k as String, (v as num).toDouble())),
        freq: j['freq'] as int,
      );

  Map<String, dynamic> toJson() => {
        'scores': scores,
        'freq': freq,
      };
}

/// Lifecycle + identity state — no visible-analytics fields here either
/// (see command.md's directive against on-screen numeric readouts).
/// `isBorn` / `name` gate the one-time birthing ritual; `interactionCount`
/// is bookkeeping only.
class EmoState {
  bool isBorn;
  String name;
  int interactionCount;

  EmoState({
    this.isBorn = false,
    this.name = '',
    this.interactionCount = 0,
  });

  factory EmoState.fromJson(Map<String, dynamic> j) => EmoState(
        isBorn: j['isBorn'] as bool,
        name: j['name'] as String,
        interactionCount: j['interactionCount'] as int,
      );

  Map<String, dynamic> toJson() => {
        'isBorn': isBorn,
        'name': name,
        'interactionCount': interactionCount,
      };
}
