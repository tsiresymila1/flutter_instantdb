import { NextResponse } from 'next/server';
import fs from 'fs';
import path from 'path';

// Recursively find all .mdx files in the app directory
function findMdxFiles(dir: string, files: string[] = []): string[] {
  const items = fs.readdirSync(dir);
  
  for (const item of items) {
    const fullPath = path.join(dir, item);
    const stat = fs.statSync(fullPath);
    
    if (stat.isDirectory()) {
      // Skip api directory and node_modules
      if (item !== 'api' && item !== 'node_modules' && !item.startsWith('.')) {
        findMdxFiles(fullPath, files);
      }
    } else if (item.endsWith('.mdx') || item.endsWith('.md')) {
      files.push(fullPath);
    }
  }
  
  return files;
}

// Extract content from MDX file (remove frontmatter)
function extractContent(filePath: string): string {
  const content = fs.readFileSync(filePath, 'utf-8');
  
  // Remove frontmatter (content between --- markers)
  const frontmatterRegex = /^---[\s\S]*?---\n*/;
  const bodyContent = content.replace(frontmatterRegex, '');
  
  // Remove import statements
  const importRegex = /^import\s+.*?;?\s*$/gm;
  const cleanContent = bodyContent.replace(importRegex, '');
  
  return cleanContent.trim();
}

export async function GET(request: Request) {
  const url = new URL(request.url);
  const query = url.searchParams.get('q');
  
  const appDir = path.join(process.cwd(), 'app');
  const mdxFiles = findMdxFiles(appDir);
  
  let contents = mdxFiles.map(file => {
    const relativePath = path.relative(appDir, file);
    const content = extractContent(file);
    return `# ${relativePath}\n\n${content}`;
  });
  
  if (query) {
    contents = contents.filter(content => 
      content.toLowerCase().includes(query.toLowerCase())
    );
  }
  
  const result = contents.join('\n\n---\n\n');
  
  return new NextResponse(result, {
    status: 200,
    headers: {
      'Content-Type': 'text/plain; charset=utf-8',
    },
  });
}
