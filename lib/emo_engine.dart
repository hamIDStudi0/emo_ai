// FILE 2: emo_engine.dart
//
// ============================================================================
// VERSI "KOMBINASI PERASAAN" — baca ini dulu.
// ============================================================================
// IndoBERT sekarang dibaca SEMUA skornya (bukan cuma yang tertinggi).
// - Label #1 (tertinggi) & #2 (kedua tertinggi) dibandingkan.
// - closeness = skor#2 / skor#1 (0..1). Makin dekat ke 1, makin ambigu
//   perasaannya (mis. happy 70% vs sadness 50% -> closeness 0.71).
// - closeness dipakai LANGSUNG sebagai peluang memakai kunci GABUNGAN
//   ("happy+sadness") alih-alih kunci TUNGGAL ("happy"). Ini yang bikin
//   persentase itu akhirnya benar-benar berpengaruh ke perilaku, bukan
//   cuma dibuang setelah menentukan siapa juara.
// - Kunci gabungan punya keranjang emoji GABUNGAN (union 2 keranjang) dan
//   Q-table SENDIRI, terpisah dari kunci tunggal — jadi ia bisa belajar
//   "karakter emoji" khusus untuk situasi campur-aduk itu (mis. 🥲 buat
//   "senang campur sedih"), bukan sekadar niru salah satu perasaan mentah.
// - Saat DISLIKE pada kunci tunggal, kalau ada label kedua yang cukup
//   signifikan, engine JUGA memberi nudge kecil ke kunci gabungan untuk
//   emoji yang sama — supaya data "kemungkinan ini sebenarnya campuran"
//   ikut terekam, walau saat itu yang dipakai cuma kunci tunggal.
// - Ini SEMUA tetap statistik/bandit, bukan "AI benar-benar merasa" —
//   efek "punya karakter sendiri" itu murni pola yang menetap dari akumulasi
//   feedback, bukan kesadaran. Saya jujur soal ini supaya ekspektasinya pas.
// ============================================================================

import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'emo_model.dart';
import 'emo_emojis.dart';

const List<String> kEmotionLabels = ['anger', 'fear', 'happy', 'love', 'sadness'];
const double _kSecondaryFloor = 0.15; // di bawah ini, label ke-2 dianggap noise.

class IndoBertClassifier {
  static const _modelUrl =
      'https://api-inference.huggingface.co/models/StevenLimcorn/indonesian-roberta-base-emotion-classifier';
  final String hfToken;
  IndoBertClassifier(this.hfToken);

  /// Mengembalikan SEMUA skor label (label -> 0..1), bukan cuma juaranya.
  /// Gagal/timeout -> map kosong (engine akan jatuh ke 'netral').
  Future<Map<String, double>> classify(String text) async {
    try {
      final resp = await http
          .post(Uri.parse(_modelUrl),
              headers: {'Authorization': 'Bearer $hfToken', 'Content-Type': 'application/json'},
              body: jsonEncode({'inputs': text}))
          .timeout(const Duration(seconds: 20));
      if (resp.statusCode != 200) return {};
      final decoded = jsonDecode(resp.body);
      final List<dynamic> preds = (decoded is List && decoded.isNotEmpty && decoded.first is List)
          ? decoded.first as List<dynamic>
          : (decoded is List ? decoded : []);
      final out = <String, double>{};
      for (final p in preds) {
        final label = (p['label'] as String).toLowerCase();
        if (kEmotionLabels.contains(label)) out[label] = (p['score'] as num).toDouble();
      }
      return out;
    } catch (_) {
      return {};
    }
  }
}

class TursoStore {
  final String databaseUrl;
  final String authToken;
  TursoStore({required this.databaseUrl, required this.authToken});

