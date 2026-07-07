// FILE 3: emo_view.dart
//
// Alur baru (jauh lebih sederhana): Boot (animasi, berlangsung selama
// EmoEngine.init() betulan memuat skor dari Turso) -> layar chat TUNGGAL
// untuk satu-satunya AI bersama (emo_ai). Tidak ada lagi multi-profil.
import 'package:flutter/material.dart';
import 'emo_engine.dart';

const _kBg = Color(0xFF0D0F14);
const _kAccent = Colors.amber;

// ============================================================================
// BOOT SCREEN — animasi berlapis, berjalan selama proses init() asli
// (koneksi ke Turso) — bukan delay palsu.
// ============================================================================
class BootScreen extends StatefulWidget {
  const BootScreen({super.key});
  @override
  State<BootScreen> createState() => _BootScreenState();
}

class _BootScreenState extends State<BootScreen> with TickerProviderStateMixin {
  late final AnimationController _pulseCtrl;
  late final AnimationController _rippleCtrl;
  late final AnimationController _dotsCtrl;
  late final AnimationController _floatCtrl;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat(reverse: true);
    _rippleCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 2200))..repeat();
    _dotsCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))..repeat();
    _floatCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 3600))..repeat();
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _rippleCtrl.dispose();
    _dotsCtrl.dispose();
    _floatCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      body: Stack(
        children: [
          AnimatedBuilder(
            animation: _floatCtrl,
            builder: (context, _) => CustomPaint(size: Size.infinite, painter: _FloatingParticlesPainter(_floatCtrl.value)),
          ),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 180,
                  height: 180,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
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
                                decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: _kAccent, width: 2)),
                              ),
                            );
                          },
                        ),
                      AnimatedBuilder(
                        animation: _pulseCtrl,
                        builder: (context, child) => Transform.scale(scale: 0.92 + _pulseCtrl.value * 0.16, child: child),
                        child: const Text('🤖', style: TextStyle(fontSize: 64)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 36),
                SizedBox(
                  width: 160,
                  height: 4,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: const LinearProgressIndicator(value: null, backgroundColor: Colors.white10, valueColor: AlwaysStoppedAnimation(_kAccent)),
                  ),
                ),
                const SizedBox(height: 20),
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
                          curve: Curves.easeOutCubic,
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          width: isActive ? 10 : 7,
                          height: isActive ? 10 : 7,
                          decoration: BoxDecoration(shape: BoxShape.circle, color: isActive ? _kAccent : Colors.white24),
                        );
                      }),
                    );
                  },
                ),
                const SizedBox(height: 18),
                const Text('Menghubungkan ke emo.ai...', style: TextStyle(color: Colors.white38, fontSize: 13)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FloatingParticlesPainter extends CustomPainter {
  final double t;
  _FloatingParticlesPainter(this.t);
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.amber.withOpacity(0.12);
    for (var i = 0; i < 14; i++) {
      final seed = i * 137.5;
      final x = size.width * ((seed % 100) / 100);
      final phase = (t + i / 14) % 1.0;
      final y = size.height * (1 - phase);
      canvas.drawCircle(Offset(x, y), 2.0 + (i % 4), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _FloatingParticlesPainter oldDelegate) => oldDelegate.t != t;
}

// ============================================================================
// LAYAR CHAT TUNGGAL — satu emoji besar, ulasan (kata-kata) di ATAS.
// ============================================================================
class EmoChatScreen extends StatefulWidget {
  final EmoEngine engine;
  const EmoChatScreen({super.key, required this.engine});

  @override
  State<EmoChatScreen> createState() => _EmoChatScreenState();
}

class _EmoChatScreenState extends State<EmoChatScreen> with SingleTickerProviderStateMixin {
  final TextEditingController _ctrl = TextEditingController();
  String? _emoji;
  bool _awaitingReview = false;
  bool _loading = false;
  late final AnimationController _revealCtrl;

  @override
  void initState() {
    super.initState();
    _revealCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 500));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _revealCtrl.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty || _loading) return;
    setState(() => _loading = true);
    final chain = await widget.engine.reply(text);
    if (!mounted) return;
    setState(() {
      _emoji = chain.emoji;
      _awaitingReview = true;
      _loading = false;
    });
    _revealCtrl.forward(from: 0);
    _ctrl.clear();
  }

  Future<void> _review(bool liked) async {
    await widget.engine.review(liked);
    if (mounted) setState(() => _awaitingReview = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: _kBg,
        elevation: 0,
        centerTitle: true,
        title: const Text('emo.ai', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Notifikasi ulasan — kembali ke ATAS, dengan teks Indonesia lagi.
            AnimatedSize(
              duration: const Duration(milliseconds: 300),
              child: _awaitingReview
                  ? Container(
                      width: double.infinity,
                      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                      decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(18)),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Bagaimana jawabannya?', style: TextStyle(color: Colors.white70)),
                          Row(
                            children: [
                              TextButton.icon(
                                onPressed: () => _review(false),
                                icon: const Icon(Icons.thumb_down_rounded, color: Colors.redAccent, size: 18),
                                label: const Text('Tidak suka', style: TextStyle(color: Colors.redAccent)),
                              ),
                              const SizedBox(width: 4),
                              TextButton.icon(
                                onPressed: () => _review(true),
                                icon: const Icon(Icons.thumb_up_rounded, color: Colors.greenAccent, size: 18),
                                label: const Text('Suka', style: TextStyle(color: Colors.greenAccent)),
                              ),
                            ],
                          ),
                        ],
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
            Expanded(
              child: Center(
                child: _loading
                    ? const CircularProgressIndicator(color: _kAccent)
                    : _emoji == null
                        ? const Text('Ketik sesuatu, lihat perasaannya...', style: TextStyle(color: Colors.white24, fontSize: 16))
                        : ScaleTransition(
                            scale: CurvedAnimation(parent: _revealCtrl, curve: Curves.elasticOut),
                            child: Text(_emoji!, style: const TextStyle(fontSize: 140)),
                          ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _ctrl,
                      style: const TextStyle(color: Colors.white),
                      onSubmitted: (_) => _send(),
                      decoration: InputDecoration(
                        hintText: 'Ceritakan sesuatu...',
                        hintStyle: const TextStyle(color: Colors.white38),
                        filled: true,
                        fillColor: Colors.white10,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(icon: const Icon(Icons.send_rounded, color: _kAccent), onPressed: _send),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
