# Flutter InstantDB — documentation

Built with [Fumadocs](https://fumadocs.dev) (Next.js App Router + fumadocs-mdx).
Dark mode is the default.

## Local development

```bash
cd website2
pnpm install      # or npm install — runs `fumadocs-mdx` postinstall to generate .source
pnpm dev          # http://localhost:3000  (docs at /docs)
pnpm build        # production build
```

## Structure

- `content/docs/**/*.mdx` — documentation pages.
- `content/docs/**/meta.json` — per-folder navigation (title + page order).
- `source.config.ts` — fumadocs-mdx config.
- `lib/source.ts` — content loader (`@/.source/server`).
- `app/layout.tsx` — `RootProvider` (dark default); `app/layout.config.tsx` — navbar/brand.
- `app/docs/` — docs layout + `[[...slug]]` page renderer.
- `app/global.css` — Tailwind v4 + fumadocs-ui preset + azure brand.

Add a page: create `content/docs/<section>/<page>.mdx` (with `title` +
`description` frontmatter) and list `<page>` in that folder's `meta.json`.

## Deploy

Standard Next.js build — deploy to Vercel (or any Node host). The repo subdir is
`website2`.
