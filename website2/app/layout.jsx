import { Footer, Layout, Navbar } from 'nextra-theme-docs'
import { Head } from 'nextra/components'
import { getPageMap } from 'nextra/page-map'
import 'nextra-theme-docs/style.css'
import './globals.css'

export const metadata = {
  title: 'Flutter InstantDB  Documentation',
  description: 'Official documentation for the Flutter InstantDB ≈ SDK',
}

export default async function RootLayout({ children }) {
  const pageMap = await getPageMap()
  
  const navbar = (
    <Navbar
      logo={<b>Flutter InstantDB</b>}
      projectLink="https://github.com/tsiresymila1/flutter_instantdb"
    />
  )
  
  const footer = (
    <Footer>
      MIT {new Date().getFullYear()} ©{' '}
      <a href="https://github.com/tsiresymila1/flutter_instantdb" target="_blank" rel="noreferrer">
        InstantDB Flutter
      </a>
    </Footer>
  )

  return (
    <html lang="en" dir="ltr" suppressHydrationWarning>
      <Head />
      <body suppressHydrationWarning>
        <Layout
          navbar={navbar}
          footer={footer}
          pageMap={pageMap}
          docsRepositoryBase="https://github.com/tsiresymila1/flutter_instantdb/tree/main/website2"
          editLink="Edit this page on GitHub"
        >
          {children}
        </Layout>
      </body>
    </html>
  )
}
