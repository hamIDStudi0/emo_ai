// FILE: emo_emojis.dart — emoji dikelompokkan per keranjang perasaan.
// Overlap antar keranjang (mis. 🥰 ada di happy & love) sengaja dibiarkan —
// mencerminkan tumpang-tindih makna yang wajar, bukan bug.
const List<String> kHappy = [
  '😀','😃','😄','😁','😆','😅','🤣','😂','🙂','😊','😇','🥰','😍','🤩','😘',
  '🥳','😎','🎉','🎊','🎈','🎁','🎵','🎶','💯','✅','🌞','☀️','🌈','✨','⭐',
  '🍀','🏆','💃','🕺','😋','👍','🙌','👏',
];
const List<String> kSadness = [
  '😢','😭','🥺','😞','😔','😟','🙁','☹️','😥','😰','😓','😩','😫','🥱','😪',
  '😴','💔','😧','😦','🌧️','❄️','💧','😕',
];
const List<String> kAnger = [
  '😡','😠','🤬','👿','😤','💢','🔥','👹','👺','🖕','✊','👊','🤜','🤛',
];
const List<String> kFear = [
  '😨','😱','😳','😖','😣','🤯','😵','🥶','🤢','🤮','🤒','🤕','😷','👻','💀',
  '☠️','👽','👾','🤡','😬',
];
const List<String> kLove = [
  '❤️','🧡','💛','💚','💙','💜','🖤','🤍','🤎','❣️','💕','💞','💓','💗','💖',
  '💘','💝','💟','🥰','😍','💋','😘',
];
const List<String> kNetral = [
  '😉','🙃','🤗','🤭','🤫','🤐','😐','😑','😶','😏','😒','🙄','🤥','😌','🧐',
  '😮','😯','😲','🤠','🤓','🥴','🤑','😜','😝','🤪','😛','😗','😙','😚',
  '👋','🤚','🖐️','✋','🖖','👌','🤌','🤏','✌️','🤞','🤟','🤘','🤙','👈','👉',
  '👆','👇','☝️','👎','🤲','🙏','✍️','💅','🤳','💪',
  '🐶','🐱','🐭','🐹','🐰','🦊','🐻','🐼','🐨','🐯','🦁','🐮','🐷','🐸','🐵',
  '🙈','🙉','🙊','🐔','🐧','🐦','🐤','🦄','🐝','🦋','🐢',
  '🍎','🍊','🍋','🍌','🍉','🍇','🍓','🍒','🍑','🥝','🍍','🥑','🍕','🍔','🍟',
  '🌭','🍿','🍩','🍪','🎂','🍰','🍫','☕','🍵',
  '🌝','🌙','⚡','⛅','🌊','🌸','🌹','🌻','🌼','❓','❗','💤','💦','💨','🎮',
  '⚽','🚀','⏰','💡','🔑','💩',
];

/// Map label -> keranjang emoji, dipakai engine untuk membatasi eksplorasi
/// hanya ke emoji yang relevan (bukan semua ~200 lagi untuk tiap label).
const Map<String, List<String>> kBaskets = {
  'happy': kHappy,
  'sadness': kSadness,
  'anger': kAnger,
  'fear': kFear,
  'love': kLove,
  'netral': kNetral,
};

/// Dipertahankan untuk kompatibilitas — union semua keranjang.
List<String> get kEmojiPalette => [...kHappy, ...kSadness, ...kAnger, ...kFear, ...kLove, ...kNetral];
