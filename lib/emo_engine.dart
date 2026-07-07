// FILE 2: emo_engine.dart
//
// ============================================================================
// ARSITEKTUR BARU (baca dulu sebelum protes "kok masih ada logika lama")
// ============================================================================
// 1. KONTEKS: dulu engine menebak makna kata mentah sendiri (bandit murni).
//    Sekarang, sebelum menebak, teks pengguna dikirim ke IndoBERT (via
//    Hugging Face Inference API — model publik
//    StevenLimcorn/indonesian-roberta-base-emotion-classifier, 5 label:
//    anger/fear/happy/love/sadness) untuk dideteksi EMOSINYA. IndoBERT yang
//    menangani "paham konteks/sinonim" — bukan lagi statistik co-occurrence
//    buatan sendiri. Ini kenapa masalah "kata mirip tidak dikenali" hilang:
//    IndoBERT sudah dilatih di jutaan kalimat.
//
// 2. Q-TABLE sekarang HANYA sebesar 6 baris (5 label emosi + 'netral' untuk
//    hasil yang confidence-nya rendah), bukan per-kata lagi. Setiap baris
//    tetap belajar emoji mana yang paling disukai untuk emosi itu, dengan
//    algoritma epsilon-greedy yang sama seperti sebelumnya (termasuk
//    perbaikan bug "nempel di emoji yang di-dislike").
//
// 3. SATU AI UNTUK SEMUA ORANG: skor Q-table ini disimpan di Turso (bukan
//    per-perangkat lagi) — semua orang yang pakai app ini menulis & membaca
//    baris yang SAMA. Tidak ada lagi "buat AI baru"/multi-profil.
//
// 4. Konsekuensi jujur: ini butuh internet (2 panggilan API: Hugging Face
//    untuk deteksi emosi, Turso untuk baca/tulis skor). Kemungkinan Play
//    Protect akan menandai app lagi karena ini, seperti sebelum kita bikin
//    versi offline.
// ============================================================================

import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'emo_model.dart';
import 'emo_emojis.dart';

/// Label yang benar-benar dipakai. 'netral' bukan output IndoBERT — dipakai
/// kalau confidence tertinggi dari model di bawah ambang batas, supaya
/// tebakan yang ragu-ragu tidak dipaksa masuk ke salah satu dari 5 emosi.
const List<String> kEmotionLabels = ['anger', 'fear', 'happy', 'love', 'sadness', 'netral'];
const double _kConfidenceThreshold = 0.40;

// ============================================================================
// IndoBERT — sekarang lewat server self-hosted sendiri (bukan Hugging Face
// Inference API lagi), supaya tidak kena rate limit HF. Server ini yang
// menjalankan model, APK cuma manggil endpoint /classify.
// ============================================================================
class IndoBertClassifier {
  final String serverUrl; // contoh: https://emo-ai-server.onrender.com
  IndoBertClassifier(this.serverUrl);

  Future<String> classify(String text) async {
    try {
      final resp = await http
          .post(
            Uri.parse('$serverUrl/classify'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'text': text}),
          )
          // Timeout dilonggarkan karena server bisa "cold start" ~30-60 detik
          // kalau baru bangun dari sleep (walau ada keep-alive, sesekali
          // masih bisa kejadian).
          .timeout(const Duration(seconds: 60));

      if (resp.statusCode != 200) return 'netral';
      final decoded = jsonDecode(resp.body);
      final label = (decoded['label'] as String).toLowerCase();
      final score = (decoded['score'] as num).toDouble();

      if (score < _kConfidenceThreshold) return 'netral';
      return kEmotionLabels.contains(label) ? label : 'netral';
    } catch (_) {
      return 'netral';
    }
  }
}

// ============================================================================
// Turso — satu database bersama untuk SEMUA pengguna (satu AI: emo_ai).
// ============================================================================
class TursoStore {
  final String databaseUrl;
  final String authToken;
  TursoStore({required this.databaseUrl, required this.authToken});

  Uri get _httpUrl {
    final host = databaseUrl.replaceFirst('libsql://', '').replaceFirst('wss://', '');
    return Uri.parse('https://$host/v2/pipeline');
  }

  Future<List<dynamic>> _pipeline(List<Map<String, dynamic>> statements) async {
    final body = {
      'requests': [
        ...statements.map((s) => {'type': 'execute', 'stmt': s}),
        {'type': 'close'},
      ],
    };
    final resp = await http
        .post(_httpUrl, headers: {
          'Authorization': 'Bearer $authToken',
          'Content-Type': 'application/json',
        }, body: jsonEncode(body))
        .timeout(const Duration(seconds: 12));
    if (resp.statusCode != 200) {
      throw Exception('Turso error ${resp.statusCode}: ${resp.body}');
    }
    return (jsonDecode(resp.body)['results'] as List);
  }

  Map<String, dynamic> _textArg(String v) => {'type': 'text', 'value': v};
  Map<String, dynamic> _floatArg(double v) => {'type': 'float', 'value': v};
  Map<String, dynamic> _intArg(int v) => {'type': 'integer', 'value': v.toString()};

