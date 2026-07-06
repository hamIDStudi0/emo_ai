// FILE: emo_emojis.dart — The Real Emoji Palette
//
// A curated cross-section of the same families Windows' emoji picker groups
// under Smileys, People (esp. hand gestures — explicitly requested), Nature,
// Food, Activities, Objects and Symbols. This is intentionally a broad,
// hand-picked subset (~200 glyphs) rather than the full multi-thousand
// Unicode emoji set: every entry here is a single, simple codepoint (or a
// codepoint + variation selector), so it always renders as one clean glyph
// on-device. Full multi-person/skin-tone ZWJ sequences are deliberately
// left out to avoid ever rendering a broken/split glyph.
//
// The engine (emo_engine.dart) never hand-picks *which* emoji means what —
// it only samples from this flat pool and lets Like/Dislike reinforcement
// decide which glyphs end up associated with which words over time.
const List<String> kEmojiPalette = [
  // --- Faces / expressions ------------------------------------------------
  '😀', '😃', '😄', '😁', '😆', '😅', '🤣', '😂', '🙂', '🙃', '😉', '😊', '😇',
  '🥰', '😍', '🤩', '😘', '😗', '😚', '😙', '😋', '😛', '😜', '🤪', '😝', '🤑',
  '🤗', '🤭', '🤫', '🤔', '🤐', '😐', '😑', '😶', '😏', '😒', '🙄', '😬', '🤥',
  '😌', '😔', '😪', '🤤', '😴', '😷', '🤒', '🤕', '🤢', '🤮', '🤧', '🥵', '🥶',
  '🥴', '😵', '🤯', '🤠', '🥳', '😎', '🤓', '🧐', '😕', '😟', '🙁', '☹️', '😮',
  '😯', '😲', '😳', '🥺', '😦', '😧', '😨', '😰', '😥', '😢', '😭', '😱', '😖',
  '😣', '😞', '😓', '😩', '😫', '🥱', '😤', '😡', '😠', '🤬', '😈', '👿', '💀',
  '☠️', '🤡', '👹', '👺', '👻', '👽', '👾', '🤖', '💩',

  // --- Hands / gestures (explicitly requested — kept extensive) ----------
  '👋', '🤚', '🖐️', '✋', '🖖', '👌', '🤌', '🤏', '✌️', '🤞', '🤟', '🤘', '🤙',
  '👈', '👉', '👆', '🖕', '👇', '☝️', '👍', '👎', '✊', '👊', '🤛', '🤜', '👏',
  '🙌', '👐', '🤲', '🙏', '✍️', '💅', '🤳', '💪',

  // --- Hearts --------------------------------------------------------------
  '❤️', '🧡', '💛', '💚', '💙', '💜', '🖤', '🤍', '🤎', '💔', '❣️', '💕', '💞',
  '💓', '💗', '💖', '💘', '💝', '💟',

  // --- Animals ---------------------------------------------------------------
  '🐶', '🐱', '🐭', '🐹', '🐰', '🦊', '🐻', '🐼', '🐨', '🐯', '🦁', '🐮', '🐷',
  '🐸', '🐵', '🙈', '🙉', '🙊', '🐔', '🐧', '🐦', '🐤', '🦄', '🐝', '🦋', '🐢',

  // --- Food / drink ----------------------------------------------------------
  '🍎', '🍊', '🍋', '🍌', '🍉', '🍇', '🍓', '🍒', '🍑', '🥝', '🍍', '🥑', '🍕',
  '🍔', '🍟', '🌭', '🍿', '🍩', '🍪', '🎂', '🍰', '🍫', '☕', '🍵',

  // --- Nature / weather --------------------------------------------------
  '🌞', '🌝', '🌙', '⭐', '✨', '⚡', '🔥', '💧', '🌈', '☀️', '⛅', '🌧️', '❄️',
  '🌊', '🌸', '🌹', '🌻', '🌼', '🍀',

  // --- Activities / objects / symbols -------------------------------------
  '🎉', '🎊', '🎈', '🎁', '🎵', '🎶', '💯', '✅', '❌', '❓', '❗', '💤', '💢',
  '💦', '💨', '🕺', '💃', '🎮', '⚽', '🏆', '🚀', '⏰', '💡', '🔑',
];
