import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'emo_engine.dart';
import 'emo_view.dart';

// Kredensial disuntik saat build lewat --dart-define (lihat codemagic.yaml)
// — TIDAK di-hardcode di source code.
const String _serverUrl = String.fromEnvironment('EMO_SERVER_URL', defaultValue: '');
const String _tursoUrl = String.fromEnvironment('TURSO_DATABASE_URL', defaultValue: '');
const String _tursoToken = String.fromEnvironment('TURSO_AUTH_TOKEN', defaultValue: '');

void main() {
  WidgetsFlutterBinding.ensureInitialized();
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
      theme: ThemeData(colorSchemeSeed: Colors.amber, useMaterial3: true, brightness: Brightness.dark),
      home: const _AppRoot(),
    );
  }
}

/// Boot screen tampil SELAMA proses init() beneran (koneksi ke Turso untuk
/// memuat skor bersama) — bukan delay palsu. Setelah siap, masuk ke satu
/// layar chat untuk satu-satunya AI bersama (emo_ai) — tidak ada lagi
/// pemilihan/pembuatan profil.
class _AppRoot extends StatefulWidget {
  const _AppRoot();
  @override
  State<_AppRoot> createState() => _AppRootState();
}

class _AppRootState extends State<_AppRoot> {
  EmoEngine? _engine;
  String? _error;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    final engine = EmoEngine(
      classifier: IndoBertClassifier(_serverUrl),
      store: TursoStore(databaseUrl: _tursoUrl, authToken: _tursoToken),
    );
    try {
      await engine.init();
      if (mounted) setState(() => _engine = engine);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Scaffold(
        backgroundColor: const Color(0xFF0D0F14),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'Gagal terhubung ke emo.ai:\n$_error',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.redAccent),
            ),
          ),
        ),
      );
    }
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 500),
      child: _engine == null
          ? const BootScreen(key: ValueKey('boot'))
          : EmoChatScreen(key: const ValueKey('chat'), engine: _engine!),
    );
  }
}
