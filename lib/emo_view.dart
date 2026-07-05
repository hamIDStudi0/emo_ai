// FILE 3: emo_view.dart — Full-Screen Canvas, Face Rendering & Chat UI
//
// Implements command.md §2 (Advanced Multi-Layered Animation System),
// §3 (Immersive UX & Hidden Evaluation Bar) and §4 (Birthing Stage).
//
// The face is a freshly-built SVG string every frame — zero bundled assets,
// pure vector markup generated from state (§CRITICAL DIRECTIVES). Three
// independent kinetic cycles (breathing, blinking, gaze drift) run
// continuously via their own AnimationControllers/Timers and are combined
// with a slow, smooth expression tween on top, so the face never looks like
// a static "dead image".
import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'emo_engine.dart';

/// Tween that interpolates every facial + HSL coordinate at once, so a full
/// expression change (e.g. after a new prediction) animates in lock-step
/// rather than each parameter drifting independently.
class ExpressionFrameTween extends Tween<ExpressionFrame> {
  ExpressionFrameTween({required ExpressionFrame begin, required ExpressionFrame end})
      : super(begin: begin, end: end);

  @override
  ExpressionFrame lerp(double t) => begin!.lerpTo(end!, t);
}

/// Renders emo's face full-screen and keeps it perpetually alive with three
/// overlapping, independent animation cycles on top of the current
/// [expression]:
///   1. Seamless breathing loop      — sin-wave macro scale, always running.
///   2. Autonomous blinking cycle    — random-interval quick eye compression.
///   3. Idle look-drift              — small asymmetric gaze wander.
///   4. Micro-expression "thinking"  — rapid mouth vibration while [isThinking].
class EmoFaceCanvas extends StatefulWidget {
  final ExpressionFrame expression;
  final bool isThinking;

  const EmoFaceCanvas({
    super.key,
    required this.expression,
    this.isThinking = false,
  });

  @override
  State<EmoFaceCanvas> createState() => _EmoFaceCanvasState();
}

class _EmoFaceCanvasState extends State<EmoFaceCanvas> with TickerProviderStateMixin {
  final Random _rng = Random();

  late final AnimationController _breathCtrl;
  late final AnimationController _blinkCtrl;
  late final AnimationController _thinkCtrl;
  late final AnimationController _driftCtrl;

  Offset _driftFrom = Offset.zero;
  Offset _driftTo = Offset.zero;

  Timer? _blinkTimer;
  Timer? _driftTimer;

