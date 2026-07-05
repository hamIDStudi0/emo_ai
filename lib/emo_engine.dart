// FILE 2: emo_engine.dart — Cognitive Brain & Curiosity Logic
//
// Implements command.md §1 (Core Philosophy & Learning Loop):
//  - Zero Seed: brand-new tokens get their expression from a random
//    "curiosity experiment", never from a hand-picked default.
//  - Curiosity-Driven Experimentation: unresolved (non-anchored) tokens are
//    re-rolled across the full facial + HSL coordinate space every time they
//    recur, until reinforcement locks them down.
//  - Slow & Steady Evolution: a Like doesn't snap the word's permanent
//    profile onto the experimental result — it nudges it there via linear
//    interpolation at `_slowLearningRate`. Only sustained, repeated Likes
//    accumulate enough nudges to fully anchor a behavior.
//  - Human Evaluation Protocol: Like anchors, Dislike penalizes + forces the
//    engine to go looking for different visual territory next time.
import 'dart:convert';
import 'dart:math';
import 'package:shared_preferences/shared_preferences.dart';
import 'emo_model.dart';

/// Clean repository interface so storage can be swapped (tests, cloud sync).
abstract class EmoRepository {
  Future<void> saveNodes(Map<String, EmoWordNode> nodes);
  Future<Map<String, EmoWordNode>> loadNodes();
  Future<void> saveState(EmoState state);
  Future<EmoState?> loadState();
}

/// Local, 100%-offline persistence via SharedPreferences.
class SharedPrefsRepository implements EmoRepository {
  static const _nodesKey = 'emo_nodes_v2';
  static const _stateKey = 'emo_state_v2';

  @override
  Future<void> saveNodes(Map<String, EmoWordNode> nodes) async {
    final prefs = await SharedPreferences.getInstance();
    final map = nodes.map((k, v) => MapEntry(k, v.toJson()));
    await prefs.setString(_nodesKey, jsonEncode(map));
  }

  @override
  Future<Map<String, EmoWordNode>> loadNodes() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_nodesKey);
    if (raw == null) return {};
    final Map<String, dynamic> decoded = jsonDecode(raw);
    return decoded.map((k, v) => MapEntry(k, EmoWordNode.fromJson(v)));
  }

  @override
  Future<void> saveState(EmoState state) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_stateKey, jsonEncode(state.toJson()));
  }

  @override
  Future<EmoState?> loadState() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_stateKey);
    if (raw == null) return null;
    return EmoState.fromJson(jsonDecode(raw));
  }
}

/// Immutable snapshot of everything the view layer needs to draw one frame
/// of the face: facial geometry + full HSL color. Produced either straight
/// from an anchored word's locked-in profile, or from a live curiosity
/// experiment for a word that hasn't been reinforced yet.
class ExpressionFrame {
  final double eyebrowTilt, eyeSize, eyeRotation, mouthDepth, mouthWidth;
  final double hue, saturation, lightness;

  const ExpressionFrame({
    required this.eyebrowTilt,
    required this.eyeSize,
    required this.eyeRotation,
    required this.mouthDepth,
    required this.mouthWidth,
    required this.hue,
    required this.saturation,
    required this.lightness,
  });

  static const neutral = ExpressionFrame(
    eyebrowTilt: 0.0,
    eyeSize: 0.5,
    eyeRotation: 0.0,
    mouthDepth: 0.0,
    mouthWidth: 0.45,
    hue: 42.0,
    saturation: 0.55,
    lightness: 0.58,
  );

  factory ExpressionFrame.fromNode(EmoWordNode n) => ExpressionFrame(
        eyebrowTilt: n.eyebrowTilt,
        eyeSize: n.eyeSize,
        eyeRotation: n.eyeRotation,
        mouthDepth: n.mouthDepth,
        mouthWidth: n.mouthWidth,
        hue: n.hue,
        saturation: n.saturation,
        lightness: n.lightness,
      );

