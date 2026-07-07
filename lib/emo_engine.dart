// FILE 2: emo_engine.dart — 100% OFFLINE learning core.
//
// ============================================================================
// APA YANG BENAR-BENAR DILAKUKAN DI FILE INI (baca ini dulu sebelum protes
// "kok masih ada daftar kata" — TIDAK ADA daftar kata di file ini sama sekali)
// ============================================================================
//
// 1. TIDAK ADA jaringan/HTTP/database eksternal apa pun. Semua data hidup di
//    satu file `.emoai` (JSON) di penyimpanan lokal perangkat. Ini alasan
//    teknis kenapa Google Play Protect biasanya lebih tenang: tidak ada
//    permission INTERNET yang dipakai untuk mengirim data ke server pihak
//    ketiga sama sekali — app ini secara harfiah tidak tahu cara connect ke
//    internet.
//
// 2. TIDAK ADA daftar stopword/kata-hubung, TIDAK ADA kamus sinonim/antonim
//    yang ditulis manusia. Setiap kata (dan setiap bigram/trigram) mulai
//    dengan bobot yang SAMA PERSIS — nol pengetahuan. Yang membuat satu kata
//    terasa "lebih penting" daripada kata lain nantinya adalah murni angka
//    yang lahir dari feedback like/dislike yang pernah ia terima untuk kata
//    itu (lihat `_informativeness`). Kata yang jarang mendapat reaksi
//    konsisten akan tetap punya bobot mendekati baseline — persis seperti
//    kata hubung "dan/atau/ya" akan berperilaku, TAPI itu kesimpulan yang
//    ia sampai sendiri dari data, bukan aturan yang saya tulis untuknya.
//
// 3. "Memahami sinonim/kata mirip dengan sendirinya": diimplementasikan
//    sebagai model *distributional* yang sangat klasik dalam NLP —
//    "you shall know a word by the company it keeps". Setiap kali dua kata
//    muncul berdekatan dalam satu kalimat, `cooccurrence` mencatatnya. Saat
//    entitas ini bertemu kata yang BELUM PERNAH dinilai sama sekali, ia
//    menengok kata-kata lain yang paling sering muncul berbarengan dengan
//    kata baru itu di masa lalu, lalu "meminjam" kecenderungan emoji dari
//    kata-kata tetangga itu sebagai firasat awal (`_borrowedGuess`). Itulah
//    cara paling jujur untuk mendapatkan efek "seolah tahu kata mirip"
//    tanpa pernah diberi tahu definisi kata apa pun.
//
// 4. Yang TIDAK dilakukan (supaya tidak menjanjikan sesuatu yang palsu):
//    ini TIDAK menulis ulang kodenya sendiri, TIDAK punya language model,
//    TIDAK benar-benar "mengerti" bahasa Indonesia. Ia cuma bandit/tabel
//    Q-learning + statistik co-occurrence sederhana. Efeknya BISA terasa
//    seperti belajar makna dari nol — tapi secara jujur, itu tetap statistik,
//    bukan pemahaman.
// ============================================================================

import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:path_provider/path_provider.dart';
import 'emo_model.dart';
import 'emo_emojis.dart';

class EmoChain {
  final List<String> keys;
  final List<String> emojis;
  final bool isIdle;
  EmoChain({required this.keys, required this.emojis, this.isIdle = false});
}

