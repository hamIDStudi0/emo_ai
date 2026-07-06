// FILE 2: emo_engine.dart — Cognitive Brain: Bigram Q-Table + Cloud Storage
//
// This replaces the earlier facial-parameter engine with a genuine
// zero-knowledge tabular reinforcement learner, in the spirit of the
// "Zero-Knowledge Emoji Responder" prompt:
//   - Memory is a flat table: key (word or "w1|w2" bigram) -> {emoji: score}.
//   - Every decision is either Eksplorasi Acak (random pick from the full
//     emoji palette) or Eksploitasi Memori (pick the highest-scoring emoji
//     already known for that key), chosen via an epsilon that shrinks the
//     more a key has been seen.
//   - The engine can emit a CHAIN of 1-3 emoji per turn (not just one), and
//     can also self-emit chains with no user input at all (idle "self-talk").
//   - A Like/Dislike review always applies to the *last emitted chain* as a
//     whole, whether that chain was a reply or an idle self-emission.
//
// Storage is 100% cloud: Turso (libSQL) over its documented HTTP pipeline
// API — no local database. See TursoRepository below.
import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'emo_model.dart';
import 'emo_emojis.dart';

/// Fill these via `--dart-define` at build/run time, e.g.:
///   flutter run \
///     --dart-define=TURSO_DATABASE_URL=libsql://emoai-hamidstudi0.aws-ap-northeast-1.turso.io \
///     --dart-define=TURSO_AUTH_TOKEN=eyJhbGciOiJFZERTQSIsInR5cCI6IkpXVCJ9.eyJhIjoicnciLCJpYXQiOjE3ODMzMTA3MzYsImlkIjoiMDE5ZjM1OWEtMjQwMS03MTk2LWE2YjYtNTdmNTNiMzQwNDNmIiwia2lkIjoiRmZuSXlIb293R1pYRlhGc21TNGoyUHZpakNsNTVCcldMQk1DeHVoekRMdyIsInJpZCI6IjRmNzZmZDJlLTc0M2MtNGYwZC04N2I5LWU0ZWQ0MGUwNzcwNCJ9.2ZBdWc9OmcPC8EayxBeJq5EDStllpDcCpHficIxvsNYFAZYfWHk5VFnx75Yijgce-pIbxGdJun_PnEiFmKXDDQ
/// If left empty, the engine falls back to an in-memory repository so the
/// app still runs (without persistence) rather than crashing.
class TursoConfig {
  static const databaseUrl = String.fromEnvironment('TURSO_DATABASE_URL');
  static const authToken = String.fromEnvironment('TURSO_AUTH_TOKEN');
  static bool get isConfigured => databaseUrl.isNotEmpty && authToken.isNotEmpty;
}

abstract class EmoRepository {
  Future<void> init();
  Future<Map<String, EmoMemoryEntry>> loadMemory();
  Future<void> saveMemory(Map<String, EmoMemoryEntry> memory);
  Future<EmoState?> loadState();
  Future<void> saveState(EmoState state);

  /// Mencatat SATU baris ulasan (Like/Dislike) apa adanya — tanpa nama,
  /// tanpa identitas pengguna. Ini terpisah dari `saveMemory` (yang cuma
  /// simpan skor teragregasi): tabel ini adalah log historis mentah supaya
  /// tren belajar bisa dianalisis nanti (kapan disukai, kapan tidak, untuk
  /// kata/emoji apa).
  Future<void> logReview({
    required bool liked,
    required List<String> keys,
    required List<String> emojis,
    required bool isIdle,
  });
}

/// Cloud persistence via Turso's documented SQL-over-HTTP pipeline
/// (`POST {databaseUrl}/v2/pipeline`, Hrana-style typed args/rows):
/// https://docs.turso.tech/sdk/http/reference
class TursoRepository implements EmoRepository {
  final String databaseUrl;
  final String authToken;

  TursoRepository({required this.databaseUrl, required this.authToken});

  Uri get _endpoint => Uri.parse('$databaseUrl/v2/pipeline');

