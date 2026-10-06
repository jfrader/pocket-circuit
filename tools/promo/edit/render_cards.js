// Renders every overlay into $PROMO_OUT/cards/<name>/NNNN.png at 30 fps, timed
// to the score's beat from $PROMO_OUT/analysis.json:
//   title cards from cards.html (transparent), the circuit wall and the car wall
//   from wall.html (opaque).   node render_cards.js [name ...]
const {chromium} = require('playwright');
const fs = require('fs');

const OUT = process.env.PROMO_OUT || '/tmp/opencode/pc-promo';
const FPS = 30;
const VIEWPORT = {width: 1920, height: 1080};
const END_CARD_SECONDS = 5.6;
const CAR_COUNT = 104;
const {beat} = JSON.parse(fs.readFileSync(`${OUT}/analysis.json`, 'utf8'));
const TWO_BARS = 8 * beat;
const CARD_SECONDS = {logo: TWO_BARS, tiny: TWO_BARS, drift: TWO_BARS, music: TWO_BARS, strip: TWO_BARS, rivals: TWO_BARS, next: TWO_BARS, end: END_CARD_SECONDS};
const WALLS = {
  wall: {setup: (p) => p.evaluate(r => build(r), JSON.parse(fs.readFileSync(`${OUT}/routes.json`, 'utf8')))},
  carwall: {
    setup: (p) => p.evaluate(s => { layout(13, 8); setCopy('BODY · PAINT · PARTS', 'EVERY CAR<br><span class="hl">PROCEDURAL</span>'); buildCars(s); },
      [...Array(CAR_COUNT).keys()].map(i => 'data:image/png;base64,' + fs.readFileSync(`${OUT}/cars/car_${String(i).padStart(3, '0')}.png`).toString('base64'))),
  },
};

async function frames(page, dir, seconds, transparent) {
  fs.rmSync(dir, {recursive: true, force: true});
  fs.mkdirSync(dir, {recursive: true});
  for (let f = 0; f < Math.round(seconds * FPS); f++) {
    await page.evaluate(t => at(t), f / FPS);
    await page.screenshot({path: `${dir}/${String(f).padStart(4, '0')}.png`, omitBackground: transparent});
  }
}

(async () => {
  const wanted = process.argv.slice(2);
  const pick = (name) => wanted.length === 0 || wanted.includes(name);
  const browser = await chromium.launch();
  const page = await browser.newPage({viewport: VIEWPORT});
  await page.goto(`file://${__dirname}/cards.html`);
  await page.evaluate(() => document.fonts.ready);
  for (const [name, seconds] of Object.entries(CARD_SECONDS).filter(([n]) => pick(n))) {
    await page.evaluate(([n, s]) => show(n, s), [name, seconds]);
    await frames(page, `${OUT}/cards/${name}`, seconds, true);
    console.log('card', name);
  }
  for (const [name, wall] of Object.entries(WALLS).filter(([n]) => pick(n))) {
    await page.goto(`file://${__dirname}/wall.html`);
    await page.evaluate(() => document.fonts.ready);
    await page.evaluate(b => setBeat(b), beat);
    await wall.setup(page);
    await page.waitForTimeout(300);
    await frames(page, `${OUT}/cards/${name}`, TWO_BARS, false);
    console.log('wall', name);
  }
  await browser.close();
})();
