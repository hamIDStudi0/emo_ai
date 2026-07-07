// FILE 3: emo_view.dart — UI layer.
//
// Alur: Boot (animasi) -> Beranda daftar profil (ikon avatar SAJA, tanpa
// teks apa pun, supaya language-neutral) -> tombol "+" ikon -> lembar pilihan
// Import / Baru (ikon saja) -> layar interaksi per-profil.
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'emo_engine.dart';
import 'emo_model.dart';
import 'emo_emojis.dart';

const _kBg = Color(0xFF0D0F14);
const _kAccent = Colors.amber;

/// Subset avatar yang dipakai khusus untuk mewakili tiap profil (wajah/
/// makhluk saja, supaya tetap terasa seperti "identitas", bukan emoji acak
/// seperti buah/objek).
const List<String> _kAvatarChoices = [
  '🤖', '👻', '🐶', '🐱', '🦊', '🐼', '🐯', '🐨', '🦄', '🐸', '🐵', '🐰',
  '😺', '🐧', '🦋', '🐢', '👽', '🦁', '🐹', '🦋',
];

// ============================================================================
// BOOT SCREEN — beberapa lapis animasi berjalan bersamaan (ripple berlapis,
// logo berdenyut, progress indeterminate, titik loading bergilir, partikel
// mengambang halus) supaya terasa hidup seperti layar booting Android TV.
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
          // Partikel mengambang halus di latar belakang.
          AnimatedBuilder(
            animation: _floatCtrl,
            builder: (context, _) {
              return CustomPaint(
                size: Size.infinite,
                painter: _FloatingParticlesPainter(_floatCtrl.value),
              );
            },
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
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(color: _kAccent, width: 2),
                                ),
                              ),
                            );
                          },
                        ),
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
                SizedBox(
                  width: 160,
                  height: 4,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: const LinearProgressIndicator(
                      value: null,
                      backgroundColor: Colors.white10,
                      valueColor: AlwaysStoppedAnimation(_kAccent),
                    ),
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
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isActive ? _kAccent : Colors.white24,
                          ),
                        );
                      }),
                    );
                  },
                ),
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
      final x = (size.width * ((seed % 100) / 100));
      final phase = (t + i / 14) % 1.0;
      final y = size.height * (1 - phase);
      final r = 2.0 + (i % 4);
      canvas.drawCircle(Offset(x, y), r, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _FloatingParticlesPainter oldDelegate) => oldDelegate.t != t;
}

// ============================================================================
// BERANDA — grid avatar profil, ikon-saja, plus tombol "+" ikon-saja.
// ============================================================================
class ProfileHomeScreen extends StatefulWidget {
  const ProfileHomeScreen({super.key});
  @override
  State<ProfileHomeScreen> createState() => _ProfileHomeScreenState();
}

class _ProfileHomeScreenState extends State<ProfileHomeScreen> {
  List<EmoProfile>? _profiles;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await ProfileStore.listProfiles();
    if (mounted) setState(() => _profiles = list);
  }

  Future<void> _openAddSheet() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: _kBg,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 24),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _IconChoiceButton(
                icon: Icons.file_open_rounded,
                tooltip: 'Import',
                onTap: () => Navigator.pop(context, 'import'),
              ),
              _IconChoiceButton(
                icon: Icons.auto_awesome_rounded,
                tooltip: 'Baru',
                onTap: () => Navigator.pop(context, 'new'),
              ),
            ],
          ),
        ),
      ),
    );
    if (choice == 'new') {
      await _createNew();
    } else if (choice == 'import') {
      await _import();
    }
  }

  Future<void> _createNew() async {
    final avatar = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: _kBg,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Wrap(
            alignment: WrapAlignment.center,
            spacing: 14,
            runSpacing: 14,
            children: _kAvatarChoices
                .map((e) => GestureDetector(
                      onTap: () => Navigator.pop(context, e),
                      child: CircleAvatar(
                        radius: 28,
                        backgroundColor: Colors.white10,
                        child: Text(e, style: const TextStyle(fontSize: 28)),
                      ),
                    ))
                .toList(),
          ),
        ),
      ),
    );
    if (avatar == null) return;
    await ProfileStore.createNew(avatar);
    await _load();
  }

  Future<void> _import() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['emoai'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final bytes = result.files.first.bytes;
    if (bytes == null) return;
    try {
      await ProfileStore.importFromBytes(bytes);
      await _load();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('File tidak valid')),
        );
      }
    }
  }

  Future<void> _deleteProfile(EmoProfile p) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _kBg,
        content: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            IconButton(
              icon: const Icon(Icons.close_rounded, color: Colors.white54, size: 32),
              onPressed: () => Navigator.pop(context, false),
            ),
            IconButton(
              icon: const Icon(Icons.delete_forever_rounded, color: Colors.redAccent, size: 32),
              onPressed: () => Navigator.pop(context, true),
            ),
          ],
        ),
      ),
    );
    if (confirm == true) {
      await ProfileStore.delete(p.id);
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final profiles = _profiles;
    return Scaffold(
      backgroundColor: _kBg,
      floatingActionButton: FloatingActionButton(
        backgroundColor: _kAccent,
        onPressed: _openAddSheet,
        child: const Icon(Icons.add_rounded, color: Colors.black),
      ),
      body: SafeArea(
        child: profiles == null
            ? const Center(child: CircularProgressIndicator(color: _kAccent))
            : profiles.isEmpty
                ? Center(
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0, end: 1),
                      duration: const Duration(milliseconds: 600),
                      curve: Curves.easeOutBack,
                      builder: (context, v, child) => Opacity(opacity: v.clamp(0, 1), child: Transform.scale(scale: 0.7 + 0.3 * v, child: child)),
                      child: const Text('➕', style: TextStyle(fontSize: 48, color: Colors.white24)),
                    ),
                  )
                : GridView.builder(
                    padding: const EdgeInsets.all(20),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      mainAxisSpacing: 18,
                      crossAxisSpacing: 18,
                    ),
                    itemCount: profiles.length,
                    itemBuilder: (context, i) {
                      final p = profiles[i];
                      return TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0, end: 1),
                        duration: Duration(milliseconds: 350 + i * 60),
                        curve: Curves.easeOutBack,
                        builder: (context, v, child) => Opacity(
                          opacity: v.clamp(0, 1),
                          child: Transform.scale(scale: 0.6 + 0.4 * v, child: child),
                        ),
                        child: GestureDetector(
                          onTap: () async {
                            await Navigator.push(
                              context,
                              PageRouteBuilder(
                                transitionDuration: const Duration(milliseconds: 350),
                                pageBuilder: (_, anim, __) => FadeTransition(
                                  opacity: anim,
                                  child: EmoInteractionScreen(engine: EmoEngine(p)),
                                ),
                              ),
                            );
                            _load();
                          },
                          onLongPress: () => _deleteProfile(p),
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.white10,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            alignment: Alignment.center,
                            child: Text(p.avatar, style: const TextStyle(fontSize: 36)),
                          ),
                        ),
                      );
                    },
                  ),
      ),
    );
  }
}

