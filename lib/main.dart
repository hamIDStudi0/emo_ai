import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'emo_view.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // §3: a 100% canvas observation screen — no system chrome competing with
  // emo's face for the user's attention.
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  runApp(const EmoApp());
}

class EmoApp extends StatelessWidget {
  const EmoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'emo.ai',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: Colors.amber,
        useMaterial3: true,
        brightness: Brightness.dark,
      ),
      home: const _AppRoot(),
    );
  }
}

/// 100% offline sekarang — tidak ada init koneksi apa pun, boot screen cuma
/// dipakai untuk transisi visual singkat sebelum masuk ke beranda daftar
/// profil (yang membaca file lokal dari disk).
class _AppRoot extends StatefulWidget {
  const _AppRoot();
  @override
  State<_AppRoot> createState() => _AppRootState();
}

class _AppRootState extends State<_AppRoot> {
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 1400), () {
      if (mounted) setState(() => _ready = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 500),
      child: _ready ? const ProfileHomeScreen(key: ValueKey('home')) : const BootScreen(key: ValueKey('boot')),
    );
  }
}
