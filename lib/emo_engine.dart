// FILE 2: emo_engine.dart — Cognitive Brain & Math Logic
import 'dart:convert';
import 'dart:math';
import 'package:shared_preferences/shared_preferences.dart';
import 'emo_model.dart';

/// Clean repository interface so storage can be swapped (tests, cloud sync, etc).
abstract class EmoRepository {
  Future<void> saveNodes(Map<String, EmoWordNode> nodes);
  Future<Map<String, EmoWordNode>> loadNodes();
  Future<void> saveState(EmoState state);
  Future<EmoState?> loadState();
}

/// Local, 100%-offline persistence via SharedPreferences.
class SharedPrefsRepository implements EmoRepository {
  static const _nodesKey = 'emo_nodes_v1';
  static const _stateKey = 'emo_state_v1';

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

/// Result of aggregating known words into a facial expression.
class FacePrediction {
  final double eyebrows, eyeOpenness, mouthCurve, colorShift;
  final String dominantAnswer;
  const FacePrediction(
    this.eyebrows,
    this.eyeOpenness,
    this.mouthCurve,
    this.colorShift,
    this.dominantAnswer,
  );

  static const neutral = FacePrediction(0, 0, 0, 0, 'Mungkin');
}

class EmoEngine {
  final Map<String, EmoWordNode> nodes = {};
  EmoState state = EmoState();
  final EmoRepository repo;
  final Random _rng = Random();

  List<String> _lastTokens = [];
  bool emotionalShock = false;
  static const double _baseLearningRate = 0.15;

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

  // 1. Lowercase tokenization -----------------------------------------------
  List<String> tokenize(String text) => text
      .toLowerCase()
      .split(RegExp(r'[^a-z0-9à-ÿ]+'))
      .where((t) => t.isNotEmpty)
      .toList();

  EmoWordNode _nodeFor(String w) => nodes.putIfAbsent(w, () => EmoWordNode(w));

  /// Implicit contextual graph: every token that co-occurs with another in the
  /// same sentence strengthens a link between them, so meaning spreads even to
  /// words the AI has never been directly rewarded/punished for.
  void _buildGraph(List<String> tokens) {
    for (int i = 0; i < tokens.length; i++) {
      final node = _nodeFor(tokens[i]);
      node.freq++;
      for (int j = 0; j < tokens.length; j++) {
        if (i == j) continue;
        final other = tokens[j];
        node.links[other] = (node.links[other] ?? 0) + 0.1;
      }
    }
  }

  // 2. Prediction: aggregate word weights into face parameters --------------
  FacePrediction predict(String text) {
    final tokens = tokenize(text);
    _lastTokens = tokens;
    if (tokens.isEmpty) return FacePrediction.neutral;

    double eb = 0, eo = 0, mc = 0, cs = 0, totalWeight = 0;
    final ansAgg = {'Ya': 0.0, 'Tidak': 0.0, 'Mungkin': 0.0};

    for (final t in tokens) {
      final n = nodes[t];
      if (n == null) continue;
      final w = 1.0 + (n.freq * 0.05);
      eb += n.eyebrows * w;
      eo += n.eyeOpenness * w;
      mc += n.mouthCurve * w;
      cs += n.colorShift * w;
      n.answerProb.forEach((k, v) => ansAgg[k] = ansAgg[k]! + v * w);

      // Spread through the co-occurrence graph (synonym-like generalization).
      n.links.forEach((linkedWord, strength) {
        final ln = nodes[linkedWord];
        if (ln == null) return;
        eb += ln.eyebrows * strength * 0.3;
        eo += ln.eyeOpenness * strength * 0.3;
        mc += ln.mouthCurve * strength * 0.3;
        cs += ln.colorShift * strength * 0.3;
      });
      totalWeight += w;
    }
    if (totalWeight == 0) totalWeight = 1;
    eb /= totalWeight;
    eo /= totalWeight;
    mc /= totalWeight;
    cs /= totalWeight;

    final dominant =
        ansAgg.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
    return FacePrediction(
      eb.clamp(-1.0, 1.0),
      eo.clamp(-1.0, 1.0),
      mc.clamp(-1.0, 1.0),
      cs.clamp(-1.0, 1.0),
      dominant,
    );
  }