  /// Straight linear interpolation toward [target] by factor [t]. Used both
  /// by the UI's smooth animation and by the engine's own slow-learning step.
  ExpressionFrame lerpTo(ExpressionFrame target, double t) => ExpressionFrame(
        eyebrowTilt: eyebrowTilt + (target.eyebrowTilt - eyebrowTilt) * t,
        eyeSize: eyeSize + (target.eyeSize - eyeSize) * t,
        eyeRotation: eyeRotation + (target.eyeRotation - eyeRotation) * t,
        mouthDepth: mouthDepth + (target.mouthDepth - mouthDepth) * t,
        mouthWidth: mouthWidth + (target.mouthWidth - mouthWidth) * t,
        hue: hue + (target.hue - hue) * t,
        saturation: saturation + (target.saturation - saturation) * t,
        lightness: lightness + (target.lightness - lightness) * t,
      );
}

class EmoEngine {
  final Map<String, EmoWordNode> nodes = {};
  EmoState state = EmoState();
  final EmoRepository repo;
  final Random _rng = Random();

  /// Highly-regulated learning rate: a single Like only nudges a word's
  /// locked profile 3% of the way toward the experimental result. Firmly
  /// locking down a behavior therefore requires consistent reinforcement
  /// over many interactions, never an erratic one-shot jump.
  static const double _slowLearningRate = 0.03;

  /// Number of Likes (of gradual nudges) needed before a word is considered
  /// fully "anchored" and stops re-rolling curiosity experiments.
  static const int _anchorThreshold = 8;

  List<String> _lastTokens = [];

  /// The experimental candidate currently "on trial" for each unanchored
  /// token — i.e. exactly what the user is looking at right now for that
  /// word, kept stable until Like/Dislike resolves it or a fresh, unrelated
  /// experiment is rolled.
  final Map<String, ExpressionFrame> _pending = {};

  EmoEngine(this.repo);

  Future<void> init() async {
    nodes.addAll(await repo.loadNodes());
    final s = await repo.loadState();
    if (s != null) state = s;
  }

  Future<void> persist() async {
    await repo.saveNodes(nodes);
    await repo.saveState(state);
  }

  /// Birthing stage (command.md §4): registers the sacred name once, then
  /// permanently flips the boot flag so the app never asks again.
  Future<void> registerName(String name) async {
    state.isBorn = true;
    state.name = name;
    await persist();
  }

  // 1. Parsing matrix tokenization ------------------------------------------
  List<String> tokenize(String text) => text
      .toLowerCase()
      .split(RegExp(r'[^a-z0-9à-ÿ]+'))
      .where((t) => t.isNotEmpty)
      .toList();

  EmoWordNode _nodeFor(String w) => nodes.putIfAbsent(w, () => EmoWordNode(w));

  double _hueDistance(double a, double b) {
    final d = (a - b).abs() % 360;
    return d > 180 ? 360 - d : d;
  }

  /// Fallback random curiosity experiment selector. Blends brand-new
  /// eyebrow/eye/mouth coordinates and a full HSL color across the entire
  /// legal range. If the word carries an accumulated Dislike penalty, the
  /// hue is resampled until it lands well away from the last rejected
  /// region, so repeated Dislikes actively push exploration elsewhere.
  ExpressionFrame _rollExperiment(EmoWordNode n) {
    double hue = _rng.nextDouble() * 360;
    if (n.penalty > 0.05) {
      var tries = 0;
      while (_hueDistance(hue, n.hue) < 50 && tries < 10) {
        hue = _rng.nextDouble() * 360;
        tries++;
      }
    }
    return ExpressionFrame(
      eyebrowTilt: _rng.nextDouble() * 2 - 1,
      eyeSize: _rng.nextDouble(),
      eyeRotation: _rng.nextDouble() * 2 - 1,
      mouthDepth: _rng.nextDouble() * 2 - 1,
      mouthWidth: _rng.nextDouble(),
      hue: hue,
      saturation: 0.35 + _rng.nextDouble() * 0.55,
      lightness: 0.35 + _rng.nextDouble() * 0.35,
    );
  }