/// Mengurus daftar profil (banyak "AI" dalam satu perangkat) di penyimpanan
/// lokal — direktori `<app-documents>/profiles/<id>.emoai`. Setiap file
/// adalah JSON valid dan sekaligus format export/import (`.emoai`).
class ProfileStore {
  static Future<Directory> _dir() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/profiles');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  static Future<File> fileFor(String id) async {
    final dir = await _dir();
    return File('${dir.path}/$id.emoai');
  }

  /// Mengembalikan semua profil yang tersimpan di perangkat ini, diurutkan
  /// dari yang terbaru dibuat.
  static Future<List<EmoProfile>> listProfiles() async {
    final dir = await _dir();
    final files = dir.listSync().whereType<File>().where((f) => f.path.endsWith('.emoai'));
    final profiles = <EmoProfile>[];
    for (final f in files) {
      try {
        final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
        profiles.add(EmoProfile.fromJson(j));
      } catch (_) {
        // File korup/bukan format emoai — lewati diam-diam.
      }
    }
    profiles.sort((a, b) => b.createdAtMs.compareTo(a.createdAtMs));
    return profiles;
  }

  static Future<void> save(EmoProfile p) async {
    final f = await fileFor(p.id);
    await f.writeAsString(jsonEncode(p.toJson()));
  }

  static Future<void> delete(String id) async {
    final f = await fileFor(id);
    if (await f.exists()) await f.delete();
  }

  static Future<EmoProfile> createNew(String avatar) async {
    final p = EmoProfile.fresh(avatar);
    await save(p);
    return p;
  }

  /// Mengimpor bytes file `.emoai` yang dipilih pengguna. ID diregenerasi
  /// supaya tidak pernah bentrok dengan profil yang sudah ada di perangkat
  /// ini, sementara avatar + seluruh memori/cooccurrence tetap dipertahankan
  /// apa adanya.
  static Future<EmoProfile> importFromBytes(List<int> bytes) async {
    final j = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    if (j['format'] != 'emoai.v1') {
      throw const FormatException('Bukan file .emoai yang valid');
    }
    final imported = EmoProfile.fromJson(j);
    final fresh = EmoProfile(
      id: EmoProfile.fresh(imported.avatar).id,
      avatar: imported.avatar,
      interactionCount: imported.interactionCount,
      memory: imported.memory,
      cooccurrence: imported.cooccurrence,
    );
    await save(fresh);
    return fresh;
  }

  /// Menyiapkan bytes siap-tulis untuk export (dipakai bareng file_picker's
  /// saveFile di layer UI).
  static List<int> exportBytes(EmoProfile p) => utf8.encode(jsonEncode(p.toJson()));
}

/// Mesin belajar untuk SATU profil yang sedang aktif dibuka.
class EmoEngine {
  final EmoProfile profile;
  final _rng = Random();
  static const double _learningRate = 0.35;
  EmoChain? _pending;

  EmoEngine(this.profile);

  Future<void> persist() => ProfileStore.save(profile);

  List<String> tokenize(String text) => text
      .toLowerCase()
      .split(RegExp(r'[^a-z0-9à-ÿ]+'))
      .where((t) => t.isNotEmpty)
      .toList();

  /// Bobot "seberapa informatif" sebuah kunci (kata/frasa) — TANPA daftar
  /// kata apa pun. Kunci yang belum pernah dinilai mendapat bobot dasar
  /// (zero-knowledge). Kunci yang sudah pernah dinilai mendapat bobot
  /// tambahan sebanding dengan seberapa KUAT/KONSISTEN reaksi yang pernah
  /// diterimanya — kata yang reaksinya campur-aduk (mendekati netral)
  /// otomatis tetap berbobot rendah, persis seperti efek yang biasanya
  /// dicapai dictionary stopword, tapi di sini murni hasil pengalaman.
  double _informativeness(String key) {
    final entry = profile.memory[key];
    if (entry == null || entry.scores.isEmpty) return 1.0;
    final maxAbs = entry.scores.values.map((v) => v.abs()).reduce(max);
    return 1.0 + maxAbs * 3.0;
  }

  List<MapEntry<String, int>> _buildWeightedKeys(List<String> tokens) {
    final raw = <String>[];
    for (var i = 0; i < tokens.length; i++) {
      raw.add(tokens[i]);
      if (i + 1 < tokens.length) raw.add('${tokens[i]}|${tokens[i + 1]}');
      if (i + 2 < tokens.length) raw.add('${tokens[i]}|${tokens[i + 1]}|${tokens[i + 2]}');
    }
    // Bobot integer (dibulatkan) sebanding dengan informativeness yang
    // seluruhnya berasal dari _informativeness (pengalaman), bukan dari
    // jenis n-gram-nya — bigram/trigram tidak diistimewakan begitu saja.
    return raw.map((k) => MapEntry(k, (10 * _informativeness(k)).round())).toList();
  }

  String _weightedPickKey(List<MapEntry<String, int>> weighted) {
    final total = weighted.fold<int>(0, (sum, e) => sum + e.value);
    if (total <= 0) return weighted[_rng.nextInt(weighted.length)].key;
    var roll = _rng.nextInt(total);
    for (final e in weighted) {
      if (roll < e.value) return e.key;
      roll -= e.value;
    }
    return weighted.last.key;
  }

  /// Mencatat co-occurrence murni dari kata-kata yang benar-benar muncul
  /// berbarengan dalam satu kalimat — ini satu-satunya "pengetahuan bahasa"
  /// yang pernah dipegang entitas ini, dan seluruhnya berasal dari apa yang
  /// diketik pengguna sendiri.
  void _recordCooccurrence(List<String> tokens) {
    for (var i = 0; i < tokens.length; i++) {
      for (var j = 0; j < tokens.length; j++) {
        if (i == j) continue;
        final a = tokens[i], b = tokens[j];
        final m = profile.cooccurrence.putIfAbsent(a, () => {});
        m[b] = (m[b] ?? 0) + 1;
      }
    }
  }

