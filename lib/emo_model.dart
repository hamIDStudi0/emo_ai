// FILE 1: emo_model.dart — Architecture & State Schema
//
// PURE TABULA RASA: every EmoWordNode is born fully neutral. Nothing about
// how a word "should" look is pre-seeded — every facial trait attached to a
// token is discovered later, only through the curiosity engine's random
// experiments plus human Like/Dislike reinforcement (see emo_engine.dart).
//
// This file only declares data. No randomness, no learning-rate math, and
// no UI code live here — that separation is the whole point of the 3-pillar
// architecture described in command.md.

/// A single learned word/token and the facial expression currently bound to
/// it. Geometric fields are normalized so the view layer can map them
/// straight onto SVG coordinates without extra scaling logic:
///   eyebrowTilt : -1.0 (furrowed)      .. 1.0 (raised)
///   eyeSize     :  0.0 (nearly closed) .. 1.0 (wide open)
///   eyeRotation : -1.0 (tilt down/in)  .. 1.0 (tilt up/out)
///   mouthDepth  : -1.0 (deep frown)    .. 1.0 (deep smile)
///   mouthWidth  :  0.0 (pursed)        .. 1.0 (wide)
///   hue         :  0 .. 360   (full HSL color wheel)
///   saturation  :  0.0 .. 1.0 (HSL)
///   lightness   :  0.0 .. 1.0 (HSL)
class EmoWordNode {
  final String word;

  // --- Facial coordinate space, HSL color space ---------------------------
  double eyebrowTilt;
  double eyeSize;
  double eyeRotation;
  double mouthDepth;
  double mouthWidth;
  double hue;
  double saturation;
  double lightness;

  // --- Analytical feedback weights (curiosity + reinforcement bookkeeping) -
  int likeCount;
  int dislikeCount;
  double penalty; // rises on Dislike; steers future random experiments away
  bool anchored; // true once reinforcement has "locked" this word's look
  int freq; // number of times this token has ever been encountered

  EmoWordNode(
    this.word, {
    this.eyebrowTilt = 0.0,
    this.eyeSize = 0.5,
    this.eyeRotation = 0.0,
    this.mouthDepth = 0.0,
    this.mouthWidth = 0.45,
    this.hue = 42.0,
    this.saturation = 0.55,
    this.lightness = 0.58,
    this.likeCount = 0,
    this.dislikeCount = 0,
    this.penalty = 0.0,
    this.anchored = false,
    this.freq = 0,
  });

  factory EmoWordNode.fromJson(Map<String, dynamic> j) => EmoWordNode(
        j['word'] as String,
        eyebrowTilt: (j['eyebrowTilt'] as num).toDouble(),
        eyeSize: (j['eyeSize'] as num).toDouble(),
        eyeRotation: (j['eyeRotation'] as num).toDouble(),
        mouthDepth: (j['mouthDepth'] as num).toDouble(),
        mouthWidth: (j['mouthWidth'] as num).toDouble(),
        hue: (j['hue'] as num).toDouble(),
        saturation: (j['saturation'] as num).toDouble(),
        lightness: (j['lightness'] as num).toDouble(),
        likeCount: j['likeCount'] as int,
        dislikeCount: j['dislikeCount'] as int,
        penalty: (j['penalty'] as num).toDouble(),
        anchored: j['anchored'] as bool,
        freq: j['freq'] as int,
      );

  Map<String, dynamic> toJson() => {
        'word': word,
        'eyebrowTilt': eyebrowTilt,
        'eyeSize': eyeSize,
        'eyeRotation': eyeRotation,
        'mouthDepth': mouthDepth,
        'mouthWidth': mouthWidth,
        'hue': hue,
        'saturation': saturation,
        'lightness': lightness,
        'likeCount': likeCount,
        'dislikeCount': dislikeCount,
        'penalty': penalty,
        'anchored': anchored,
        'freq': freq,
      };
}

/// Lifecycle + identity state.
///
/// Deliberately holds NO visible-analytics fields. Per command.md §3/§CRITICAL
/// DIRECTIVES, the app must never surface boredom percentages, stress bars,
/// or any other numeric readout on the main screen. `isBorn` / `name` exist
/// purely to gate the one-time birthing ritual (§4); `interactionCount` is
/// internal bookkeeping only and is never rendered.
class EmoState {
  bool isBorn;
  String name;
  int interactionCount;

  EmoState({
    this.isBorn = false,
    this.name = '',
    this.interactionCount = 0,
  });

  factory EmoState.fromJson(Map<String, dynamic> j) => EmoState(
        isBorn: j['isBorn'] as bool,
        name: j['name'] as String,
        interactionCount: j['interactionCount'] as int,
      );

  Map<String, dynamic> toJson() => {
        'isBorn': isBorn,
        'name': name,
        'interactionCount': interactionCount,
      };
}
