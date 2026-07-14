// Sigma mascot sticker generator — blue Σ blob character.
// Exports buildSVG(spec) -> 512x512 SVG string with transparent bg + white sticker outline.

const W = 512;

// ---- palette ---------------------------------------------------------------
const BLUE1 = '#6E92FF';   // light (top-left)
const BLUE2 = '#4F7CFF';   // brand blue
const BLUE3 = '#3A63E0';   // shadow
const INK   = '#12203A';   // dark features
const WHITE = '#FFFFFF';

// ---- eyes ------------------------------------------------------------------
// each returns svg for both eyes. lx/rx eye centers, ey eye line.
const LX = 198, RX = 314, EY = 250, ER = 40;

function eyeWhite(cx, cy, rx, ry) {
  return `<ellipse cx="${cx}" cy="${cy}" rx="${rx}" ry="${ry}" fill="${WHITE}"/>`;
}
function pupil(cx, cy, r, dx = 0, dy = 4) {
  return `<circle cx="${cx + dx}" cy="${cy + dy}" r="${r}" fill="${INK}"/>` +
         `<circle cx="${cx + dx - r * 0.32}" cy="${cy + dy - r * 0.4}" r="${r * 0.32}" fill="${WHITE}"/>`;
}

const EYES = {
  normal: () => eyeWhite(LX, EY, ER, ER + 4) + eyeWhite(RX, EY, ER, ER + 4) +
                pupil(LX, EY, 20) + pupil(RX, EY, 20),
  happy: () => // upward curved ^ eyes
    `<path d="M ${LX-34} ${EY+6} Q ${LX} ${EY-40} ${LX+34} ${EY+6}" stroke="${INK}" stroke-width="16" fill="none" stroke-linecap="round"/>` +
    `<path d="M ${RX-34} ${EY+6} Q ${RX} ${EY-40} ${RX+34} ${EY+6}" stroke="${INK}" stroke-width="16" fill="none" stroke-linecap="round"/>`,
  heart: () => heart(LX, EY, 40, '#FF4D6D') + heart(RX, EY, 40, '#FF4D6D'),
  wide: () => eyeWhite(LX, EY, ER+6, ER+12) + eyeWhite(RX, EY, ER+6, ER+12) +
              pupil(LX, EY, 14, 0, 0) + pupil(RX, EY, 14, 0, 0),
  star: () => star(LX, EY, 44, '#FFD84D') + star(RX, EY, 44, '#FFD84D'),
  money: () => eyeWhite(LX, EY, ER, ER+4) + eyeWhite(RX, EY, ER, ER+4) +
    `<text x="${LX}" y="${EY+18}" font-family="Arial Black,Arial" font-size="52" font-weight="900" fill="#2ECC71" text-anchor="middle">$</text>` +
    `<text x="${RX}" y="${EY+18}" font-family="Arial Black,Arial" font-size="52" font-weight="900" fill="#2ECC71" text-anchor="middle">$</text>`,
  dead: () => cross(LX, EY, 30) + cross(RX, EY, 30),
  angry: () => eyeWhite(LX, EY+6, ER, ER) + eyeWhite(RX, EY+6, ER, ER) +
    pupil(LX, EY+10, 20, 4, 2) + pupil(RX, EY+10, 20, -4, 2) +
    `<path d="M ${LX-42} ${EY-40} L ${LX+30} ${EY-14}" stroke="${INK}" stroke-width="18" stroke-linecap="round"/>` +
    `<path d="M ${RX+42} ${EY-40} L ${RX-30} ${EY-14}" stroke="${INK}" stroke-width="18" stroke-linecap="round"/>`,
  teary: () => eyeWhite(LX, EY, ER, ER+8) + eyeWhite(RX, EY, ER, ER+8) +
    pupil(LX, EY+8, 22, 0, 4) + pupil(RX, EY+8, 22, 0, 4) +
    `<path d="M ${LX-30} ${EY+30} q -18 40 -6 70 q 12 -30 6 -70" fill="#7FD4FF"/>` +
    `<path d="M ${RX+30} ${EY+30} q 18 40 6 70 q -12 -30 -6 -70" fill="#7FD4FF"/>`,
  dizzy: () => spiral(LX, EY) + spiral(RX, EY),
  wink: () => `<path d="M ${LX-34} ${EY} Q ${LX} ${EY-34} ${LX+34} ${EY}" stroke="${INK}" stroke-width="16" fill="none" stroke-linecap="round"/>` +
              eyeWhite(RX, EY, ER, ER+4) + pupil(RX, EY, 20),
  side: () => // sigma stare — half-lidded looking to side
    eyeWhite(LX, EY, ER, ER-6) + eyeWhite(RX, EY, ER, ER-6) +
    pupil(LX, EY, 20, 14, 0) + pupil(RX, EY, 20, 14, 0) +
    `<path d="M ${LX-ER} ${EY-8} q ${ER} -22 ${ER*2} 0" fill="${BLUE2}"/>` +
    `<path d="M ${RX-ER} ${EY-8} q ${ER} -22 ${ER*2} 0" fill="${BLUE2}"/>`,
  glow: () => // intense glowing eyes
    `<ellipse cx="${LX}" cy="${EY}" rx="${ER}" ry="${ER}" fill="#BFE3FF"/>` +
    `<ellipse cx="${RX}" cy="${EY}" rx="${ER}" ry="${ER}" fill="#BFE3FF"/>` +
    `<circle cx="${LX}" cy="${EY}" r="16" fill="#2E8BFF"/><circle cx="${RX}" cy="${EY}" r="16" fill="#2E8BFF"/>`,
};

