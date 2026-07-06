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

  /// Unigrams + consecutive bigrams — the "Tabel Ingatan" is keyed on both,
  /// so the engine can react to a single word as well as short phrases.
  List<String> _buildKeys(List<String> tokens) {
    final keys = <String>[];
    for (var i = 0; i < tokens.length; i++) {
      keys.add(tokens[i]);
      if (i + 1 < tokens.length) keys.add('${tokens[i]}|${tokens[i + 1]}');
    }
    return keys;
  }

  /// Epsilon-greedy pick for a single key: Eksplorasi Acak vs Eksploitasi
  /// Memori. Epsilon starts at 1.0 (fully random — zero knowledge) and
  /// shrinks toward a small floor as the key accumulates exposure.
  String _pickEmoji(String key) {
    final entry = _memory.putIfAbsent(key, () => EmoMemoryEntry(key));
    final epsilon = (1.0 - entry.freq * 0.05).clamp(0.08, 1.0);
    String emoji;
    if (entry.scores.isEmpty || _rng.nextDouble() < epsilon) {
      emoji = kEmojiPalette[_rng.nextInt(kEmojiPalette.length)];
    } else {
      emoji = entry.scores.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
    }
    entry.freq++;
    return emoji;
  }

  /// Emits a chain of 1-3 emoji in reply to user text. The chain (and the
  /// keys that produced it) is kept as `_pending` until the UI reports a
  /// Like/Dislike, or until it's overwritten by the next chain.
  EmoChain reply(String text) {
    final tokens = tokenize(text);
    final keys = _buildKeys(tokens);
    if (keys.isEmpty) keys.add('_neutral_');

    final length = 1 + _rng.nextInt(3);
    final emojis = <String>[];
    final usedKeys = <String>[];
    for (var i = 0; i < length; i++) {
      final key = keys[_rng.nextInt(keys.length)];
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
  }
}
