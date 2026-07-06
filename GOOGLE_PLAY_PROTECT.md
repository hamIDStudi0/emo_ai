# Tutorial: Mengatasi Google Play Protect Menandai APK/App

Google Play Protect biasanya menandai APK Flutter karena beberapa alasan
teknis, jarang karena "kode berbahaya" sungguhan. Ikuti checklist ini
berurutan — kebanyakan kasus selesai di langkah 1–3.

## 1. Pastikan build ditandatangani dengan release key, bukan debug key
APK yang ditandatangani dengan debug keystore (`debug.keystore` bawaan
Flutter) hampir selalu dicurigai Play Protect karena kunci itu publik dan
dipakai jutaan proyek contoh.

- Buat keystore rilis sendiri:
  ```
  keytool -genkey -v -keystore ~/emo-release-key.jks -keyalg RSA \
    -keysize 2048 -validity 10000 -alias emo_ai
  ```
- Isi `android/key.properties`:
  ```
  storePassword=...
  keyPassword=...
  keyAlias=emo_ai
  storeFile=/absolute/path/emo-release-key.jks
  ```
- Pastikan `android/app/build.gradle` memuat konfigurasi `signingConfigs.release`
  yang membaca file itu dan dipakai oleh `buildTypes.release`.
- Build ulang: `flutter build appbundle --release` (App Bundle, bukan APK
  mentah, untuk upload ke Play Console).

## 2. Aktifkan Play App Signing
Di Play Console → **Setup → App integrity**, pastikan **Play App Signing**
aktif. Ini membuat Google menandatangani ulang build dengan kunci yang sudah
mereka verifikasi — mengurangi banyak false-positive Play Protect di sisi
pengguna akhir.

## 3. Lengkapi App Content di Play Console
Play Protect (dan proses review) sering menahan app yang formulirnya belum
lengkap:
- **Data safety form**: deklarasikan bahwa data ulasan disimpan (Turso) dan
  jelaskan bahwa data anonim (tanpa nama/identitas) — sesuai perubahan yang
  sudah dilakukan di proyek ini.
- **Privacy policy URL**: wajib diisi, meski app kecil.
- **Target API level**: pastikan `targetSdkVersion` di
  `android/app/build.gradle` mengikuti syarat terbaru Play (biasanya API
  level tahun berjalan − boleh dicek di Play Console saat upload, akan ada
  peringatan jika kurang).

## 4. Hindari pola yang sering di-flag heuristically
- Jangan memuat kode dari luar APK saat runtime (dynamic code loading) —
  proyek ini sudah aman karena semua logic ada di dalam APK.
- Jangan minta permission berlebihan di `AndroidManifest.xml` yang tidak
  benar-benar dipakai (app ini hanya butuh akses internet untuk Turso —
  `<uses-permission android:name="android.permission.INTERNET"/>` — jangan
  tambahkan lebih dari itu).
- Jangan obfuscate/minify secara agresif tanpa mapping yang jelas jika belum
  perlu; obfuscation berlebihan pada app kecil kadang menaikkan skor
  kecurigaan heuristik.

## 5. Uji sendiri dengan Play Protect sebelum submit
- Upload dulu ke **Internal testing track** di Play Console.
- Install dari track itu di HP fisik, buka **Play Store → Profil → Play
  Protect → pindai** manual, lihat apakah masih ditandai.
- Jika APK di-scan langsung (di luar Play Store) lewat
  https://play.google.com/apps/testing → juga bisa memicu warning karena
  "app tidak dikenal"; ini normal untuk app baru dan akan hilang setelah
  cukup banyak install bersih tanpa laporan.

## 6. Jika sudah lolos semua di atas tapi masih ditandai
Ajukan **App content appeal / reconsideration** lewat Play Console →
**Policy status** → ikuti tautan "Appeal" pada pelanggaran yang muncul.
Sertakan penjelasan singkat: app open-source, hanya menyimpan skor/emoji
anonim di Turso, tidak ada permission sensitif, tidak ada kode native pihak
ketiga yang tidak dikenal.

---
Referensi resmi: dokumentasi Google Play Console "Prepare your app for
review" dan "App signing", serta pusat bantuan Play Protect di
`support.google.com/googleplay/answer/2812853`.