  Future<Map<String, dynamic>> _pipeline(List<Map<String, dynamic>> statements) async {
    final res = await http.post(
      _endpoint,
      headers: {
        'Authorization': 'Bearer $authToken',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'requests': [
          for (final s in statements) {'type': 'execute', 'stmt': s},
          {'type': 'close'},
        ],
      }),
    );
    if (res.statusCode != 200) {
      throw Exception('Turso HTTP ${res.statusCode}: ${res.body}');
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Map<String, dynamic> _textArg(String v) => {'type': 'text', 'value': v};
  Map<String, dynamic> _intArg(int v) => {'type': 'integer', 'value': v.toString()};

  /// Unwraps Hrana's typed cell ({"type": "...", "value": "..."}) to a plain
  /// Dart value for the columns we actually use (all TEXT/INTEGER).
  dynamic _cell(dynamic raw) {
    if (raw is Map && raw.containsKey('value')) return raw['value'];
    return raw;
  }

  List<List<dynamic>> _rowsOf(Map<String, dynamic> data, int requestIndex) {
    final results = data['results'] as List;
    final entry = results[requestIndex] as Map<String, dynamic>;
    if (entry['type'] != 'ok') return [];
    final response = entry['response'] as Map<String, dynamic>;
    final result = response['result'] as Map<String, dynamic>?;
    if (result == null) return [];
    final rows = result['rows'] as List? ?? [];
    return rows.map((r) => (r as List).map(_cell).toList()).toList();
  }

  @override
  Future<void> init() async {
    await _pipeline([
      {
        'sql': 'CREATE TABLE IF NOT EXISTS emo_memory ('
            'key TEXT PRIMARY KEY, scores TEXT NOT NULL, freq INTEGER NOT NULL DEFAULT 0)',
      },
      {
        'sql': 'CREATE TABLE IF NOT EXISTS emo_state ('
            'id INTEGER PRIMARY KEY CHECK (id = 1), '
            'is_born INTEGER NOT NULL DEFAULT 0, '
            'name TEXT NOT NULL DEFAULT \'\', '
            'interaction_count INTEGER NOT NULL DEFAULT 0)',
      },
      // Log ulasan mentah — TIDAK ADA kolom nama/identitas pengguna sama
      // sekali, sesuai permintaan: hanya jejak anonim dari respon + ulasan.
      {
        'sql': 'CREATE TABLE IF NOT EXISTS emo_reviews ('
            'id INTEGER PRIMARY KEY AUTOINCREMENT, '
            'ts INTEGER NOT NULL, '
            'liked INTEGER NOT NULL, '
            'is_idle INTEGER NOT NULL, '
            'keys_json TEXT NOT NULL, '
            'emojis_json TEXT NOT NULL)',
      },
    ]);
  }

  @override
  Future<Map<String, EmoMemoryEntry>> loadMemory() async {
    final data = await _pipeline([
      {'sql': 'SELECT key, scores, freq FROM emo_memory'},
    ]);
    final rows = _rowsOf(data, 0);
    final result = <String, EmoMemoryEntry>{};
    for (final row in rows) {
      final key = row[0] as String;
      final scores = jsonDecode(row[1] as String) as Map<String, dynamic>;
      final freq = int.parse(row[2].toString());
      result[key] = EmoMemoryEntry.fromJson(key, {'scores': scores, 'freq': freq});
    }
    return result;
  }

  @override
  Future<void> saveMemory(Map<String, EmoMemoryEntry> memory) async {
    if (memory.isEmpty) return;
    final statements = memory.values
        .map((e) => {
              'sql': 'INSERT INTO emo_memory (key, scores, freq) VALUES (?, ?, ?) '
                  'ON CONFLICT(key) DO UPDATE SET scores = excluded.scores, freq = excluded.freq',
              'args': [_textArg(e.key), _textArg(jsonEncode(e.scores)), _intArg(e.freq)],
            })
        .toList();
    await _pipeline(statements);
  }

  @override
  Future<EmoState?> loadState() async {
    final data = await _pipeline([
      {'sql': 'SELECT is_born, name, interaction_count FROM emo_state WHERE id = 1'},
    ]);
    final rows = _rowsOf(data, 0);
    if (rows.isEmpty) return null;
    final row = rows.first;
    return EmoState(
      isBorn: row[0].toString() == '1',
      name: row[1] as String,
      interactionCount: int.parse(row[2].toString()),
    );
  }

  @override
  Future<void> saveState(EmoState state) async {
    await _pipeline([
      {
        'sql': 'INSERT INTO emo_state (id, is_born, name, interaction_count) VALUES (1, ?, ?, ?) '
            'ON CONFLICT(id) DO UPDATE SET is_born = excluded.is_born, name = excluded.name, '
            'interaction_count = excluded.interaction_count',
        'args': [_intArg(state.isBorn ? 1 : 0), _textArg(state.name), _intArg(state.interactionCount)],
      },
    ]);
  }

  @override
  Future<void> logReview({
    required bool liked,
    required List<String> keys,
    required List<String> emojis,
    required bool isIdle,
  }) async {
    await _pipeline([
      {
        'sql': 'INSERT INTO emo_reviews (ts, liked, is_idle, keys_json, emojis_json) '
            'VALUES (?, ?, ?, ?, ?)',
        'args': [
          _intArg(DateTime.now().millisecondsSinceEpoch),
          _intArg(liked ? 1 : 0),
          _intArg(isIdle ? 1 : 0),
          _textArg(jsonEncode(keys)),
          _textArg(jsonEncode(emojis)),
        ],
      },
    ]);
  }
}

/// Safety net so the app still runs (without persistence) if Turso isn't
/// configured yet or a request fails — never crashes on missing cloud config.
class InMemoryRepository implements EmoRepository {
  final Map<String, EmoMemoryEntry> _memory = {};
  EmoState? _state;