  // 2. Prediction: aggregate word expressions into one face -----------------
  ExpressionFrame predict(String text) {
    final tokens = tokenize(text);
    _lastTokens = tokens;
    if (tokens.isEmpty) return ExpressionFrame.neutral;

    double eb = 0, es = 0, er = 0, md = 0, mw = 0, sat = 0, lig = 0;
    double hueSin = 0, hueCos = 0;

    for (final t in tokens) {
      final n = _nodeFor(t);
      n.freq++;

      final ExpressionFrame active;
      if (n.anchored) {
        active = ExpressionFrame.fromNode(n);
      } else {
        active = _pending.putIfAbsent(t, () => _rollExperiment(n));
      }

      eb += active.eyebrowTilt;
      es += active.eyeSize;
      er += active.eyeRotation;
      md += active.mouthDepth;
      mw += active.mouthWidth;
      sat += active.saturation;
      lig += active.lightness;
      final rad = active.hue * pi / 180;
      hueSin += sin(rad);
      hueCos += cos(rad);
    }

    final count = tokens.length;
    final avgHue = (atan2(hueSin / count, hueCos / count) * 180 / pi + 360) % 360;

    return ExpressionFrame(
      eyebrowTilt: (eb / count).clamp(-1.0, 1.0),
      eyeSize: (es / count).clamp(0.0, 1.0),
      eyeRotation: (er / count).clamp(-1.0, 1.0),
      mouthDepth: (md / count).clamp(-1.0, 1.0),
      mouthWidth: (mw / count).clamp(0.0, 1.0),
      hue: avgHue,
      saturation: (sat / count).clamp(0.0, 1.0),
      lightness: (lig / count).clamp(0.0, 1.0),
    );
  }

  // 3. Human Evaluation Protocol ---------------------------------------------

  /// Like: anchors the active experimental facial parameters to every token
  /// in the last input, for future recall. The anchor is applied gradually
  /// (Lerp at `_slowLearningRate`) so a single Like never causes an abrupt
  /// visual jump — only sustained reinforcement fully locks the behavior in.
  void likeCurrent() {
    if (_lastTokens.isEmpty) return;
    for (final t in _lastTokens) {
      final n = _nodeFor(t);
      final candidate = _pending[t];
      if (candidate != null) {
        final blended = ExpressionFrame.fromNode(n).lerpTo(candidate, _slowLearningRate);
        n.eyebrowTilt = blended.eyebrowTilt;
        n.eyeSize = blended.eyeSize;
        n.eyeRotation = blended.eyeRotation;
        n.mouthDepth = blended.mouthDepth;
        n.mouthWidth = blended.mouthWidth;
        n.hue = blended.hue;
        n.saturation = blended.saturation;
        n.lightness = blended.lightness;
      }
      n.likeCount++;
      n.penalty = (n.penalty - 0.15).clamp(0.0, 6.0);
      if (n.likeCount >= _anchorThreshold) n.anchored = true;
      _pending.remove(t);
    }
    state.interactionCount++;
    persist();
  }

  /// Dislike: appends a penalty multiplier to every token in the last input,
  /// un-anchors it if it had started to settle, and discards its pending
  /// experiment so the next encounter is forced to seek alternative visual
  /// boundaries (see `_rollExperiment`'s hue-avoidance logic).
  void dislikeCurrent() {
    if (_lastTokens.isEmpty) return;
    for (final t in _lastTokens) {
      final n = _nodeFor(t);
      n.dislikeCount++;
      n.penalty = (n.penalty + 0.4).clamp(0.0, 6.0);
      n.anchored = false;
      _pending.remove(t);
    }
    state.interactionCount++;
    persist();
  }
}
