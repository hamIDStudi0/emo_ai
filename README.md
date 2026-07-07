# emo.ai

Satu AI emoji bersama (bukan lagi per-perangkat) untuk Android (Flutter).
Setiap kalimat yang diketik pengguna dikirim ke **IndoBERT** (lewat
Hugging Face Inference API, model
`StevenLimcorn/indonesian-roberta-base-emotion-classifier`) untuk dideteksi
emosinya (anger/fear/happy/love/sadness/netral), lalu satu emoji besar
ditampilkan sebagai balasan. Skor "emoji mana yang paling pas untuk emosi
ini" dipelajari dari like/dislike dan disimpan bersama di **Turso** —
semua pengguna app ini belajar ke satu otak yang sama.

## Struktur
```
lib/
  emo_model.dart   # skema Q-table (label emosi -> skor emoji)
  emo_engine.dart  # panggilan IndoBERT (HF), penyimpanan Turso, epsilon-greedy learning
  emo_view.dart    # boot screen animasi + layar chat tunggal
  main.dart        # app entry point, injeksi kredensial via --dart-define
```

## Setup
Lihat `SETUP_INDOBERT_TURSO.md` untuk cara membuat token Hugging Face,
database Turso, dan menyambungkannya ke build Codemagic.

## Menjalankan lokal
```bash
flutter pub get
flutter run \
  --dart-define=HF_TOKEN=hf_xxx \
  --dart-define=TURSO_DATABASE_URL=libsql://xxx.turso.io \
  --dart-define=TURSO_AUTH_TOKEN=xxx
```

## Catatan jujur
- App ini **butuh internet** (Hugging Face + Turso) — beda dari versi
  offline sebelumnya. Kemungkinan besar Google Play Protect menandai app
  lagi seperti sebelum versi offline dibuat; lihat `GOOGLE_PLAY_PROTECT.md`.
- Hugging Face free tier dibatasi rate limit (~ratusan request/jam) —
  cukup untuk personal/testing, bukan untuk trafik besar.
- Karena satu database dipakai bersama, siapa pun yang pakai app ini ikut
  memengaruhi skor emoji yang dipelajari — tidak ada isolasi per pengguna.