  @override
  Future<void> init() async {}

  @override
  Future<Map<String, EmoMemoryEntry>> loadMemory() async => _memory;

  @override
  Future<void> saveMemory(Map<String, EmoMemoryEntry> memory) async {
    _memory
      ..clear()
      ..addAll(memory);
  }

  @override
  Future<EmoState?> loadState() async => _state;

  @override
  Future<void> saveState(EmoState state) async => _state = state;

  final List<Map<String, dynamic>> _reviewLog = [];

  @override
  Future<void> logReview({
    required bool liked,
    required List<String> keys,
    required List<String> emojis,
    required bool isIdle,
  }) async {
    _reviewLog.add({
      'ts': DateTime.now().millisecondsSinceEpoch,
      'liked': liked,
      'isIdle': isIdle,
      'keys': keys,
      'emojis': emojis,
    });
  }
}

/// One emitted turn: the emoji glyphs shown, the memory keys that produced
/// them (parallel list, same length), and whether this was an idle
/// self-emission rather than a reply to user text.
class EmoChain {
  final List<String> emojis;
  final List<String> keys;
  final bool isIdle;
  const EmoChain({required this.emojis, required this.keys, required this.isIdle});
}

class EmoEngine {
  final Map<String, EmoMemoryEntry> _memory = {};
  EmoState state = EmoState();
  final EmoRepository repo;
  final Random _rng = Random();

  /// Q-learning update rate: how far a Like/Dislike moves a key/emoji score
  /// toward the +1 / -1 target in one shot. Kept moderate (not instant, not
  /// glacial) since rewards here are already a clean +1/-1 signal rather
  /// than a whole profile to blend.
  static const double _learningRate = 0.25;

  EmoChain? _pending;
  EmoChain? get pending => _pending;

  EmoEngine(this.repo);

  Future<void> init() async {
    await repo.init();
    _memory.addAll(await repo.loadMemory());
    final s = await repo.loadState();
    if (s != null) state = s;
  }

  Future<void> persist() async {
    await repo.saveMemory(_memory);
    await repo.saveState(state);
  }