  @override
  void initState() {
    super.initState();
    _breathCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 4))
      ..repeat(reverse: true);
    _blinkCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 140));
    _thinkCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 80));
    _driftCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200));

    _scheduleBlink();
    _scheduleDrift();
    if (widget.isThinking) _thinkCtrl.repeat(reverse: true);
  }

  void _scheduleBlink() {
    _blinkTimer = Timer(Duration(milliseconds: 2200 + _rng.nextInt(3600)), () async {
      if (!mounted) return;
      await _blinkCtrl.forward();
      if (!mounted) return;
      await _blinkCtrl.reverse();
      _scheduleBlink();
    });
  }

  void _scheduleDrift() {
    _driftTimer = Timer(Duration(milliseconds: 1800 + _rng.nextInt(2600)), () {
      if (!mounted) return;
      final settled = Offset.lerp(_driftFrom, _driftTo, _driftCtrl.value) ?? Offset.zero;
      _driftFrom = settled;
      _driftTo = Offset((_rng.nextDouble() * 2 - 1) * 9, (_rng.nextDouble() * 2 - 1) * 5);
      _driftCtrl.forward(from: 0);
      _scheduleDrift();
    });
  }

  @override
  void didUpdateWidget(covariant EmoFaceCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isThinking && !_thinkCtrl.isAnimating) {
      _thinkCtrl.repeat(reverse: true);
    } else if (!widget.isThinking && _thinkCtrl.isAnimating) {
      _thinkCtrl.stop();
      _thinkCtrl.value = 0;
    }
  }

  @override
  void dispose() {
    _blinkTimer?.cancel();
    _driftTimer?.cancel();
    _breathCtrl.dispose();
    _blinkCtrl.dispose();
    _thinkCtrl.dispose();
    _driftCtrl.dispose();
    super.dispose();
  }

  String _buildSvg({
    required ExpressionFrame e,
    required double blink,
    required Offset gaze,
    required double thinkJitter,
  }) {
    const w = 320.0, h = 320.0;
    const cx = w / 2, cy = h / 2;
    const faceR = 130.0;
    final color = 'hsl(${e.hue.toStringAsFixed(1)}, '
        '${(e.saturation * 100).toStringAsFixed(0)}%, '
        '${(e.lightness * 100).toStringAsFixed(0)}%)';

    final browLift = e.eyebrowTilt * 26;
    final eyeRy = (10 + e.eyeSize * 16) * (1 - blink).clamp(0.05, 1.0);
    final eyeRot = e.eyeRotation * 12;
    const eyeGapX = 42.0;
    const eyeY = cy - 14;
    final pupilDx = gaze.dx.clamp(-8.0, 8.0);
    final pupilDy = gaze.dy.clamp(-6.0, 6.0);
    final pupilOpacity = blink > 0.7 ? 0 : 1;
    final mouthHalfW = 30 + e.mouthWidth * 30;
    final mouthArc = e.mouthDepth * 40 + thinkJitter;
    const mouthY = cy + 46;

    return '''
<svg viewBox="0 0 $w $h" xmlns="http://www.w3.org/2000/svg">
  <circle cx="$cx" cy="$cy" r="$faceR" fill="$color" />
  <g transform="rotate($eyeRot ${cx - eyeGapX} $eyeY)">
    <ellipse cx="${cx - eyeGapX}" cy="$eyeY" rx="14" ry="$eyeRy" fill="#232323"/>
    <circle cx="${cx - eyeGapX + pupilDx}" cy="${eyeY + pupilDy}" r="4" fill="#ffffff" opacity="$pupilOpacity"/>
  </g>
  <g transform="rotate(${-eyeRot} ${cx + eyeGapX} $eyeY)">
    <ellipse cx="${cx + eyeGapX}" cy="$eyeY" rx="14" ry="$eyeRy" fill="#232323"/>
    <circle cx="${cx + eyeGapX + pupilDx}" cy="${eyeY + pupilDy}" r="4" fill="#ffffff" opacity="$pupilOpacity"/>
  </g>
  <path d="M ${cx - eyeGapX - 24} ${eyeY - 30 - browLift} Q ${cx - eyeGapX} ${eyeY - 48 - browLift} ${cx - eyeGapX + 24} ${eyeY - 30 - browLift}"
        stroke="#232323" stroke-width="7" fill="none" stroke-linecap="round"/>
  <path d="M ${cx + eyeGapX - 24} ${eyeY - 30 - browLift} Q ${cx + eyeGapX} ${eyeY - 48 - browLift} ${cx + eyeGapX + 24} ${eyeY - 30 - browLift}"
        stroke="#232323" stroke-width="7" fill="none" stroke-linecap="round"/>
  <path d="M ${cx - mouthHalfW} $mouthY Q $cx ${mouthY - mouthArc} ${cx + mouthHalfW} $mouthY"
        stroke="#232323" stroke-width="8" fill="none" stroke-linecap="round"/>
</svg>
''';
  }

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<ExpressionFrame>(
      tween: ExpressionFrameTween(begin: widget.expression, end: widget.expression),
      duration: const Duration(milliseconds: 750),
      curve: Curves.easeInOutCubic,
      builder: (context, expr, _) {
        return AnimatedBuilder(
          animation: Listenable.merge([_breathCtrl, _blinkCtrl, _thinkCtrl, _driftCtrl]),
          builder: (context, __) {
            final breath = 1.0 + (_breathCtrl.value - 0.5) * 0.06;
            final gaze = Offset.lerp(
                  _driftFrom,
                  _driftTo,
                  Curves.easeInOutCubic.transform(_driftCtrl.value),
                ) ??
                Offset.zero;
            final thinkJitter = widget.isThinking ? sin(_thinkCtrl.value * pi * 2) * 4 : 0.0;

            return Transform.scale(
              scale: breath,
              child: SizedBox(
                width: 300,
                height: 300,
                child: SvgPicture.string(
                  _buildSvg(e: expr, blink: _blinkCtrl.value, gaze: gaze, thinkJitter: thinkJitter),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

/// §4 Initialization & Birthing Stage. Shown exactly once, on the very
/// first launch: the user must register a sacred name before the full
/// interactive canvas unlocks.
class EmoBirthScreen extends StatefulWidget {
  final EmoEngine engine;
  final VoidCallback onBorn;

  const EmoBirthScreen({super.key, required this.engine, required this.onBorn});

  @override
  State<EmoBirthScreen> createState() => _EmoBirthScreenState();
}

class _EmoBirthScreenState extends State<EmoBirthScreen> {
  final TextEditingController _nameCtrl = TextEditingController();

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _birth() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return;
    await widget.engine.registerName(name);
    widget.onBorn();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0F14),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const EmoFaceCanvas(expression: ExpressionFrame.neutral),
                const SizedBox(height: 32),
                const Text(
                  'Beri nama untuk entitas ini',
                  style: TextStyle(color: Colors.white70, fontSize: 16),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _nameCtrl,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 20),
                  decoration: const InputDecoration(
                    hintText: 'Nama...',
                    hintStyle: TextStyle(color: Colors.white38),
                    enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                    focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.amber)),
                  ),
                  onSubmitted: (_) => _birth(),
                ),
                const SizedBox(height: 24),
                ElevatedButton(onPressed: _birth, child: const Text('Lahirkan')),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// §3 Immersive UX: a 100% canvas observation screen. The face fills the
/// entire viewport; the chat workspace and Like/Dislike thumbs live hidden
/// underneath a bottom drawer that only a micro-arrow toggle reveals, so
/// evaluation controls never sit on top of / obscure emo's face.
class EmoHomeScreen extends StatefulWidget {
  final EmoEngine engine;

  const EmoHomeScreen({super.key, required this.engine});

  @override
  State<EmoHomeScreen> createState() => _EmoHomeScreenState();
}

class _EmoHomeScreenState extends State<EmoHomeScreen> with TickerProviderStateMixin {
  final TextEditingController _inputCtrl = TextEditingController();
  late final AnimationController _flyCtrl;

  ExpressionFrame _expression = ExpressionFrame.neutral;
  bool _sheetOpen = false;
  bool _isThinking = false;
  bool _awaitingFeedback = false;
  String? _flyingText;
  String _lastText = '';

  @override
  void initState() {
    super.initState();
    _flyCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 420));
  }

  @override
  void dispose() {
    _inputCtrl.dispose();
    _flyCtrl.dispose();
    super.dispose();
  }

  /// Snap Flying-Bubble Animation: fires the typed bubble upward toward
  /// emo's mouth, closes the sheet automatically, then lands the new
  /// prediction once the (brief, cosmetic) "thinking" beat finishes.
  Future<void> _send() async {
    final text = _inputCtrl.text.trim();
    if (text.isEmpty) return;
    _inputCtrl.clear();
    _lastText = text;
    setState(() {
      _flyingText = text;
      _isThinking = true;
      _awaitingFeedback = false;
    });
    _flyCtrl.forward(from: 0);

    await Future.delayed(const Duration(milliseconds: 520));
    final expr = widget.engine.predict(text);
    if (!mounted) return;
    setState(() {
      _expression = expr;
      _isThinking = false;
      _awaitingFeedback = true;
      _sheetOpen = false;
      _flyingText = null;
    });
    _flyCtrl.reset();
  }

  void _like() {
    widget.engine.likeCurrent();
    setState(() => _awaitingFeedback = false);
  }

  void _dislike() {
    widget.engine.dislikeCurrent();
    final expr = widget.engine.predict(_lastText);
    setState(() {
      _expression = expr;
      _awaitingFeedback = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return Scaffold(
      backgroundColor: const Color(0xFF0D0F14),
      body: Stack(
        fit: StackFit.expand,
        children: [
          Center(
            child: EmoFaceCanvas(expression: _expression, isThinking: _isThinking),
          ),
          if (_flyingText != null) _buildFlyingBubble(size),
          _buildBottomSheet(),
        ],
      ),
    );
  }

  Widget _buildFlyingBubble(Size size) {
    return AnimatedBuilder(
      animation: _flyCtrl,
      builder: (context, _) {
        final t = Curves.easeIn.transform(_flyCtrl.value);
        final startY = size.height - 140;
        final endY = size.height * 0.32;
        final y = startY + (endY - startY) * t;
        final opacity = (1 - t).clamp(0.0, 1.0);
        return Positioned(
          left: 0,
          right: 0,
          top: y,
          child: Center(
            child: Opacity(
              opacity: opacity,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.amber.withOpacity(0.9),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(_flyingText ?? '', style: const TextStyle(color: Colors.black87)),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildBottomSheet() {
    return AnimatedPositioned(
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeInOutCubic,
      left: 0,
      right: 0,
      bottom: 0,
      height: _sheetOpen ? 220 : 46,
      child: GestureDetector(
        onTap: () => setState(() => _sheetOpen = !_sheetOpen),
        onVerticalDragUpdate: (d) {
          if (d.delta.dy < -4 && !_sheetOpen) setState(() => _sheetOpen = true);
          if (d.delta.dy > 4 && _sheetOpen) setState(() => _sheetOpen = false);
        },
        child: Container(
          decoration: const BoxDecoration(
            color: Color(0xFF1A1D24),
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 8),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
              ),
              Icon(
                _sheetOpen ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_up,
                color: Colors.white38,
                size: 18,
              ),
              if (_sheetOpen) ...[
                const SizedBox(height: 4),
                if (_awaitingFeedback) _buildFeedbackRow(),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            decoration: BoxDecoration(
                              color: Colors.white10,
                              borderRadius: BorderRadius.circular(24),
                            ),
                            child: TextField(
                              controller: _inputCtrl,
                              style: const TextStyle(color: Colors.white),
                              decoration: const InputDecoration(
                                border: InputBorder.none,
                                hintText: 'Ketik sesuatu...',
                                hintStyle: TextStyle(color: Colors.white38),
                              ),
                              onSubmitted: (_) => _send(),
                            ),
                          ),
                        ),
                        IconButton(icon: const Icon(Icons.send, color: Colors.amber), onPressed: _send),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Unobtrusive Floating Feedback: the Like/Dislike thumbs row is embedded
  /// deep inside the expandable sheet and only appears once a prompt has
  /// actually been processed, so it never blocks the view of emo's face.
  Widget _buildFeedbackRow() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            icon: const Icon(Icons.thumb_up_alt_outlined, color: Colors.greenAccent),
            onPressed: _like,
          ),
          const SizedBox(width: 24),
          IconButton(
            icon: const Icon(Icons.thumb_down_alt_outlined, color: Colors.redAccent),
            onPressed: _dislike,
          ),
        ],
      ),
    );
  }
}

/// App root: waits for the engine's local persistence to load, then routes
/// to the one-time birthing ritual or straight into the full-screen canvas.
class EmoRoot extends StatefulWidget {
  const EmoRoot({super.key});

  @override
  State<EmoRoot> createState() => _EmoRootState();
}

class _EmoRootState extends State<EmoRoot> {
  late final EmoEngine _engine;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _engine = EmoEngine(SharedPrefsRepository());
    _engine.init().then((_) {
      if (mounted) setState(() => _ready = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return const Scaffold(
        backgroundColor: Color(0xFF0D0F14),
        body: Center(child: CircularProgressIndicator(color: Colors.amber)),
      );
    }
    if (!_engine.state.isBorn) {
      return EmoBirthScreen(
        engine: _engine,
        onBorn: () => setState(() {}),
      );
    }
    return EmoHomeScreen(engine: _engine);
  }
}
