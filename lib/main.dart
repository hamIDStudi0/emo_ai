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
      home: const EmoRoot(),
    );
  }
}