  /// Menandai entitas sebagai "lahir" secara otomatis, TANPA meminta nama
  /// apa pun. `registerName` di bawah masih tersedia kalau suatu saat mau
  /// dipakai lagi secara opsional, tapi jalur utama tidak memanggilnya lagi.
  Future<void> autoBornIfNeeded() async {
    if (state.isBorn) return;
    state.isBorn = true;
    await persist();
  }

  Future<void> registerName(String name) async {
    state.isBorn = true;
    state.name = name;
    await persist();
  }

  List<String> tokenize(String text) => text
      .toLowerCase()
      .split(RegExp(r'[^a-z0-9à-ÿ]+'))
      .where((t) => t.isNotEmpty)
      .toList();

  /// Kata hubung/fungsi Indonesia yang paling umum — bobotnya sengaja
  /// direndahkan supaya "kata isi" (kata yang benar-benar membawa makna/
  /// perasaan, misalnya "bahagia", "sedih", "capek") yang lebih sering jadi
  /// kunci pemilihan emoji, bukan "yang", "dan", "di", dst. Ini bukan kamus
  /// makna (engine tetap zero-knowledge soal EMOJI apa yang cocok), hanya
  /// heuristik tata-bahasa ringan untuk tahu kata mana yang "penting".
  static const Set<String> _fungsi = {
    'yang', 'dan', 'di', 'ke', 'dari', 'itu', 'ini', 'ada', 'akan', 'juga',
    'saya', 'aku', 'kamu', 'kita', 'kami', 'dengan', 'untuk', 'pada', 'atau',
    'tidak', 'saja', 'sudah', 'belum', 'masih', 'lagi', 'kok', 'sih', 'deh',
    'nya', 'apa', 'ya', 'aja', 'gitu', 'gak', 'ga', 'the', 'a', 'an', 'is',
    'am', 'are', 'to', 'of', 'in', 'on',
  };

  /// Memecah kalimat jadi unigram + bigram + trigram, lalu memberi BOBOT
  /// tiap kunci: kata isi > kata fungsi, dan frasa (bigram/trigram) > kata
  /// tunggal karena membawa lebih banyak konteks. Kunci dengan bobot lebih
  /// besar lebih sering dipilih untuk menghasilkan emoji — jadi kalimat
  /// pendek pun bisa "dirangkai" maknanya dengan cepat tanpa perlu kamus
  /// makna dari nol.
  List<MapEntry<String, int>> _buildWeightedKeys(List<String> tokens) {
    final entries = <MapEntry<String, int>>[];
    for (var i = 0; i < tokens.length; i++) {
      final isFungsi = _fungsi.contains(tokens[i]);
      entries.add(MapEntry(tokens[i], isFungsi ? 1 : 3));
      if (i + 1 < tokens.length) {
        entries.add(MapEntry('${tokens[i]}|${tokens[i + 1]}', 4));
      }
      if (i + 2 < tokens.length) {
        entries.add(MapEntry('${tokens[i]}|${tokens[i + 1]}|${tokens[i + 2]}', 6));
      }
    }
    return entries;
  }

  String _weightedPickKey(List<MapEntry<String, int>> weighted) {
    final total = weighted.fold<int>(0, (sum, e) => sum + e.value);
    var roll = _rng.nextInt(total);
    for (final e in weighted) {
      if (roll < e.value) return e.key;
      roll -= e.value;
    }
    return weighted.last.key;
  }

