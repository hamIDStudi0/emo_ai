// FILE 3: emo_view.dart — Emoji Stage, Idle Self-Talk & Review Notification
//
// The face is gone; the stage now shows real emoji glyphs (device's own
// color emoji font — zero bundled assets, same "0-byte" spirit as before).
// Two animation problems from the previous version are fixed here:
//   1. Entrances/exits now use non-linear easing (easeOutBack / easeInCubic)
//      instead of a flat linear lerp, and each emoji in a chain pops in
//      with a small stagger instead of all snapping in at once.
//   2. A chain can contain 2+ emoji, and the entity keeps emitting chains on
//      its own while idle — not just in reply to messages.
// A review banner slides down from the top exactly when the *current*
// chain has finished animating in, whether that chain was a reply or an
// idle self-emission, and Like/Dislike always apply to that whole chain.
import 'dart:async';
import 'package:flutter/material.dart';
import 'emo_engine.dart';

/// Pops a single emoji in with a bouncy scale + fade after `delay`, so a
/// multi-emoji chain reads as "arriving" one after another rather than
/// snapping onto the screen as a block.
class StaggeredEmoji extends StatefulWidget {
  final String emoji;
  final Duration delay;
  const StaggeredEmoji({super.key, required this.emoji, required this.delay});

  @override
  State<StaggeredEmoji> createState() => _StaggeredEmojiState();
}

class _StaggeredEmojiState extends State<StaggeredEmoji> {
  bool _shown = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(widget.delay, () {
      if (mounted) setState(() => _shown = true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      scale: _shown ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutBack,
      child: AnimatedOpacity(
        opacity: _shown ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOut,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Text(widget.emoji, style: const TextStyle(fontSize: 56)),
        ),
      ),
    );
  }
}

/// Displays the current chain as a row of [StaggeredEmoji], and swaps
/// whole chains (reply <-> idle <-> next reply) through an [AnimatedSwitcher]
/// so the outgoing chain shrinks/fades away (easeInCubic) instead of just
/// vanishing, while the incoming one pops in with easeOutBack.
class EmojiStage extends StatelessWidget {
  final EmoChain? chain;
  final int generation;
  const EmojiStage({super.key, required this.chain, required this.generation});

  @override
  Widget build(BuildContext context) {
    final current = chain;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 320),
      switchInCurve: Curves.easeOutBack,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) => ScaleTransition(
        scale: animation,
        child: FadeTransition(opacity: animation, child: child),
      ),
      child: current == null
          ? const SizedBox(key: ValueKey('empty'), width: 1, height: 1)
          : Row(
              key: ValueKey(generation),
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < current.emojis.length; i++)
                  StaggeredEmoji(
                    emoji: current.emojis[i],
                    delay: Duration(milliseconds: i * 130),
                  ),
              ],
            ),
    );
  }
}

// Catatan: layar "beri nama" sebelumnya DIHAPUS atas permintaan — proses
// kelahiran kini otomatis lewat `EmoEngine.autoBornIfNeeded()` di
// emo_engine.dart, tanpa meminta nama apa pun. Ini sejalan dengan permintaan
// agar data yang tersimpan di Turso (termasuk log ulasan) benar-benar
// anonim, tidak terikat pada identitas siapa pun.

class EmoHomeScreen extends StatefulWidget {
  final EmoEngine engine;
  const EmoHomeScreen({super.key, required this.engine});

  @override
  State<EmoHomeScreen> createState() => _EmoHomeScreenState();
}

class _EmoHomeScreenState extends State<EmoHomeScreen> {
  final TextEditingController _inputCtrl = TextEditingController();

  EmoChain? _chain;
  int _generation = 0;
  bool _sheetOpen = false;
  bool _reviewVisible = false;

  Timer? _idleTimer;
  Timer? _reviewRevealTimer;

  @override
  void initState() {
    super.initState();
    _scheduleIdle();
  }

  @override
  void dispose() {
    _idleTimer?.cancel();
    _reviewRevealTimer?.cancel();
    _inputCtrl.dispose();
    super.dispose();
  }

  /// Idle self-talk: while left alone, the entity keeps trying other
  /// responses on its own at random intervals. Any user interaction
  /// (sending a message) resets this timer.
  void _scheduleIdle() {
    _idleTimer?.cancel();
    _idleTimer = Timer(Duration(seconds: 18 + DateTime.now().millisecond % 20), () {
      if (!mounted) return;
      _emit(widget.engine.autonomous());
      _scheduleIdle();
    });
  }

  /// Shared by both replies and idle self-emissions: shows the new chain,
  /// then reveals the review notification once the chain has fully
  /// finished popping in ("array respon selesai").
  void _emit(EmoChain chain) {
    _reviewRevealTimer?.cancel();
    setState(() {
      _chain = chain;
      _generation++;
      _reviewVisible = false;
    });
    final totalPopInMs = chain.emojis.length * 130 + 420;
    _reviewRevealTimer = Timer(Duration(milliseconds: totalPopInMs), () {
      if (!mounted) return;
      setState(() => _reviewVisible = true);
    });
  }

  void _send() {
    final text = _inputCtrl.text.trim();
    if (text.isEmpty) return;
    _inputCtrl.clear();
    setState(() => _sheetOpen = false);
    _emit(widget.engine.reply(text));
    _scheduleIdle();
  }

