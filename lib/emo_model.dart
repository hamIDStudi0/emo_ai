// FILE 1: emo_model.dart
//
// Sekarang jauh lebih sederhana: HANYA SATU "AI" bersama (emo_ai) untuk
// semua orang. Kuncinya bukan lagi kata mentah, tapi LABEL EMOSI yang
// dideteksi IndoBERT (lihat emo_engine.dart) — anger/fear/happy/love/
// sadness/netral. Setiap label punya tabel skor emoji sendiri, disimpan
// bersama di Turso supaya semua pengguna belajar ke satu otak yang sama.

/// Satu baris Q-table: label emosi -> {emoji -> skor}.
class EmoLabelEntry {
  final String label;
  Map<String, double> scores;
  int freq;

  EmoLabelEntry(this.label, {Map<String, double>? scores, this.freq = 0}) : scores = scores ?? {};
}
