import { readFile } from 'node:fs/promises';
import assert from 'node:assert/strict';
const html = await readFile('site/index.html', 'utf8');
const css = await readFile('site/styles.css', 'utf8');
const ids = [...html.matchAll(/id="([^"]+)"/g)].map(x => x[1]);
assert.equal(new Set(ids).size, ids.length, 'IDs must be unique');
for (const [, href] of html.matchAll(/href="([^"]+)"/g)) {
  if (href.startsWith('#') && href !== '#') assert(ids.includes(href.slice(1)), `Missing anchor ${href}`);
  else if (!href.startsWith('#') && href !== 'styles.css') assert((href.startsWith('https://github.com/scottconverse/cowork-autonomy-kit') || href.startsWith('https://code.claude.com/docs/en/')), `Unexpected link ${href}`);
}
assert.equal([...html.matchAll(/<h1>/g)].length, 1);
assert(html.includes('bypassPermissions') && html.includes('-SkipBypass') && html.includes('confirmation'), 'Permission changes must be disclosed');
assert(html.includes('no reuse license') && html.includes('not performed'), 'Scope and license disclosure required');
assert(css.includes(':focus-visible') && css.includes('prefers-reduced-motion'));
assert(!html.includes('src="/') && !html.includes('href="/'), 'Assets must work under project subpath');
console.log('PASS: anchors, unique headings/IDs, portable paths, disclosures, focus and reduced-motion styles');

const changelog = await readFile('CHANGELOG.md', 'utf8');
const version = changelog.match(/^## v(\d+\.\d+\.\d+)/m)?.[1];
assert(version, 'Newest changelog heading must have a version');
for (const path of ['README.md', 'docs/SETUP.md', 'docs/DEVELOPER-MANUAL.md', 'site/index.html']) {
  const content = await readFile(path, 'utf8');
  const versions = [...content.matchAll(/\b(?:v|Version )?(\d+\.\d+\.\d+)\b/g)].map(m => m[1]);
  assert(versions.length && versions.every(v => v === version), `Version mismatch in ${path}`);
}
for (const [,size] of css.matchAll(/(?:font-size\s*:|font\s*:)[^;{}]*?(\d+(?:\.\d+)?)px/g)) {
  assert(Number(size) >= 12, `Text size below 12px: ${size}`);
}
assert(css.includes('small{font-size:12px}'), 'small text must have explicit minimum');
assert(html.includes('Code tab') && html.includes('CLI') && html.includes('Cowork tab is out of scope'), 'Target must be explicit');
console.log('PASS: v' + version + ' consistency and minimum 12px text declarations');