  /// Epsilon-greedy pick for a single key: Eksplorasi Acak vs Eksploitasi
  /// Memori. Epsilon starts at 1.0 (fully random — zero knowledge) and
  /// shrinks toward a small floor as the key accumulates exposure.
  ///
  /// PERBAIKAN BUG: sebelumnya, kalau satu-satunya emoji yang pernah dicoba
  /// untuk sebuah kata itu skornya sudah NEGATIF (pernah di-dislike), fungsi
  /// `reduce()` tetap memilih dia lagi karena tidak ada pembanding lain di
  /// map — jadi ia "nempel" di emoji yang jelas-jelas ditolak. Sekarang:
  /// kalau skor terbaik yang diketahui untuk kata itu sudah di bawah 0,
  /// engine dipaksa Eksplorasi Acak (bukan tetap Eksploitasi skor negatif),
  /// dan emoji yang baru saja di-dislike untuk kata itu dihindari supaya
  /// tidak langsung terpilih ulang secara kebetulan.
  String _pickEmoji(String key) {
    final entry = _memory.putIfAbsent(key, () => EmoMemoryEntry(key));
    final epsilon = (1.0 - entry.freq * 0.05).clamp(0.08, 1.0);

    MapEntry<String, double>? best;
    if (entry.scores.isNotEmpty) {
      best = entry.scores.entries.reduce((a, b) => a.value >= b.value ? a : b);
    }
    final bestIsDisliked = best != null && best.value < 0;
    final shouldExplore = best == null || bestIsDisliked || _rng.nextDouble() < epsilon;

    String emoji;
    if (shouldExplore) {
      final avoid = bestIsDisliked ? best!.key : null;
      do {
        emoji = kEmojiPalette[_rng.nextInt(kEmojiPalette.length)];
      } while (emoji == avoid && kEmojiPalette.length > 1);
    } else {
      emoji = best!.key;
    }
    entry.freq++;
    return emoji;
  }

  /// Emits a chain of 1-3 emoji in reply to user text. The chain (and the
  /// keys that produced it) is kept as `_pending` until the UI reports a
  /// Like/Dislike, or until it's overwritten by the next chain.
  EmoChain reply(String text) {
    final tokens = tokenize(text);
    var weighted = _buildWeightedKeys(tokens);
    if (weighted.isEmpty) weighted = [const MapEntry('_neutral_', 1)];

    final length = 1 + _rng.nextInt(3);
    final emojis = <String>[];
    final usedKeys = <String>[];
    for (var i = 0; i < length; i++) {
      final key = _weightedPickKey(weighted);
      emojis.add(_pickEmoji(key));
      usedKeys.add(key);
    }

    state.interactionCount++;
    _pending = EmoChain(emojis: emojis, keys: usedKeys, isIdle: false);
    return _pending!;
  }

  /// Self-emission with no user input: while "left alone", the entity keeps
  /// trying other responses on its own, mostly by revisiting keys it
  /// already has some memory of (so idle chatter still feels connected to
  /// what it's learned) with occasional fresh exploration.
  EmoChain autonomous() {
    final knownKeys = _memory.keys.toList();
    final length = 1 + _rng.nextInt(2);
    final emojis = <String>[];
    final usedKeys = <String>[];
    for (var i = 0; i < length; i++) {
      final key = knownKeys.isNotEmpty && _rng.nextDouble() < 0.7
          ? knownKeys[_rng.nextInt(knownKeys.length)]
          : '_idle_${_rng.nextInt(99999)}';
      emojis.add(_pickEmoji(key));
      usedKeys.add(key);
    }
    _pending = EmoChain(emojis: emojis, keys: usedKeys, isIdle: true);
    return _pending!;
  }

  /// Applies a Like/Dislike to the last emitted chain as a whole — this is
  /// valid whether that chain was a reply or an idle self-emission, exactly
  /// like the spec calls for ("walau respon itu bersifat menunggu ... tetap
  /// bisa mengulas").
  void review(bool liked) {
    final chain = _pending;
    if (chain == null) return;
    final reward = liked ? 1.0 : -1.0;
    for (var i = 0; i < chain.keys.length; i++) {
      final entry = _memory.putIfAbsent(chain.keys[i], () => EmoMemoryEntry(chain.keys[i]));
      final emoji = chain.emojis[i];
      final current = entry.scores[emoji] ?? 0.0;
      entry.scores[emoji] = current + _learningRate * (reward - current);
    }
    _pending = null;
    persist();
    // Log baris ulasan mentah — anonim, tanpa nama/identitas — sebagai
    // riwayat terpisah dari skor teragregasi, agar bisa dianalisis nanti.
    repo.logReview(liked: liked, keys: chain.keys, emojis: chain.emojis, isIdle: chain.isIdle);
  }
}
