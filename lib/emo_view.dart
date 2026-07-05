// FILE 3: emo_view.dart — Dynamic SVG Face & Chat UI
import 'dart:ui' show lerpDouble;
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'emo_engine.dart';
import 'emo_model.dart' show EmoState;

/// Immutable snapshot of the 4 face parameters, so we can hand a single
/// interpolatable value to a Tween and animate everything in lock-step.
class FaceParams {
  final double eyebrows, eyeOpenness, mouthCurve, colorShift;
  const FaceParams(this.eyebrows, this.eyeOpenness, this.mouthCurve, this.colorShift);
}

class FaceParamsTween extends Tween<FaceParams> {
  FaceParamsTween({required FaceParams begin, required FaceParams end})
      : super(begin: begin, end: end);

  @override
  FaceParams lerp(double t) => FaceParams(
        lerpDouble(begin!.eyebrows, end!.eyebrows, t)!,
        lerpDouble(begin!.eyeOpenness, end!.eyeOpenness, t)!,
        lerpDouble(begin!.mouthCurve, end!.mouthCurve, t)!,
        lerpDouble(begin!.colorShift, end!.colorShift, t)!,
      );
}

/// Renders the face as a freshly-built SVG string every frame (0-byte assets:
/// nothing is bundled, the vector markup is generated purely from state) and
/// smoothly tweens between expressions with TweenAnimationBuilder.
class EmoFaceVisual extends StatelessWidget {
  final double eyebrows, eyeOpenness, mouthCurve, colorShift;
  const EmoFaceVisual({
    super.key,
    required this.eyebrows,
    required this.eyeOpenness,
    required this.mouthCurve,
    required this.colorShift,
  });

  static const _amber = Color(0xFFFFC107);
  static const _crimson = Color(0xFFDC143C);
  static const _paleBlue = Color(0xFFA7D8F0);

  Color _colorFor(double cs) {
    if (cs <= 0) return Color.lerp(_amber, _paleBlue, -cs)!;
    return Color.lerp(_amber, _crimson, cs)!;
  }

  String _hex(Color c) =>
      '#${c.value.toRadixString(16).padLeft(8, '0').substring(2)}';

  String _buildSvg(FaceParams p) {
    const cx = 150.0, cy = 150.0, r = 120.0;
    final color = _colorFor(p.colorShift);
    final eyeY = cy - 15;
    final eyeH = (18 + p.eyeOpenness * 14).clamp(4.0, 34.0); // openness -1..1
    final browLift = p.eyebrows * 22; // eyebrows -1..1 -> arch/furrow
    final mouthY = cy + 48;
    final mouthArc = p.mouthCurve * 45; // positive = smile, negative = frown

    return '''
<svg viewBox="0 0 300 300" xmlns="http://www.w3.org/2000/svg">
  <circle cx="$cx" cy="$cy" r="$r" fill="${_hex(color)}" />
  <path d="M ${cx - 62} ${eyeY - 28 - browLift} Q ${cx - 40} ${eyeY - 46 - browLift} ${cx - 18} ${eyeY - 28 - browLift}"
        stroke="#2b2b2b" stroke-width="7" fill="none" stroke-linecap="round"/>
  <path d="M ${cx + 18} ${eyeY - 28 - browLift} Q ${cx + 40} ${eyeY - 46 - browLift} ${cx + 62} ${eyeY - 28 - browLift}"
        stroke="#2b2b2b" stroke-width="7" fill="none" stroke-linecap="round"/>
  <ellipse cx="${cx - 38}" cy="$eyeY" rx="13" ry="${eyeH / 2}" fill="#2b2b2b"/>
  <ellipse cx="${cx + 38}" cy="$eyeY" rx="13" ry="${eyeH / 2}" fill="#2b2b2b"/>
  <path d="M ${cx - 48} $mouthY Q $cx ${mouthY - mouthArc} ${cx + 48} $mouthY"
        stroke="#2b2b2b" stroke-width="8" fill="none" stroke-linecap="round"/>
</svg>
''';
  }

  @override
  Widget build(BuildContext context) {
    final target = FaceParams(eyebrows, eyeOpenness, mouthCurve, colorShift);
    return TweenAnimationBuilder<FaceParams>(
      tween: FaceParamsTween(begin: target, end: target),
      duration: const Duration(milliseconds: 550),
      curve: Curves.easeInOutCubic,
      builder: (context, params, child) {
        return SizedBox(
          width: 260,
          height: 260,
          child: SvgPicture.string(_buildSvg(params)),
        );
      },
    );
  }
}

class EmoChatScreen extends StatefulWidget {
  const EmoChatScreen({super.key});
  @override
  State<EmoChatScreen> createState() => _EmoChatScreenState();
}

class _EmoChatScreenState extends State<EmoChatScreen> {
  late final EmoEngine _engine;
  final TextEditingController _controller = TextEditingController();
  final List<_ChatMsg> _messages = [];
  FacePrediction _face = FacePrediction.neutral;
  String _lastText = '';
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _engine = EmoEngine(SharedPrefsRepository());
    _engine.init().then((_) => setState(() => _ready = true));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _send() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    _lastText = text;
    setState(() {
      _messages.add(_ChatMsg(text, true));
      _face = _engine.predict(text);
    });
    _controller.clear();
  }

  void _feedback(String fb) {
    if (_lastText.isEmpty) return;
    _engine.learn(fb);
    setState(() {
      _messages.add(_ChatMsg('[$fb]', false));
      // Re-predict so the face reflects what was just learned.
      _face = _engine.predict(_lastText);
    });
    if (_engine.emotionalShock) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('⚡ Emotional shock — learning rate doubled'), duration: Duration(seconds: 1)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      appBar: AppBar(title: const Text('emo.ai')),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 12),
            EmoFaceVisual(
              eyebrows: _face.eyebrows,
              eyeOpenness: _face.eyeOpenness,
              mouthCurve: _face.mouthCurve,
              colorShift: _face.colorShift,
            ),
            const SizedBox(height: 8),
            _StatusPanel(state: _engine.state),
            const Divider(height: 1),
            Expanded(
              child: ListView.builder(
                reverse: true,
                padding: const EdgeInsets.all(12),
                itemCount: _messages.length,
                itemBuilder: (context, i) {
                  final m = _messages[_messages.length - 1 - i];
                  return Align(
                    alignment: m.isUser ? Alignment.centerRight : Alignment.centerLeft,
                    child: Container(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: m.isUser ? Colors.blue[100] : Colors.grey[300],
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(m.text),
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      decoration: const InputDecoration(hintText: 'Ketik sesuatu...'),
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  IconButton(icon: const Icon(Icons.send), onPressed: _send),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  ElevatedButton(onPressed: () => _feedback('Ya'), child: const Text('Ya')),
                  ElevatedButton(onPressed: () => _feedback('Tidak'), child: const Text('Tidak')),
                  ElevatedButton(onPressed: () => _feedback('Mungkin'), child: const Text('Mungkin')),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChatMsg {
  final String text;
  final bool isUser;
  _ChatMsg(this.text, this.isUser);
}

class _StatusPanel extends StatelessWidget {
  final EmoState state;
  const _StatusPanel({required this.state});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('Level ${state.level}'),
          Text('Stress ${(state.stress * 100).toStringAsFixed(0)}%'),
          Text('Bosan ${(state.boredom * 100).toStringAsFixed(0)}%'),
          Text('Homeo ${(state.homeostasis * 100).toStringAsFixed(0)}%'),
        ],
      ),
    );
  }
}
