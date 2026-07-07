// FILE 1: emo_model.dart — Architecture & State Schema (offline, multi-profile)
//
// Pure data only. The "brain" is a tabular Q-table: each key (a word, or a
// "w1|w2" / "w1|w2|w3" n-gram) owns a map of emoji -> score. Nothing is
// pre-seeded — a key's score map starts empty and every entry in it is
// written only in response to a real Like/Dislike (see emo_engine.dart).
//
// NO hardcoded word lists live here or anywhere else in this app (no
// stopwords, no synonym/antonym dictionary). Anything that looks like
// "this entity understands X" is derived at runtime, purely from the
// statistics of what it has personally experienced — see the comment
// block at the top of emo_engine.dart for exactly how that works and,
// just as importantly, what it honestly does *not* do.

/// One row of the Q-table.
class EmoMemoryEntry {
  final String key;
  Map<String, double> scores;
  int freq;

  EmoMemoryEntry(this.key, {Map<String, double>? scores, this.freq = 0}) : scores = scores ?? {};

  factory EmoMemoryEntry.fromJson(String key, Map<String, dynamic> j) => EmoMemoryEntry(
        key,
        scores: (j['scores'] as Map).map((k, v) => MapEntry(k as String, (v as num).toDouble())),
        freq: j['freq'] as int? ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'scores': scores,
        'freq': freq,
      };
}

/// A single "AI entity" living on this device. Identity is a picked emoji
/// avatar ONLY — deliberately no text name field at all, so the home
/// screen and add-flow can stay 100% language-neutral (icons/emoji only),
/// per the request that anyone regardless of spoken language can use it.
class EmoProfile {
  String id;
  String avatar;
  int interactionCount;
  int createdAtMs;

  /// key -> {emoji -> score}
  Map<String, EmoMemoryEntry> memory;

  /// Co-occurrence counts: token -> {neighborToken -> count}. Built purely
  /// from words the user has actually typed together. This is the entire
  /// substrate the engine uses to make an educated guess about a brand-new
  /// word it has never been rated on, by "borrowing" a hunch from whatever
  /// known words tend to show up in the same sentences as it (distributional
  /// similarity — the closest honest, from-scratch analogue of learning a
  /// synonym without ever being told what a synonym is).
  Map<String, Map<String, int>> cooccurrence;

  EmoProfile({
    required this.id,
    required this.avatar,
    this.interactionCount = 0,
    int? createdAtMs,
    Map<String, EmoMemoryEntry>? memory,
    Map<String, Map<String, int>>? cooccurrence,
  })  : createdAtMs = createdAtMs ?? DateTime.now().millisecondsSinceEpoch,
        memory = memory ?? {},
        cooccurrence = cooccurrence ?? {};

  factory EmoProfile.fresh(String avatar) => EmoProfile(
        id: _randomId(),
        avatar: avatar,
      );

  static String _randomId() {
    final now = DateTime.now().microsecondsSinceEpoch;
    final rnd = (now * 2654435761) & 0x7fffffff;
    return '${now.toRadixString(36)}${rnd.toRadixString(36)}';
  }

  factory EmoProfile.fromJson(Map<String, dynamic> j) => EmoProfile(
        id: j['id'] as String,
        avatar: j['avatar'] as String,
        interactionCount: j['interactionCount'] as int? ?? 0,
        createdAtMs: j['createdAtMs'] as int?,
        memory: (j['memory'] as Map<String, dynamic>? ?? {}).map(
          (k, v) => MapEntry(k, EmoMemoryEntry.fromJson(k, v as Map<String, dynamic>)),
        ),
        cooccurrence: (j['cooccurrence'] as Map<String, dynamic>? ?? {}).map(
          (k, v) => MapEntry(k, (v as Map<String, dynamic>).map((k2, v2) => MapEntry(k2, v2 as int))),
        ),
      );

  Map<String, dynamic> toJson() => {
        // Format marker so import can sanity-check the file is really a
        // .emoai bundle before trying to parse it as one.
        'format': 'emoai.v1',
        'id': id,
        'avatar': avatar,
        'interactionCount': interactionCount,
        'createdAtMs': createdAtMs,
        'memory': memory.map((k, v) => MapEntry(k, v.toJson())),
        'cooccurrence': cooccurrence,
      };
}
