import { readdirSync, readFileSync, statSync } from 'fs';
import { join, relative } from 'path';

const DOCS_DIR = join(process.cwd(), 'content', 'docs');

export interface DocEntry {
  /** Site-relative URL, e.g. `/docs/getting-started/quick-start`. */
  url: string;
  title: string;
  description: string;
  /** Raw MDX body with frontmatter stripped. */
  content: string;
  /** Sort/group key: top-level folder under content/docs ('' for root). */
  group: string;
}

function walk(dir: string): string[] {
  const out: string[] = [];
  for (const entry of readdirSync(dir)) {
    const full = join(dir, entry);
    if (statSync(full).isDirectory()) {
      out.push(...walk(full));
    } else if (entry.endsWith('.mdx') || entry.endsWith('.md')) {
      out.push(full);
    }
  }
  return out;
}

function parseFrontmatter(raw: string): {
  data: Record<string, string>;
  body: string;
} {
  const match = /^---\n([\s\S]*?)\n---\n?/.exec(raw);
  if (!match) return { data: {}, body: raw };
  const data: Record<string, string> = {};
  for (const line of match[1].split('\n')) {
    const idx = line.indexOf(':');
    if (idx === -1) continue;
    const key = line.slice(0, idx).trim();
    let value = line.slice(idx + 1).trim();
    if (
      (value.startsWith('"') && value.endsWith('"')) ||
      (value.startsWith("'") && value.endsWith("'"))
    ) {
      value = value.slice(1, -1);
    }
    data[key] = value;
  }
  return { data, body: raw.slice(match[0].length) };
}

function fileToUrl(file: string): string {
  let rel = relative(DOCS_DIR, file).replace(/\\/g, '/');
  rel = rel.replace(/\.(mdx|md)$/, '');
  if (rel === 'index') return '/docs';
  if (rel.endsWith('/index')) rel = rel.slice(0, -'/index'.length);
  return `/docs/${rel}`;
}

/** Read every doc, sorted with the landing page first, then alphabetically. */
export function getDocs(): DocEntry[] {
  const docs = walk(DOCS_DIR).map((file): DocEntry => {
    const raw = readFileSync(file, 'utf8');
    const { data, body } = parseFrontmatter(raw);
    const rel = relative(DOCS_DIR, file).replace(/\\/g, '/');
    const group = rel.includes('/') ? rel.split('/')[0] : '';
    return {
      url: fileToUrl(file),
      title: data.title ?? rel,
      description: data.description ?? '',
      content: body.trim(),
      group,
    };
  });

  return docs.sort((a, b) => {
    if (a.url === '/docs') return -1;
    if (b.url === '/docs') return 1;
    return a.url.localeCompare(b.url);
  });
}

/**
 * Absolute site origin for links. Static prerender has no request host, so we
 * resolve from env: explicit override → Vercel production domain → local dev.
 */
export function siteOrigin(): string {
  if (process.env.NEXT_PUBLIC_SITE_URL) return process.env.NEXT_PUBLIC_SITE_URL;
  if (process.env.VERCEL_PROJECT_PRODUCTION_URL) {
    return `https://${process.env.VERCEL_PROJECT_PRODUCTION_URL}`;
  }
  return 'https://flutter-instantdb.vercel.app';
}

const SITE_TITLE = 'Flutter InstantDB';
const SITE_SUMMARY =
  'Flutter SDK for InstantDB — a real-time, offline-first, local-first ' +
  'database with reactive bindings. Type-safe InstaQL queries, optimistic ' +
  'InstaML transactions, WebSocket sync, auth, presence/rooms, file storage, ' +
  'and reactive widgets for iOS, Android, Web, macOS, Windows, and Linux.';

/** llms.txt index: title, summary, and a linked list of every doc page. */
export function buildLlmsIndex(origin: string): string {
  const docs = getDocs();
  const lines: string[] = [`# ${SITE_TITLE}`, '', `> ${SITE_SUMMARY}`, ''];

  const groups = new Map<string, DocEntry[]>();
  for (const doc of docs) {
    const key = doc.group || 'Overview';
    if (!groups.has(key)) groups.set(key, []);
    groups.get(key)!.push(doc);
  }

  for (const [group, entries] of groups) {
    lines.push(`## ${titleCase(group)}`, '');
    for (const doc of entries) {
      const desc = doc.description ? `: ${doc.description}` : '';
      lines.push(`- [${doc.title}](${origin}${doc.url})${desc}`);
    }
    lines.push('');
  }

  lines.push('## Full text', '', `- [Complete docs](${origin}/llms-full.txt)`);
  return lines.join('\n') + '\n';
}

/** llms-full.txt: the entire documentation concatenated as one markdown file. */
export function buildLlmsFull(origin: string): string {
  const docs = getDocs();
  const parts: string[] = [
    `# ${SITE_TITLE} — Full Documentation`,
    '',
    `> ${SITE_SUMMARY}`,
    '',
  ];
  for (const doc of docs) {
    parts.push(
      '---',
      '',
      `# ${doc.title}`,
      '',
      doc.description ? `> ${doc.description}\n` : '',
      `Source: ${origin}${doc.url}`,
      '',
      doc.content,
      '',
    );
  }
  return parts.join('\n') + '\n';
}

function titleCase(s: string): string {
  if (!s) return 'Overview';
  return s
    .split('-')
    .map((w) => w.charAt(0).toUpperCase() + w.slice(1))
    .join(' ');
}
