const fs = require('fs');
const path = require('path');
const { Resvg } = require('@resvg/resvg-js');
const { buildSVG } = require('./sigma');

function png(svg, size = 512) {
  const r = new Resvg(svg, { fitTo: { mode: 'width', value: size } });
  return r.render().asPng();
}

function renderPack(name, specs, outDir) {
  fs.mkdirSync(outDir, { recursive: true });
  specs.forEach((s, i) => {
    const svg = buildSVG(s);
    const buf = png(svg, 512);
    const file = path.join(outDir, `${String(i + 1).padStart(2, '0')}_${s.name}.png`);
    fs.writeFileSync(file, buf);
  });
  console.log(`${name}: ${specs.length} stickers -> ${outDir}`);
}

// contact sheet: grid of stickers on a light+dark split bg to check outline
function contactSheet(specs, outFile, cols = 4, cell = 300) {
  const rows = Math.ceil(specs.length / cols);
  const w = cols * cell, h = rows * cell;
  const imgs = specs.map((s, i) => {
    const b64 = png(buildSVG(s), 260).toString('base64');
    const x = (i % cols) * cell + (cell - 260) / 2;
    const y = Math.floor(i / cols) * cell + (cell - 260) / 2;
    const label = `<text x="${(i%cols)*cell+cell/2}" y="${Math.floor(i/cols)*cell+cell-14}" font-family="Arial" font-size="18" fill="#8891a8" text-anchor="middle">${s.name}</text>`;
    return `<image x="${x}" y="${y}" width="260" height="260" href="data:image/png;base64,${b64}"/>${label}`;
  }).join('');
  const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="${w}" height="${h}" viewBox="0 0 ${w} ${h}">
    <rect width="${w/2}" height="${h}" fill="#0F1015"/>
    <rect x="${w/2}" width="${w/2}" height="${h}" fill="#F5F5F2"/>
    ${imgs}
  </svg>`;
  const r = new Resvg(svg);
  fs.writeFileSync(outFile, r.render().asPng());
  console.log('contact sheet ->', outFile);
}

module.exports = { renderPack, contactSheet, png };

// ---- run samples when invoked directly ----
if (require.main === module) {
  const samples = [
    { name: 'sigma-cool', eyes: 'side', mouth: 'smirk', props: ['sunglasses'] },
    { name: 'love', eyes: 'heart', mouth: 'smallSmile', props: ['floatHearts', 'blush'] },
    { name: 'lol', eyes: 'happy', mouth: 'bigOpen', props: ['tearsBig'] },
    { name: 'king', eyes: 'side', mouth: 'smirk', behind: ['crown'] },
  ];
  contactSheet(samples, path.join(__dirname, 'preview_samples.png'), 4, 300);
}