  Future<void> ensureSchema() async {
    await _pipeline([
      {
        'sql': 'CREATE TABLE IF NOT EXISTS emo_global_scores ('
            'label TEXT NOT NULL, '
            'emoji TEXT NOT NULL, '
            'score REAL NOT NULL DEFAULT 0, '
            'count INTEGER NOT NULL DEFAULT 0, '
            'PRIMARY KEY (label, emoji))',
      },
      // Log anonim — tidak ada kolom identitas/nama pengguna sama sekali.
      {
        'sql': 'CREATE TABLE IF NOT EXISTS emo_reviews ('
            'id INTEGER PRIMARY KEY AUTOINCREMENT, '
            'ts INTEGER NOT NULL, '
            'label TEXT NOT NULL, '
            'emoji TEXT NOT NULL, '
            'liked INTEGER NOT NULL)',
      },
    ]);
  }

  /// Ambil seluruh skor yang sudah pernah dipelajari (dari SEMUA pengguna)
  /// untuk dimuat ke memori lokal saat aplikasi dibuka.
  Future<Map<String, EmoLabelEntry>> loadAll() async {
    final result = await _pipeline([
      {'sql': 'SELECT label, emoji, score, count FROM emo_global_scores'},
    ]);
    final rows = (result[0]['response']['result']['rows'] as List);
    final map = <String, EmoLabelEntry>{};
    for (final row in rows) {
      final label = row[0]['value'] as String;
      final emoji = row[1]['value'] as String;
      final score = double.parse(row[2]['value'].toString());
      final count = int.parse(row[3]['value'].toString());
      final entry = map.putIfAbsent(label, () => EmoLabelEntry(label));
      entry.scores[emoji] = score;
      entry.freq += count;
    }
    return map;
  }

  Future<void> upsertScore(String label, String emoji, double score, int count) async {
    await _pipeline([
      {
        'sql': 'INSERT INTO emo_global_scores (label, emoji, score, count) VALUES (?, ?, ?, ?) '
            'ON CONFLICT(label, emoji) DO UPDATE SET score = excluded.score, count = excluded.count',
        'args': [_textArg(label), _textArg(emoji), _floatArg(score), _intArg(count)],
      },
    ]);
  }

  Future<void> logReview({required String label, required String emoji, required bool liked}) async {
    await _pipeline([
      {
        'sql': 'INSERT INTO emo_reviews (ts, label, emoji, liked) VALUES (?, ?, ?, ?)',
        'args': [
          _intArg(DateTime.now().millisecondsSinceEpoch),
          _textArg(label),
          _textArg(emoji),
          _intArg(liked ? 1 : 0),
        ],
      },
    ]);
  }
}

class EmoChain {
  final String label;
  final String emoji;
  EmoChain({required this.label, required this.emoji});
}

/// Mesin utama — satu instance dipakai untuk SATU AI bersama (emo_ai).
class EmoEngine {
  final IndoBertClassifier classifier;
  final TursoStore store;
  final _rng = Random();
  static const double _learningRate = 0.35;

  final Map<String, EmoLabelEntry> _memory = {};
  EmoChain? _pending;

  EmoEngine({required this.classifier, required this.store});

  Future<void> init() async {
    await store.ensureSchema();
    final loaded = await store.loadAll();
    _memory.addAll(loaded);
    for (final label in kEmotionLabels) {
      _memory.putIfAbsent(label, () => EmoLabelEntry(label));
    }
  }

  /// Sama seperti versi sebelumnya: kalau skor terbaik yang diketahui untuk
  /// label ini sudah negatif (baru saja di-dislike dan itu satu-satunya
  /// tercatat), JANGAN tetap dieksploitasi — paksa eksplorasi & hindari
  /// memilih ulang emoji yang sama.
  String _pickEmoji(String label) {
    final entry = _memory.putIfAbsent(label, () => EmoLabelEntry(label));
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
        emoji = kEmojiPalette[_rng.nextInt(kEmojiPalette.length)];
      } while (emoji == avoid && kEmojiPalette.length > 1);
    } else {
      emoji = best!.key;
    }
    return emoji;
  }

  /// SATU balasan = SATU emoji (bukan rangkaian lagi).
  Future<EmoChain> reply(String text) async {
    final label = await classifier.classify(text);
    final emoji = _pickEmoji(label);
    final chain = EmoChain(label: label, emoji: emoji);
    _pending = chain;
    return chain;
  }

  Future<void> review(bool liked) async {
    final chain = _pending;
    if (chain == null) return;
    final reward = liked ? 1.0 : -1.0;
    final entry = _memory.putIfAbsent(chain.label, () => EmoLabelEntry(chain.label));
    final current = entry.scores[chain.emoji] ?? 0.0;
    final updated = current + _learningRate * (reward - current);
    entry.scores[chain.emoji] = updated;
    entry.freq++;
    _pending = null;

    // Tulis ke Turso supaya SEMUA pengguna lain langsung ikut belajar dari
    // reaksi ini juga (satu otak bersama).
    await store.upsertScore(chain.label, chain.emoji, updated, entry.freq);
    await store.logReview(label: chain.label, emoji: chain.emoji, liked: liked);
  }
}
