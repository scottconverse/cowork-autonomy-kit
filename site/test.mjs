import { readFile } from 'node:fs/promises';
import assert from 'node:assert/strict';
const html = await readFile('site/index.html', 'utf8');
const css = await readFile('site/styles.css', 'utf8');
const ids = [...html.matchAll(/id="([^"]+)"/g)].map(x => x[1]);
assert.equal(new Set(ids).size, ids.length, 'IDs must be unique');
for (const [, href] of html.matchAll(/href="([^"]+)"/g)) {
  if (href.startsWith('#') && href !== '#') assert(ids.includes(href.slice(1)), `Missing anchor ${href}`);
  else if (!href.startsWith('#') && href !== 'styles.css') assert(href.startsWith('https://github.com/scottconverse/cowork-autonomy-kit'), `Unexpected link ${href}`);
}
assert.equal([...html.matchAll(/<h1>/g)].length, 1);
assert(html.includes('bypassPermissions') && html.includes('automatically'), 'Permission changes must be disclosed');
assert(html.includes('no reuse license') && html.includes('not performed'), 'Scope and license disclosure required');
assert(css.includes(':focus-visible') && css.includes('prefers-reduced-motion'));
assert(!html.includes('src="/') && !html.includes('href="/'), 'Assets must work under project subpath');
console.log('PASS: anchors, unique headings/IDs, portable paths, disclosures, focus and reduced-motion styles');
