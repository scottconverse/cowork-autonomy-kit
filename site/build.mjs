import { mkdir, copyFile } from 'node:fs/promises';
await mkdir('dist', { recursive: true });
for (const file of ['index.html', 'styles.css']) await copyFile(`site/${file}`, `dist/${file}`);
console.log('PASS: static site built in dist/ (no dependencies)');
