# emo.ai

100% offline emoji companion for Android (Flutter). Tidak ada koneksi
internet, tidak ada database eksternal — semua data hidup di file lokal
`.emoai` di penyimpanan perangkat. Mendukung banyak "AI" (profil) sekaligus
di satu perangkat, masing-masing diidentifikasi dengan avatar emoji (bukan
nama teks), plus export/import antar perangkat lewat file `.emoai`.

## Struktur
```
lib/
  emo_model.dart   # EmoProfile (per-AI) + EmoMemoryEntry data schema
  emo_engine.dart  # tokenizer, weighting emergent, co-occurrence, learning, storage lokal
  emo_view.dart    # boot screen animasi, beranda profil (ikon-saja), layar interaksi
  main.dart        # app entry point
```

## Menjalankan
```bash
flutter pub get
flutter run
```

Build APK rilis:
```bash
flutter build apk --release
```

## Cara kerja
- **Tidak ada daftar kata hardcoded** (tidak ada stopword/sinonim/antonim
  buatan manusia di kode). Setiap kata mulai dengan bobot sama; bobot yang
  "terasa penting" nantinya murni lahir dari seberapa konsisten reaksi
  like/dislike yang pernah diterima kata itu — lihat komentar panjang di
  atas `emo_engine.dart` untuk penjelasan jujur soal apa yang benar-benar
  dilakukan (dan apa yang TIDAK dilakukan) sistem ini.
- Generalisasi ke kata baru yang belum pernah dinilai memakai peta
  co-occurrence (kata yang sering muncul berdekatan) sebagai "firasat" —
  analogi paling jujur dari mengenali kata mirip tanpa kamus.
- **Beranda** menampilkan grid avatar (emoji) semua profil di perangkat ini,
  tanpa teks apa pun — cukup ketuk avatar untuk masuk, tekan lama untuk
  hapus, tombol "+" untuk menambah (pilih Import file `.emoai` atau Baru).
- **Export**: dari layar interaksi, tombol share di kanan atas menyimpan
  seluruh memori profil itu sebagai file `.emoai` (JSON) yang bisa dipindah
  ke perangkat lain dan di-import di sana.

## Privasi & Play Protect
Karena tidak ada permission INTERNET yang dipakai (aplikasi memang tidak
tahu cara connect ke jaringan), salah satu pemicu Play Protect yang paling
umum untuk app kecil (kirim data ke server tak dikenal) tidak berlaku di
sini. Lihat `GOOGLE_PLAY_PROTECT.md` untuk penyebab lain yang masih relevan
(signing key, distribusi di luar Play Store, dsb).