  // 3+4+5. Learning, dynamic rate, rebellion, homeostasis -------------------
  /// Call after the user taps Ya / Tidak / Mungkin in reply to the AI's last
  /// reaction to `predict()`'s input.
  void learn(String feedback) {
    if (_lastTokens.isEmpty) return;
    _buildGraph(_lastTokens);

    late double targetEb, targetEo, targetMc, targetCs;
    switch (feedback) {
      case 'Ya':
        targetEb = -0.6;
        targetEo = 0.7;
        targetMc = 0.8;
        targetCs = -0.3;
        state.stress = (state.stress - 0.05).clamp(0.0, 1.0);
        state.boredom = (state.boredom - 0.03).clamp(0.0, 1.0);
        break;
      case 'Tidak':
        targetEb = 0.7;
        targetEo = -0.4;
        targetMc = -0.8;
        targetCs = 0.4;
        state.stress = (state.stress + 0.12).clamp(0.0, 1.0);
        break;
      default: // Mungkin
        targetEb = 0.1;
        targetEo = 0.0;
        targetMc = -0.1;
        targetCs = 0.1;
        state.boredom = (state.boredom + 0.08).clamp(0.0, 1.0);
    }

    // Emotional Shock: if current prediction is far from the target reaction,
    // learn twice as fast this round.
    final prediction = predict(_lastTokens.join(' '));
    final error = (targetEb - prediction.eyebrows).abs() +
        (targetMc - prediction.mouthCurve).abs();
    emotionalShock = error > 1.2;
    final lr = _baseLearningRate * (emotionalShock ? 2.0 : 1.0);

    for (final t in _lastTokens) {
      final n = _nodeFor(t);
      n.eyebrows += (targetEb - n.eyebrows) * lr;
      n.eyeOpenness += (targetEo - n.eyeOpenness) * lr;
      n.mouthCurve += (targetMc - n.mouthCurve) * lr;
      n.colorShift += (targetCs - n.colorShift) * lr;

      n.answerProb.updateAll(
        (k, v) => k == feedback ? v + lr * 0.5 : v - lr * 0.15,
      );
      final sum = n.answerProb.values.fold(0.0, (a, b) => a + b);
      if (sum > 0) {
        n.answerProb.updateAll((k, v) => (v / sum).clamp(0.0, 1.0));
      }
    }

    state.homeostasis = (state.homeostasis +
            (feedback == 'Ya' ? 0.05 : feedback == 'Tidak' ? -0.05 : 0.0))
        .clamp(0.0, 1.0);
    state.interactionCount++;
    if (state.interactionCount % 10 == 0) state.level++;

    maybeRebel();
    persist();
  }

  /// 5% baseline chaos, rising sharply with boredom/stress.
  bool maybeRebel() {
    final chance = 0.05 + state.boredom * 0.25 + state.stress * 0.25;
    if (_rng.nextDouble() < chance) {
      _triggerRebellion();
      return true;
    }
    return false;
  }

  void _triggerRebellion() {
    for (final n in nodes.values) {
      if (_rng.nextDouble() < 0.4) {
        n.eyebrows *= -1;
        n.mouthCurve *= -1;
      }
      n.eyebrows = (n.eyebrows + (_rng.nextDouble() * 0.6 - 0.3)).clamp(-1.0, 1.0);
      n.eyeOpenness = (n.eyeOpenness + (_rng.nextDouble() * 0.6 - 0.3)).clamp(-1.0, 1.0);
      n.mouthCurve = (n.mouthCurve + (_rng.nextDouble() * 0.6 - 0.3)).clamp(-1.0, 1.0);
      n.colorShift = 1.0; // crimson red shift
    }
    state.stress = (state.stress + 0.2).clamp(0.0, 1.0);
    state.boredom = 0.0;
  }

  /// 6. Homeostasis tick — call periodically (e.g. every few seconds of idle
  /// time) so the AI actively drifts back toward equilibrium and, when
  /// stressed, becomes more eager to seek the user's approval.
  void tickHomeostasis() {
    if (state.stress > 0.6) {
      state.homeostasis = (state.homeostasis - 0.02).clamp(0.0, 1.0);
    } else {
      state.stress = (state.stress - 0.01).clamp(0.0, 1.0);
      state.homeostasis = (state.homeostasis + 0.01).clamp(0.0, 1.0);
    }
    state.boredom = (state.boredom + 0.005).clamp(0.0, 1.0);
  }

  /// True while the AI is actively trying to win back approval (used by the
  /// UI to nudge copy/animation toward "seeking approval" behavior).
  bool get isSeekingApproval => state.stress > 0.6;
}