class _IconChoiceButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  const _IconChoiceButton({required this.icon, required this.tooltip, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(28),
        onTap: onTap,
        child: Container(
          width: 84,
          height: 84,
          decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(28)),
          child: Icon(icon, color: _kAccent, size: 36),
        ),
      ),
    );
  }
}

// ============================================================================
// LAYAR INTERAKSI per-profil — chat sederhana + tombol export (ikon).
// ============================================================================
class EmoInteractionScreen extends StatefulWidget {
  final EmoEngine engine;
  const EmoInteractionScreen({super.key, required this.engine});

  @override
  State<EmoInteractionScreen> createState() => _EmoInteractionScreenState();
}

class _EmoInteractionScreenState extends State<EmoInteractionScreen> with SingleTickerProviderStateMixin {
  final TextEditingController _ctrl = TextEditingController();
  String? _emojis;
  bool _awaitingReview = false;
  late final AnimationController _revealCtrl;

  @override
  void initState() {
    super.initState();
    _revealCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 450));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _revealCtrl.dispose();
    super.dispose();
  }

  void _send() {
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;
    final chain = widget.engine.reply(text);
    setState(() {
      _emojis = chain.emojis.join(' ');
      _awaitingReview = true;
    });
    _revealCtrl.forward(from: 0);
    _ctrl.clear();
  }

  void _review(bool liked) {
    widget.engine.review(liked);
    setState(() => _awaitingReview = false);
  }

  Future<void> _export() async {
    final bytes = ProfileStore.exportBytes(widget.engine.profile);
    final path = await FilePicker.platform.saveFile(
      fileName: '${widget.engine.profile.avatar.hashCode}.emoai',
      bytes: bytes,
    );
    if (mounted && path != null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Berhasil diekspor')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: _kBg,
        elevation: 0,
        title: Text(widget.engine.profile.avatar, style: const TextStyle(fontSize: 22)),
        actions: [
          IconButton(icon: const Icon(Icons.ios_share_rounded, color: Colors.white70), onPressed: _export),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: _emojis == null
                    ? const Text('...', style: TextStyle(color: Colors.white24, fontSize: 40))
                    : ScaleTransition(
                        scale: CurvedAnimation(parent: _revealCtrl, curve: Curves.elasticOut),
                        child: Text(_emojis!, style: const TextStyle(fontSize: 52)),
                      ),
              ),
            ),
            if (_awaitingReview)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _ReviewButton(icon: Icons.thumb_down_rounded, color: Colors.redAccent, onTap: () => _review(false)),
                    _ReviewButton(icon: Icons.thumb_up_rounded, color: Colors.greenAccent, onTap: () => _review(true)),
                  ],
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
                        filled: true,
                        fillColor: Colors.white10,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.send_rounded, color: _kAccent),
                    onPressed: _send,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReviewButton extends StatefulWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  const _ReviewButton({required this.icon, required this.color, required this.onTap});

  @override
  State<_ReviewButton> createState() => _ReviewButtonState();
}

class _ReviewButtonState extends State<_ReviewButton> with SingleTickerProviderStateMixin {
  double _scale = 1.0;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _scale = 0.85),
      onTapUp: (_) => setState(() => _scale = 1.0),
      onTapCancel: () => setState(() => _scale = 1.0),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _scale,
        duration: const Duration(milliseconds: 120),
        child: Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(color: Colors.white10, shape: BoxShape.circle),
          child: Icon(widget.icon, color: widget.color, size: 30),
        ),
      ),
    );
  }
}