// ---- mouths ----------------------------------------------------------------
const MY = 328;
const MOUTHS = {
  smile: () => `<path d="M ${256-46} ${MY} Q 256 ${MY+52} ${256+46} ${MY}" stroke="${INK}" stroke-width="16" fill="none" stroke-linecap="round"/>`,
  smallSmile: () => `<path d="M ${256-30} ${MY} Q 256 ${MY+30} ${256+30} ${MY}" stroke="${INK}" stroke-width="14" fill="none" stroke-linecap="round"/>`,
  bigOpen: () => `<path d="M ${256-56} ${MY-6} Q 256 ${MY+80} ${256+56} ${MY-6} Q 256 ${MY+18} ${256-56} ${MY-6} Z" fill="${INK}"/>` +
                 `<path d="M ${256-30} ${MY+40} Q 256 ${MY+68} ${256+30} ${MY+40} Q 256 ${MY+30} ${256-30} ${MY+40} Z" fill="#FF6B7D"/>`,
  frown: () => `<path d="M ${256-42} ${MY+34} Q 256 ${MY-20} ${256+42} ${MY+34}" stroke="${INK}" stroke-width="16" fill="none" stroke-linecap="round"/>`,
  shockO: () => `<ellipse cx="256" cy="${MY+18}" rx="30" ry="40" fill="${INK}"/>`,
  flat: () => `<path d="M ${256-40} ${MY+10} L ${256+40} ${MY+10}" stroke="${INK}" stroke-width="14" stroke-linecap="round"/>`,
  smirk: () => `<path d="M ${256-30} ${MY+14} Q ${256+20} ${MY+30} ${256+52} ${MY-8}" stroke="${INK}" stroke-width="16" fill="none" stroke-linecap="round"/>`,
  grin: () => `<path d="M ${256-58} ${MY-4} Q 256 ${MY+70} ${256+58} ${MY-4} Z" fill="${INK}"/>` +
              `<path d="M ${256-58} ${MY-4} L ${256+58} ${MY-4}" stroke="${WHITE}" stroke-width="14"/>` +
              `<rect x="${256-52}" y="${MY-8}" width="104" height="16" fill="${WHITE}"/>`,
  tongue: () => `<path d="M ${256-46} ${MY-6} Q 256 ${MY+46} ${256+46} ${MY-6} Z" fill="${INK}"/>` +
                `<path d="M ${256-22} ${MY+16} q 22 60 44 0 Z" fill="#FF6B7D"/>`,
  kiss: () => `<path d="M ${256-14} ${MY+6} q -22 12 0 24 q 22 -12 0 -24" fill="#FF4D6D"/>` +
              `<path d="M ${256+6} ${MY+2} q 26 14 0 32 q -18 -16 0 -32" fill="#FF4D6D"/>`,
  cry: () => `<path d="M ${256-40} ${MY+4} q 20 40 40 0 q 20 40 0 0" stroke="${INK}" stroke-width="14" fill="none" stroke-linecap="round"/>` +
             `<path d="M ${256-40} ${MY+30} q 40 -50 80 0 q -40 60 -80 0 Z" fill="${INK}"/>`,
};

