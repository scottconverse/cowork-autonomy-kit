# Website maintenance

Static HTML/CSS with no JavaScript runtime or third-party dependencies. `index.html` owns content; `styles.css` owns the cream/terracotta workshop design tokens, system typography, responsive layouts, and focus states. Keep claims grounded in the implementation and release evidence. Do not describe public source as open-source until an actual license exists.

From the repository root, with Node 24 and Python 3 available:

```sh
npm test
npm run build
npm run preview
```

Open http://localhost:4321. `npm run dev` serves the source instead. The build copies only HTML and CSS into `dist/`. Assets are relative so the output works under `/cowork-autonomy-kit/`.

GitHub Pages uses the Actions source. The `Publish website` workflow tests and builds pull requests, then deploys main to https://scottconverse.github.io/cowork-autonomy-kit/. Roll back a broken website by reverting its source commit through a PR; main redeploys. Do not rewrite published product release tags to update the website.

Before publishing content changes, check desktop, tablet and mobile layouts, keyboard focus, every link, and the accuracy of permission and testing disclosures. The workflow's static tests are not a substitute for browser testing.

For v2.0.0, download calls to action target the exact release, while manual and architecture links target current documentation on main. Keep repository About description and homepage in sync with the Code-tab/CLI scope. The historical repository slug remains unchanged. Published ZIP filename: `cowork-autonomy-kit-v2.0.0.zip`; checksums: `SHA256SUMS.txt`.
