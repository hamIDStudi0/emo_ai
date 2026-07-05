import 'package:flutter/material.dart';
import 'emo_view.dart';

void main() => runApp(const EmoApp());

class EmoApp extends StatelessWidget {
  const EmoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'emo.ai',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: Colors.amber, useMaterial3: true),
      home: const EmoChatScreen(),
    );
  }
}