// ---- props / glyphs --------------------------------------------------------
function heart(cx, cy, s, color) {
  const k = s / 40;
  return `<path transform="translate(${cx},${cy}) scale(${k})" d="M0 22 C -30 -8 -22 -34 0 -14 C 22 -34 30 -8 0 22 Z" fill="${color}"/>`;
}
function star(cx, cy, s, color) {
  let pts = '';
  for (let i = 0; i < 10; i++) {
    const r = i % 2 ? s * 0.42 : s;
    const a = -Math.PI / 2 + i * Math.PI / 5;
    pts += `${(cx + r * Math.cos(a)).toFixed(1)},${(cy + r * Math.sin(a)).toFixed(1)} `;
  }
  return `<polygon points="${pts}" fill="${color}"/>`;
}
function cross(cx, cy, s) {
  return `<path d="M ${cx-s} ${cy-s} L ${cx+s} ${cy+s} M ${cx+s} ${cy-s} L ${cx-s} ${cy+s}" stroke="${INK}" stroke-width="16" stroke-linecap="round"/>`;
}
function spiral(cx, cy) {
  return `<path d="M ${cx} ${cy} m 0 -30 a 30 30 0 1 1 -21 9 a 20 20 0 1 1 14 -6 a 11 11 0 1 1 -7 4" stroke="${INK}" stroke-width="9" fill="none"/>`;
}
function sunglasses() {
  return `<g>
    <rect x="150" y="222" width="90" height="56" rx="14" fill="#101828"/>
    <rect x="272" y="222" width="90" height="56" rx="14" fill="#101828"/>
    <rect x="238" y="240" width="36" height="12" fill="#101828"/>
    <path d="M 120 232 L 152 236" stroke="#101828" stroke-width="12" stroke-linecap="round"/>
    <path d="M 392 232 L 360 236" stroke="#101828" stroke-width="12" stroke-linecap="round"/>
    <path d="M 162 234 l 30 30" stroke="#3A5BFF" stroke-width="10" stroke-linecap="round" opacity="0.7"/>
    <path d="M 284 234 l 30 30" stroke="#3A5BFF" stroke-width="10" stroke-linecap="round" opacity="0.7"/>
  </g>`;
}
function crown() {
  return `<g transform="translate(256,120)">
    <path d="M -70 10 L -70 -34 L -34 -6 L 0 -50 L 34 -6 L 70 -34 L 70 10 Z" fill="#FFD84D" stroke="#E0A400" stroke-width="6" stroke-linejoin="round"/>
    <circle cx="-70" cy="-34" r="9" fill="#FFE98A"/><circle cx="0" cy="-50" r="10" fill="#FFE98A"/><circle cx="70" cy="-34" r="9" fill="#FFE98A"/>
    <circle cx="0" cy="-6" r="8" fill="#FF5C7A"/>
  </g>`;
}
function fireAura() {
  return `<g opacity="0.95">
    <path d="M 128 430 q -34 -60 6 -110 q -6 44 26 40 q -30 -70 34 -120 q -10 70 40 96 q 34 20 22 74 Z" fill="#FF7A2E"/>
    <path d="M 356 430 q 40 -70 -6 -120 q 8 46 -26 42 q 30 -70 -30 -118 q 12 66 -40 92 q -36 22 -20 76 Z" fill="#FF9E3D"/>
  </g>`;
}
function tearsBig() {
  return `<path d="M ${LX-38} ${EY+34} q -22 46 -8 82 q 14 -34 8 -82" fill="#7FD4FF"/>` +
         `<path d="M ${RX+38} ${EY+34} q 22 46 8 82 q -14 -34 -8 -82" fill="#7FD4FF"/>`;
}
function blush() {
  return `<ellipse cx="${LX-6}" cy="${EY+58}" rx="30" ry="16" fill="#FF7DA3" opacity="0.55"/>` +
         `<ellipse cx="${RX+6}" cy="${EY+58}" rx="30" ry="16" fill="#FF7DA3" opacity="0.55"/>`;
}
function sweat() {
  return `<path d="M 372 176 q 26 34 12 58 q -30 6 -30 -22 q 0 -22 18 -36 Z" fill="#8FDcFF"/>`;
}
function floatHearts() {
  return heart(150, 150, 26, '#FF4D6D') + heart(372, 132, 34, '#FF6B84') + heart(400, 210, 20, '#FF4D6D');
}
function zzz() {
  return `<text x="380" y="180" font-family="Arial Black,Arial" font-size="60" font-weight="900" fill="${WHITE}" opacity="0.9">Z</text>` +
         `<text x="420" y="140" font-family="Arial Black,Arial" font-size="40" font-weight="900" fill="${WHITE}" opacity="0.7">z</text>`;
}
function rudeHand() {
  // stylized fist with raised middle finger (cheeky 18+)
  return `<g transform="translate(360,300)">
    <rect x="-6" y="-96" width="40" height="120" rx="18" fill="${BLUE1}" stroke="${WHITE}" stroke-width="10"/>
    <rect x="-40" y="-6" width="96" height="86" rx="30" fill="${BLUE1}" stroke="${WHITE}" stroke-width="10"/>
    <rect x="-6" y="-92" width="40" height="116" rx="18" fill="${BLUE1}"/>
  </g>`;
}
function bottle() {
  return `<g transform="translate(150,300) rotate(-18)">
    <rect x="-16" y="-70" width="32" height="20" rx="4" fill="#6b4a2b"/>
    <rect x="-26" y="-52" width="52" height="110" rx="16" fill="#2E7D46" stroke="${WHITE}" stroke-width="8"/>
    <rect x="-22" y="0" width="44" height="40" fill="#F2E9C9"/>
  </g>`;
}
function muscleArms() {
  return `<g stroke="${WHITE}" stroke-width="12">
    <path d="M 120 300 q -50 -10 -40 -70 q 40 20 60 40" fill="${BLUE1}"/>
    <path d="M 392 300 q 50 -10 40 -70 q -40 20 -60 40" fill="${BLUE1}"/>
  </g>`;
}
function devilHorns() {
  return `<g fill="#FF4D6D">
    <path d="M 150 140 q -30 -40 -46 -70 q 44 8 60 54 Z"/>
    <path d="M 362 140 q 30 -40 46 -70 q -44 8 -60 54 Z"/>
  </g>`;
}

