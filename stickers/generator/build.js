const path = require('path');
const { renderPack, contactSheet } = require('./render');

// FREE pack — everyday reactions. emoji = suggested Telegram emoji.
const FREE = [
  { name: 'hi',        emoji: '👋', eyes: 'normal', mouth: 'smile' },
  { name: 'happy',     emoji: '😃', eyes: 'happy',  mouth: 'grin' },
  { name: 'love',      emoji: '😍', eyes: 'heart',  mouth: 'smallSmile', props: ['floatHearts', 'blush'] },
  { name: 'lol',       emoji: '😂', eyes: 'happy',  mouth: 'bigOpen', props: ['tearsBig'] },
  { name: 'cool',      emoji: '😎', eyes: 'side',   mouth: 'smirk', props: ['sunglasses'] },
  { name: 'wow',       emoji: '😮', eyes: 'wide',   mouth: 'shockO' },
  { name: 'wink',      emoji: '😉', eyes: 'wink',   mouth: 'smirk' },
  { name: 'tongue',    emoji: '😜', eyes: 'happy',  mouth: 'tongue' },
  { name: 'star',      emoji: '🤩', eyes: 'star',   mouth: 'grin' },
  { name: 'shy',       emoji: '☺️', eyes: 'happy',  mouth: 'smallSmile', props: ['blush'] },
  { name: 'think',     emoji: '🤔', eyes: 'normal', mouth: 'flat', props: ['sweat'] },
  { name: 'sleep',     emoji: '😴', eyes: 'happy',  mouth: 'flat', props: ['zzz'] },
  { name: 'sad',       emoji: '😢', eyes: 'teary',  mouth: 'frown' },
  { name: 'cry',       emoji: '😭', eyes: 'teary',  mouth: 'cry', props: ['tearsBig'] },
  { name: 'angry',     emoji: '😠', eyes: 'angry',  mouth: 'frown' },
  { name: 'dead',      emoji: '💀', eyes: 'dead',   mouth: 'flat' },
];

// PREMIUM pack — status/flex + spicy 18+ sub-tier (last 5).
const PREMIUM = [
  { name: 'king',      emoji: '👑', eyes: 'side',  mouth: 'smirk',  behind: ['crown'] },
  { name: 'rich',      emoji: '🤑', eyes: 'money', mouth: 'grin' },
  { name: 'fire',      emoji: '🔥', eyes: 'angry', mouth: 'grin',   behind: ['fireAura'] },
  { name: 'sigma',     emoji: '🗿', eyes: 'side',  mouth: 'flat',   props: ['sunglasses'] },
  { name: 'genius',    emoji: '🧠', eyes: 'glow',  mouth: 'smirk' },
  { name: 'strong',    emoji: '💪', eyes: 'angry', mouth: 'grin',   props: ['muscleArms'] },
  { name: 'mindblown', emoji: '🤯', eyes: 'wide',  mouth: 'shockO', props: ['sweat'] },
  { name: 'rage',      emoji: '😡', eyes: 'angry', mouth: 'bigOpen', behind: ['fireAura'] },
  { name: 'evil',      emoji: '😈', eyes: 'angry', mouth: 'grin',   behind: ['devilHorns'] },
  { name: 'champion',  emoji: '🏆', eyes: 'star',  mouth: 'grin',   behind: ['crown'] },
  { name: 'zen',       emoji: '🧘', eyes: 'happy', mouth: 'smallSmile' },
  // ---- 18+ spicy sub-tier ----
  { name: 'flirt',     emoji: '😘', eyes: 'wink',  mouth: 'kiss',   props: ['floatHearts'] },
  { name: 'kiss',      emoji: '💋', eyes: 'happy', mouth: 'kiss',   props: ['floatHearts', 'blush'] },
  { name: 'rude',      emoji: '🖕', eyes: 'angry', mouth: 'smirk',  props: ['rudeHand'] },
  { name: 'drunk',     emoji: '🥴', eyes: 'dizzy', mouth: 'tongue', props: ['bottle', 'blush'] },
  { name: 'naughty',   emoji: '😏', eyes: 'side',  mouth: 'tongue', behind: ['devilHorns'], props: ['sweat'] },
];

const OUT = __dirname;
renderPack('FREE',    FREE,    path.join(OUT, 'out', 'sigma-free'));
renderPack('PREMIUM', PREMIUM, path.join(OUT, 'out', 'sigma-premium'));
contactSheet(FREE,    path.join(OUT, 'preview_free.png'),    4, 300);
contactSheet(PREMIUM, path.join(OUT, 'preview_premium.png'), 4, 300);

module.exports = { FREE, PREMIUM };
