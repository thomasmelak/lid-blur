// Renders design/AppIcon.html to Resources/AppIcon.png with Playwright:
//   node design/render-icon.js "$PWD/design/AppIcon.html" Resources/AppIcon.png
const { chromium } = require('playwright');
(async () => {
  const b = await chromium.launch();
  const p = await b.newPage({ viewport: { width: 1024, height: 1024 }, deviceScaleFactor: 1 });
  await p.goto('file://' + process.argv[2]);
  await p.screenshot({ path: process.argv[3], omitBackground: true });
  await b.close();
})();
