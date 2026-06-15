import { buildLlmsFull, siteOrigin } from '@/lib/llms';

export const dynamic = 'force-static';

export function GET() {
  return new Response(buildLlmsFull(siteOrigin()), {
    headers: { 'Content-Type': 'text/plain; charset=utf-8' },
  });
}
