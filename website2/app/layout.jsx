import { Footer, Layout, Navbar } from 'nextra-theme-docs'
import { Head } from 'nextra/components'
import { getPageMap } from 'nextra/page-map'
import { Geist, Bricolage_Grotesque, JetBrains_Mono } from 'next/font/google'
import 'nextra-theme-docs/style.css'
import './globals.css'

const sans = Geist({
  subsets: ['latin'],
  variable: '--font-sans',
  display: 'swap',
})

const display = Bricolage_Grotesque({
  subsets: ['latin'],
  variable: '--font-display',
  display: 'swap',
})

const mono = JetBrains_Mono({
  subsets: ['latin'],
  variable: '--font-mono',
  display: 'swap',
})

export const metadata = {
  title: {
    default: 'Flutter InstantDB — Real-time, offline-first database for Flutter',
    template: '%s · Flutter InstantDB',
  },
  description:
    'Real-time, offline-first database for Flutter with reactive bindings, type-safe queries, code generation and live collaboration.',
  applicationName: 'Flutter InstantDB',
  metadataBase: new URL('https://flutter-instantdb.vercel.app'),
  openGraph: {
    title: 'Flutter InstantDB',
    description:
      'Real-time, offline-first database for Flutter with reactive bindings.',
    url: 'https://flutter-instantdb.vercel.app',
    siteName: 'Flutter InstantDB',
    type: 'website',
  },
}

const Logo = () => (
  <span className="fid-logo">
    <img
      src="/logo.svg"
      alt=""
      width={26}
      height={26}
      className="fid-logo__mark"
    />
    <span className="fid-logo__text">
      Flutter<span className="fid-logo__accent">InstantDB</span>
    </span>
  </span>
)

export default async function RootLayout({ children }) {
  const pageMap = await getPageMap()

  const navbar = (
    <Navbar
      logo={<Logo />}
      logoLink="/"
      projectLink="https://github.com/tsiresymila1/flutter_instantdb"
    />
  )

  const footer = (
    <Footer>
      <div className="fid-footer">
        <span>
          MIT © {new Date().getFullYear()} ·{' '}
          <a
            href="https://github.com/tsiresymila1/flutter_instantdb"
            target="_blank"
            rel="noreferrer"
          >
            Flutter InstantDB
          </a>
        </span>
        <span className="fid-footer__meta">
          Built with Flutter · A community port of{' '}
          <a href="https://instantdb.com" target="_blank" rel="noreferrer">
            InstantDB
          </a>
        </span>
      </div>
    </Footer>
  )

  return (
    <html
      lang="en"
      dir="ltr"
      suppressHydrationWarning
      className={`${sans.variable} ${display.variable} ${mono.variable}`}
    >
      <Head
        color={{ hue: 211, saturation: 92 }}
        backgroundColor={{ dark: '#0c0e13', light: '#ffffff' }}
      />
      <body suppressHydrationWarning>
        <Layout
          navbar={navbar}
          footer={footer}
          pageMap={pageMap}
          docsRepositoryBase="https://github.com/tsiresymila1/flutter_instantdb/tree/main/website2"
          editLink="Edit this page on GitHub"
          nextThemes={{ defaultTheme: 'dark' }}
          sidebar={{ defaultMenuCollapseLevel: 1, toggleButton: true }}
          toc={{ float: true, backToTop: 'Back to top' }}
          feedback={{ content: 'Question? Give us feedback' }}
        >
          {children}
        </Layout>
      </body>
    </html>
  )
}