  void _review(bool liked) {
    widget.engine.review(liked);
    setState(() => _reviewVisible = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0F14),
      body: Stack(
        fit: StackFit.expand,
        children: [
          Center(child: EmojiStage(chain: _chain, generation: _generation)),
          _buildReviewBanner(),
          _buildBottomSheet(),
        ],
      ),
    );
  }

  /// Unobtrusive-but-visible review notification: slides down from the top
  /// only once the current chain (reply OR idle) has finished displaying,
  /// and always evaluates that whole chain — reply or self-talk alike.
  Widget _buildReviewBanner() {
    return AnimatedPositioned(
      duration: const Duration(milliseconds: 380),
      curve: _reviewVisible ? Curves.easeOutBack : Curves.easeInCubic,
      top: _reviewVisible ? 0 : -120,
      left: 0,
      right: 0,
      child: SafeArea(
        child: Center(
          child: Container(
            margin: const EdgeInsets.only(top: 8),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1D24),
              borderRadius: BorderRadius.circular(20),
              boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 12)],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _chain?.isIdle == true ? 'Ekspresi iseng ini pas?' : 'Responnya pas?',
                  style: const TextStyle(color: Colors.white70),
                ),
                const SizedBox(width: 12),
                IconButton(
                  icon: const Icon(Icons.thumb_up_alt_outlined, color: Colors.greenAccent, size: 20),
                  onPressed: () => _review(true),
                ),
                IconButton(
                  icon: const Icon(Icons.thumb_down_alt_outlined, color: Colors.redAccent, size: 20),
                  onPressed: () => _review(false),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBottomSheet() {
    return AnimatedPositioned(
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeInOutCubic,
      left: 0,
      right: 0,
      bottom: 0,
      height: _sheetOpen ? 160 : 46,
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
              if (_sheetOpen)
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
          ),
        ),
      ),
    );
  }
}

/// Layar boot bergaya "Android TV": logo yang berdenyut (pulse), beberapa
/// cincin yang mengembang dan memudar berurutan (ripple), garis progres
/// yang mengisi dari kiri, serta titik-titik loading yang menyala bergilir.
/// Semuanya CSS-free (murni Flutter `AnimationController`), tidak butuh
/// aset gambar apa pun — konsisten dengan semangat "zero-asset" proyek ini.
class _BootScreen extends StatefulWidget {
  const _BootScreen();

  @override
  State<_BootScreen> createState() => _BootScreenState();
}

class _BootScreenState extends State<_BootScreen> with TickerProviderStateMixin {
  late final AnimationController _pulseCtrl;
  late final AnimationController _rippleCtrl;
  late final AnimationController _dotsCtrl;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))
      ..repeat(reverse: true);
    _rippleCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 2200))
      ..repeat();
    _dotsCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))
      ..repeat();
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _rippleCtrl.dispose();
    _dotsCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0F14),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 180,
              height: 180,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Tiga cincin ripple, masing-masing dengan offset fase
                  // berbeda supaya terlihat "mengembang berurutan" seperti
                  // logo boot Android TV.
                  for (final phase in [0.0, 0.33, 0.66])
                    AnimatedBuilder(
                      animation: _rippleCtrl,
                      builder: (context, _) {
                        final t = (_rippleCtrl.value + phase) % 1.0;
                        return Opacity(
                          opacity: (1.0 - t) * 0.6,
                          child: Container(
                            width: 70 + t * 110,
                            height: 70 + t * 110,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.amber, width: 2),
                            ),
                          ),
                        );
                      },
                    ),
                  // Logo/emoji inti yang berdenyut pelan.
                  AnimatedBuilder(
                    animation: _pulseCtrl,
                    builder: (context, child) {
                      final scale = 0.92 + _pulseCtrl.value * 0.16;
                      return Transform.scale(scale: scale, child: child);
                    },
                    child: const Text('🤖', style: TextStyle(fontSize: 64)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 36),
            // Garis progres tak-tentu (indeterminate) bergaya TV.
            SizedBox(
              width: 160,
              height: 4,
              child: AnimatedBuilder(
                animation: _rippleCtrl,
                builder: (context, _) {
                  return ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      value: null,
                      backgroundColor: Colors.white10,
                      valueColor: const AlwaysStoppedAnimation(Colors.amber),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 20),
            // Titik-titik loading yang menyala bergiliran.
            AnimatedBuilder(
              animation: _dotsCtrl,
              builder: (context, _) {
                final active = (_dotsCtrl.value * 3).floor() % 3;
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: List.generate(3, (i) {
                    final isActive = i == active;
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      width: isActive ? 10 : 7,
                      height: isActive ? 10 : 7,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isActive ? Colors.amber : Colors.white24,
                      ),
                    );
                  }),
                );
              },
            ),
            const SizedBox(height: 16),
            const Text('Menyalakan...', style: TextStyle(color: Colors.white38, fontSize: 13)),
          ],
        ),
      ),
    );
  }
}

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
    final repo = TursoConfig.isConfigured
        ? TursoRepository(databaseUrl: TursoConfig.databaseUrl, authToken: TursoConfig.authToken)
        : InMemoryRepository();
    _engine = EmoEngine(repo);
    _engine.init().then((_) async {
      // Kelahiran otomatis, tanpa meminta nama — lihat catatan di
      // EmoBirthScreen (dihapus) dan EmoEngine.autoBornIfNeeded().
      await _engine.autoBornIfNeeded();
      if (mounted) setState(() => _ready = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return const _BootScreen();
    }
    return EmoHomeScreen(engine: _engine);
  }
}
