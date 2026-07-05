# emo.ai

100% offline, self-evolving emotional AI companion for Android (Flutter).
Starts with **zero pre-seeded data** — every word, expression, and answer
probability is learned purely from your "Ya" / "Tidak" / "Mungkin" feedback.

## Structure
```
lib/
  emo_model.dart   # EmoWordNode + EmoState data schema
  emo_engine.dart  # tokenizer, co-occurrence graph, learning, rebellion, homeostasis, storage
  emo_view.dart    # dynamic SVG face (animated) + chat UI
  main.dart        # app entry point
```

## Run
```bash
flutter pub get
flutter run          # plug in an Android device/emulator
```

To build a release APK:
```bash
flutter build apk --release
```

## How it works
- Type a message → `EmoEngine.predict()` tokenizes it, aggregates the known
  weight of each word (plus anything linked to it via the co-occurrence
  graph) into eyebrows / eye-openness / mouth-curve / color values in
  `[-1, 1]`, and the face redraws itself as a fresh SVG, smoothly
  interpolating from the previous expression.
- Tap **Ya / Tidak / Mungkin** → `EmoEngine.learn()` nudges every word from
  that sentence toward the reaction associated with your feedback. If the
  AI's prediction was very wrong, it's an "Emotional Shock" and the
  learning rate doubles for that update.
- Every learning step has a small (5%+) chance of **Stochastic Rebellion** —
  weights invert, mutate randomly, and the face flashes crimson red. The
  chance rises the more bored or stressed the AI's homeostasis state gets.
- `EmoEngine.tickHomeostasis()` can be called on a timer to let stress and
  boredom drift back toward equilibrium on their own between messages.

## Notes / things you may want to tune
- The face SVG is rebuilt as a raw string on every animation frame for
  transparency and 0-byte-asset purity; if you want max render performance
  on very low-end devices, consider caching identical strings or switching
  the SVG markup to a `CustomPainter`.
- Storage is local-only (`SharedPreferences`) — nothing leaves the device.