const PROPS = {
  sunglasses, crown, fireAura, tearsBig, blush, sweat, floatHearts,
  zzz, rudeHand, bottle, muscleArms, devilHorns,
};

// ---- body ------------------------------------------------------------------
function body() {
  const stroke = `stroke="${WHITE}" stroke-width="16"`;
  // feet
  const feet = `<ellipse cx="198" cy="446" rx="46" ry="26" fill="${BLUE3}" ${stroke}/>` +
               `<ellipse cx="314" cy="446" rx="46" ry="26" fill="${BLUE3}" ${stroke}/>`;
  // arms (behind body)
  const arms = `<ellipse cx="112" cy="330" rx="34" ry="52" fill="${BLUE2}" ${stroke}/>` +
               `<ellipse cx="400" cy="330" rx="34" ry="52" fill="${BLUE2}" ${stroke}/>`;
  // main squircle body
  const b = `<rect x="112" y="120" width="288" height="320" rx="130" fill="url(#g)" ${stroke}/>`;
  // soft top highlight
  const hi = `<ellipse cx="210" cy="180" rx="70" ry="34" fill="${WHITE}" opacity="0.18"/>`;
  return feet + arms + b + hi;
}

function sigmaBadge() {
  const bx = 256, by = 392, h = 26, sw = 14;
  const pts = `${bx+h},${by-h} ${bx-h},${by-h} ${bx+h*0.1},${by} ${bx-h},${by+h} ${bx+h},${by+h}`;
  return `<polyline points="${pts}" fill="none" stroke="${WHITE}" stroke-width="${sw}" stroke-linejoin="round" stroke-linecap="round" opacity="0.92"/>`;
}

// ---- assemble --------------------------------------------------------------
function buildSVG(spec) {
  const before = (spec.behind || []).map((p) => PROPS[p]()).join('');
  const props = (spec.props || []).map((p) => PROPS[p]()).join('');
  const eyes = EYES[spec.eyes] ? EYES[spec.eyes]() : EYES.normal();
  const mouth = MOUTHS[spec.mouth] ? MOUTHS[spec.mouth]() : MOUTHS.smile();
  return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${W} ${W}" width="${W}" height="${W}">
<defs>
  <linearGradient id="g" x1="0" y1="0" x2="1" y2="1">
    <stop offset="0" stop-color="${BLUE1}"/>
    <stop offset="1" stop-color="${BLUE2}"/>
  </linearGradient>
</defs>
${before}
${body()}
${sigmaBadge()}
${eyes}
${mouth}
${props}
</svg>`;
}

module.exports = { buildSVG, EYES, MOUTHS, PROPS };
