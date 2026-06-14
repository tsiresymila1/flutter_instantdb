import type { BaseLayoutProps } from 'fumadocs-ui/layouts/shared';

export const baseOptions: BaseLayoutProps = {
  nav: {
    title: (
      <>
        <img src="/logo.svg" alt="" width={24} height={24} />
        <span style={{ fontWeight: 700 }}>Flutter InstantDB</span>
      </>
    ),
    transparentMode: 'top',
  },
  githubUrl: 'https://github.com/tsiresymila1/flutter_instantdb',
  links: [
    {
      text: 'Documentation',
      url: '/docs',
      active: 'nested-url',
    },
    {
      text: 'Quick Start',
      url: '/docs/getting-started/quick-start',
    },
  ],
};
