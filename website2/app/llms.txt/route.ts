import { buildLlmsIndex } from '@/lib/llms';
import { siteOrigin } from '@/lib/llms';

export const dynamic = 'force-static';

export function GET() {
  return new Response(buildLlmsIndex(siteOrigin()), {
    headers: { 'Content-Type': 'text/plain; charset=utf-8' },
  });
}