  Uri get _httpUrl => Uri.parse('https://${databaseUrl.replaceFirst('libsql://', '')}/v2/pipeline');

  Future<List<dynamic>> _pipeline(List<Map<String, dynamic>> statements) async {
    final body = {
      'requests': [...statements.map((s) => {'type': 'execute', 'stmt': s}), {'type': 'close'}]
    };
    final resp = await http
        .post(_httpUrl, headers: {'Authorization': 'Bearer $authToken', 'Content-Type': 'application/json'}, body: jsonEncode(body))
        .timeout(const Duration(seconds: 12));
    if (resp.statusCode != 200) throw Exception('Turso error ${resp.statusCode}: ${resp.body}');
    return (jsonDecode(resp.body)['results'] as List);
  }

  Map<String, dynamic> _t(String v) => {'type': 'text', 'value': v};
  Map<String, dynamic> _f(double v) => {'type': 'float', 'value': v};
  Map<String, dynamic> _i(int v) => {'type': 'integer', 'value': v.toString()};

  Future<void> ensureSchema() async {
    await _pipeline([
      {
        'sql': 'CREATE TABLE IF NOT EXISTS emo_global_scores ('
            'label TEXT NOT NULL, emoji TEXT NOT NULL, score REAL NOT NULL DEFAULT 0, '
            'count INTEGER NOT NULL DEFAULT 0, PRIMARY KEY (label, emoji))'
      },
      {
        'sql': 'CREATE TABLE IF NOT EXISTS emo_reviews ('
            'id INTEGER PRIMARY KEY AUTOINCREMENT, ts INTEGER NOT NULL, label TEXT NOT NULL, '
            'emoji TEXT NOT NULL, liked INTEGER NOT NULL)'
      },
    ]);
  }

  Future<Map<String, EmoLabelEntry>> loadAll() async {
    final result = await _pipeline([
      {'sql': 'SELECT label, emoji, score, count FROM emo_global_scores'},
    ]);
    final rows = (result[0]['response']['result']['rows'] as List);
    final map = <String, EmoLabelEntry>{};
    for (final row in rows) {
      final label = row[0]['value'] as String;
      final entry = map.putIfAbsent(label, () => EmoLabelEntry(label));
      entry.scores[row[1]['value'] as String] = double.parse(row[2]['value'].toString());
      entry.freq += int.parse(row[3]['value'].toString());
    }
    return map;
  }

  Future<void> upsertScore(String label, String emoji, double score, int count) async {
    await _pipeline([
      {
        'sql': 'INSERT INTO emo_global_scores (label, emoji, score, count) VALUES (?, ?, ?, ?) '
            'ON CONFLICT(label, emoji) DO UPDATE SET score = excluded.score, count = excluded.count',
        'args': [_t(label), _t(emoji), _f(score), _i(count)],
      },
    ]);
  }

  Future<void> logReview({required String label, required String emoji, required bool liked}) async {
    await _pipeline([
      {
        'sql': 'INSERT INTO emo_reviews (ts, label, emoji, liked) VALUES (?, ?, ?, ?)',
        'args': [_i(DateTime.now().millisecondsSinceEpoch), _t(label), _t(emoji), _i(liked ? 1 : 0)],
      },
    ]);
  }
}

class EmoChain {
  final String label; // "happy" atau kombinasi "happy+sadness"
  final String emoji;
  final String? secondaryLabel; // label ke-2 signifikan, kalau ada (untuk cross-nudge)
  EmoChain({required this.label, required this.emoji, this.secondaryLabel});
}

class EmoEngine {
  final IndoBertClassifier classifier;
  final TursoStore store;
  final _rng = Random();
  static const double _learningRate = 0.35;
  static const double _crossLearningRate = 0.15; // nudge lebih lemah utk kunci gabungan

  final Map<String, EmoLabelEntry> _memory = {};
  EmoChain? _pending;

  EmoEngine({required this.classifier, required this.store});

  Future<void> init() async {
    await store.ensureSchema();
    _memory.addAll(await store.loadAll());
  }

  /// Nama kunci gabungan selalu diurutkan alfabetis supaya "happy+sadness"
  /// dan "sadness+happy" adalah kunci yang SAMA.
  String _comboKey(String a, String b) {
    final list = [a, b]..sort();
    return list.join('+');
  }

  List<String> _basketFor(String key) {
    if (key.contains('+')) {
      final parts = key.split('+');
      return [...?kBaskets[parts[0]], ...?kBaskets[parts[1]]];
    }
    return kBaskets[key] ?? kNetral;
  }

  String _pickEmoji(String key) {
    final pool = _basketFor(key);
    final entry = _memory.putIfAbsent(key, () => EmoLabelEntry(key));
    final epsilon = (1.0 - entry.freq * 0.03).clamp(0.10, 1.0);

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
        emoji = pool[_rng.nextInt(pool.length)];
      } while (emoji == avoid && pool.length > 1);
    } else {
      emoji = best!.key;
    }
    return emoji;
  }

  Future<EmoChain> reply(String text) async {
    final scores = await classifier.classify(text);
    if (scores.isEmpty) {
      final emoji = _pickEmoji('netral');
      final chain = EmoChain(label: 'netral', emoji: emoji);
      _pending = chain;
      return chain;
    }

    final sorted = scores.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final primary = sorted.first;
    final secondary = sorted.length > 1 ? sorted[1] : null;

    String key = primary.key;
    String? secondaryLabel;
    if (secondary != null && secondary.value >= _kSecondaryFloor) {
      secondaryLabel = secondary.key;
      // closeness = skor#2 / skor#1, LANGSUNG jadi peluang pakai kunci gabungan.
      final closeness = (secondary.value / primary.value).clamp(0.0, 1.0);
      if (_rng.nextDouble() < closeness) {
        key = _comboKey(primary.key, secondary.key);
      }
    }

    final emoji = _pickEmoji(key);
    final chain = EmoChain(label: key, emoji: emoji, secondaryLabel: secondaryLabel);
    _pending = chain;
    return chain;
  }

  Future<void> _applyUpdate(String key, String emoji, double reward, double rate) async {
    final entry = _memory.putIfAbsent(key, () => EmoLabelEntry(key));
    final current = entry.scores[emoji] ?? 0.0;
    final updated = current + rate * (reward - current);
    entry.scores[emoji] = updated;
    entry.freq++;
    await store.upsertScore(key, emoji, updated, entry.freq);
  }

  Future<void> review(bool liked) async {
    final chain = _pending;
    if (chain == null) return;
    final reward = liked ? 1.0 : -1.0;

    await _applyUpdate(chain.label, chain.emoji, reward, _learningRate);

    // Cross-nudge: kalau yang dipakai kunci TUNGGAL tapi ada label kedua
    // signifikan, ikut catat sinyal ini (lebih lemah) ke kunci gabungan —
    // supaya data "mungkin ini sebenarnya campuran" tetap terekam.
    if (!chain.label.contains('+') && chain.secondaryLabel != null) {
      final comboKey = _comboKey(chain.label, chain.secondaryLabel!);
      await _applyUpdate(comboKey, chain.emoji, reward, _crossLearningRate);
    }

    await store.logReview(label: chain.label, emoji: chain.emoji, liked: liked);
    _pending = null;
  }
}