  /// Firasat awal untuk kata yang BELUM PERNAH dinilai: tengok tetangga
  /// co-occurrence yang paling sering muncul bersamanya, ambil skor emoji
  /// yang sudah dipelajari untuk tetangga2 itu, gabungkan berbobot jumlah
  /// kemunculan bersama. Efeknya: kata baru yang sering nongol di kalimat
  /// yang sama dengan kata yang sudah kuat asosiasinya, "mewarisi" sedikit
  /// kecenderungan itu — analog paling jujur dari "mengerti kata mirip".
  MapEntry<String, double>? _borrowedGuess(String key) {
    final neighbors = profile.cooccurrence[key];
    if (neighbors == null || neighbors.isEmpty) return null;
    final sorted = neighbors.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final blended = <String, double>{};
    var totalWeight = 0.0;
    for (final n in sorted.take(5)) {
      final neighborEntry = profile.memory[n.key];
      if (neighborEntry == null || neighborEntry.scores.isEmpty) continue;
      final w = n.value.toDouble();
      neighborEntry.scores.forEach((emoji, score) {
        blended[emoji] = (blended[emoji] ?? 0) + score * w;
      });
      totalWeight += w;
    }
    if (totalWeight == 0 || blended.isEmpty) return null;
    blended.updateAll((k, v) => v / totalWeight);
    final best = blended.entries.reduce((a, b) => a.value >= b.value ? a : b);
    // Hanya jadi firasat kalau cukup meyakinkan (bukan noise kecil).
    if (best.value.abs() < 0.15) return null;
    return best;
  }

  /// Epsilon-greedy pick, dengan dua perbaikan penting:
  /// (a) kalau skor terbaik yang diketahui untuk kunci ini sudah negatif
  ///     (pernah di-dislike dan itu satu-satunya yang tercatat), JANGAN
  ///     tetap dieksploitasi — paksa eksplorasi & hindari memilih ulang
  ///     emoji yang sama persis.
  /// (b) kalau kunci ini benar-benar baru (belum pernah dinilai), coba dulu
  ///     firasat dari `_borrowedGuess` (distributional) sebelum jatuh ke
  ///     eksplorasi acak murni.
  String _pickEmoji(String key) {
    final entry = profile.memory.putIfAbsent(key, () => EmoMemoryEntry(key));
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
      final guess = entry.scores.isEmpty ? _borrowedGuess(key) : null;
      if (guess != null && _rng.nextDouble() < 0.5) {
        emoji = guess.key;
      } else {
        do {
          emoji = kEmojiPalette[_rng.nextInt(kEmojiPalette.length)];
        } while (emoji == avoid && kEmojiPalette.length > 1);
      }
    } else {
      emoji = best!.key;
    }
    entry.freq++;
    return emoji;
  }

  EmoChain reply(String text) {
    final tokens = tokenize(text);
    _recordCooccurrence(tokens);
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
    profile.interactionCount++;
    final chain = EmoChain(keys: usedKeys, emojis: emojis);
    _pending = chain;
    return chain;
  }

  /// Reaksi otonom/idle — dipakai layar UI untuk "gumaman" spontan berbasis
  /// kunci yang sudah pernah ada di memori (tanpa input baru dari pengguna).
  EmoChain autonomous() {
    if (profile.memory.isEmpty) {
      final emoji = kEmojiPalette[_rng.nextInt(kEmojiPalette.length)];
      final chain = EmoChain(keys: const ['_idle_'], emojis: [emoji], isIdle: true);
      _pending = chain;
      return chain;
    }
    final keys = profile.memory.keys.toList();
    final length = 1 + _rng.nextInt(2);
    final emojis = <String>[];
    final usedKeys = <String>[];
    for (var i = 0; i < length; i++) {
      final key = keys[_rng.nextInt(keys.length)];
      emojis.add(_pickEmoji(key));
      usedKeys.add(key);
    }
    final chain = EmoChain(keys: usedKeys, emojis: emojis, isIdle: true);
    _pending = chain;
    return chain;
  }

  void review(bool liked) {
    final chain = _pending;
    if (chain == null) return;
    final reward = liked ? 1.0 : -1.0;
    for (var i = 0; i < chain.keys.length; i++) {
      final entry = profile.memory.putIfAbsent(chain.keys[i], () => EmoMemoryEntry(chain.keys[i]));
      final emoji = chain.emojis[i];
      final current = entry.scores[emoji] ?? 0.0;
      entry.scores[emoji] = current + _learningRate * (reward - current);
    }
    _pending = null;
    persist();
  }
}
