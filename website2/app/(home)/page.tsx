import Link from 'next/link';
import {
  Zap,
  WifiOff,
  Sparkles,
  ShieldCheck,
  Wand2,
  Users,
  ArrowRight,
  Github,
} from 'lucide-react';

const GITHUB = 'https://github.com/tsiresymila1/flutter_instantdb';

export default function HomePage() {
  return (
    <main className="flex flex-col">
      <Hero />
      <Platforms />
      <Features />
      <TypedHighlight />
      <BottomCTA />
    </main>
  );
}

function Hero() {
  return (
    <section className="relative overflow-hidden border-b border-fd-border">
      <div className="hero-bg" />
      <div className="mx-auto grid max-w-6xl items-center gap-12 px-6 py-20 lg:grid-cols-2 lg:py-28">
        <div className="fid-rise">
          <span className="inline-flex items-center gap-2 rounded-full border border-fd-primary/30 bg-fd-primary/10 px-3 py-1 text-xs font-medium text-fd-primary">
            <span className="relative flex size-1.5">
              <span className="absolute inline-flex size-full animate-ping rounded-full bg-fd-primary opacity-75" />
              <span className="relative inline-flex size-1.5 rounded-full bg-fd-primary" />
            </span>
            Local-first · Real-time · Type-safe
          </span>

          <h1 className="mt-5 text-4xl font-extrabold leading-[1.05] tracking-tight sm:text-5xl lg:text-6xl">
            The <span className="grad-text">real-time database</span> for Flutter
          </h1>

          <p className="mt-5 max-w-xl text-lg text-fd-muted-foreground">
            A Flutter/Dart port of InstantDB. Offline-first SQLite, instant sync
            across clients, reactive widgets, and a fully type-safe query &amp;
            transaction layer generated from your models.
          </p>

          <div className="mt-8 flex flex-wrap gap-3">
            <Link
              href="/docs/getting-started/installation"
              className="inline-flex items-center gap-2 rounded-xl bg-fd-primary px-5 py-3 text-sm font-semibold text-fd-primary-foreground shadow-lg shadow-fd-primary/30 transition-transform hover:-translate-y-0.5"
            >
              Get started
              <ArrowRight className="size-4" />
            </Link>
            <a
              href={GITHUB}
              target="_blank"
              rel="noreferrer"
              className="inline-flex items-center gap-2 rounded-xl border border-fd-border bg-fd-card px-5 py-3 text-sm font-semibold transition-colors hover:border-fd-primary/50 hover:bg-fd-primary/5"
            >
              <Github className="size-4" />
              GitHub
            </a>
          </div>

          <p className="mt-6 font-mono text-xs text-fd-muted-foreground">
            <span className="text-fd-primary">$</span> flutter pub add flutter_instantdb
          </p>
        </div>

        <CodeWindow />
      </div>
    </section>
  );
}

function CodeWindow() {
  return (
    <div className="code-window fid-rise overflow-hidden rounded-2xl border border-fd-border bg-fd-card/80 backdrop-blur">
      <div className="flex items-center gap-2 border-b border-fd-border px-4 py-3">
        <span className="size-3 rounded-full bg-[#ff5f57]" />
        <span className="size-3 rounded-full bg-[#febc2e]" />
        <span className="size-3 rounded-full bg-[#28c840]" />
        <span className="ml-2 font-mono text-xs text-fd-muted-foreground">
          todos_screen.dart
        </span>
      </div>
      <pre className="overflow-x-auto p-5 text-[13px] leading-relaxed">
        <code className="font-mono">
          <span className="tok-com">// Reactive, typed query — rebuilds on change</span>
          {'\n'}
          <span className="tok-key">final</span> todos = <span className="tok-key">await</span>{' '}
          <span className="tok-typ">TodoTable</span>()
          {'\n'}    .query()
          {'\n'}    .<span className="tok-fn">where</span>((t) =&gt; t.done.<span className="tok-fn">eq</span>(<span className="tok-key">false</span>))
          {'\n'}    .<span className="tok-fn">order</span>((t) =&gt; t.createdAt.<span className="tok-fn">desc</span>())
          {'\n'}    .<span className="tok-fn">getAll</span>(db);
          {'\n\n'}
          <span className="tok-com">// Typed write — wrong types won&apos;t compile</span>
          {'\n'}
          <span className="tok-key">await</span> db.<span className="tok-fn">transact</span>(
          {'\n'}  <span className="tok-typ">TodoTable</span>().<span className="tok-fn">tx</span>(db).<span className="tok-fn">createModel</span>(
          {'\n'}    <span className="tok-typ">Todo</span>(id: db.<span className="tok-fn">id</span>(), title: <span className="tok-str">&apos;Ship it&apos;</span>, done: <span className="tok-key">false</span>),
          {'\n'}  ),
          {'\n'});
        </code>
      </pre>
    </div>
  );
}

const PLATFORMS = ['iOS', 'Android', 'Web', 'macOS', 'Windows', 'Linux'];

function Platforms() {
  return (
    <section className="border-b border-fd-border">
      <div className="mx-auto max-w-6xl px-6 py-10">
        <p className="text-center text-xs font-medium uppercase tracking-widest text-fd-muted-foreground">
          One codebase · every platform
        </p>
        <div className="mt-5 flex flex-wrap items-center justify-center gap-x-10 gap-y-3 text-sm font-semibold text-fd-muted-foreground">
          {PLATFORMS.map((p) => (
            <span key={p} className="transition-colors hover:text-fd-foreground">
              {p}
            </span>
          ))}
        </div>
      </div>
    </section>
  );
}

const FEATURES = [
  {
    icon: Zap,
    title: 'Real-time sync',
    body: 'Changes propagate instantly to every connected client with reliable conflict resolution.',
  },
  {
    icon: WifiOff,
    title: 'Offline-first',
    body: 'Local SQLite storage. Your app works offline and syncs the moment connectivity returns.',
  },
  {
    icon: Sparkles,
    title: 'Reactive UI',
    body: 'Widgets rebuild automatically when data changes — powered by Signals, no manual state.',
  },
  {
    icon: ShieldCheck,
    title: 'Type-safe',
    body: 'A typed query + transaction DSL catches wrong fields and value types at compile time.',
  },
  {
    icon: Wand2,
    title: 'Code generation',
    body: 'Annotate a model with @InstantModel and generate typed tables, relations and writes.',
  },
  {
    icon: Users,
    title: 'Presence',
    body: 'Cursors, typing indicators, reactions and avatars for live multiplayer collaboration.',
  },
];

function Features() {
  return (
    <section className="mx-auto max-w-6xl px-6 py-20">
      <h2 className="text-center text-3xl font-bold tracking-tight">
        Everything you need to build collaborative apps
      </h2>
      <p className="mx-auto mt-3 max-w-2xl text-center text-fd-muted-foreground">
        The local-first developer experience of InstantDB, native to Flutter.
      </p>
      <div className="mt-12 grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
        {FEATURES.map(({ icon: Icon, title, body }) => (
          <div
            key={title}
            className="group rounded-2xl border border-fd-border bg-fd-card/50 p-6 transition-all hover:-translate-y-1 hover:border-fd-primary/40"
          >
            <div className="mb-4 inline-flex rounded-xl border border-fd-border bg-fd-primary/10 p-2.5 text-fd-primary">
              <Icon className="size-5" />
            </div>
            <h3 className="text-base font-semibold">{title}</h3>
            <p className="mt-2 text-sm text-fd-muted-foreground">{body}</p>
          </div>
        ))}
      </div>
    </section>
  );
}

function TypedHighlight() {
  return (
    <section className="border-y border-fd-border bg-fd-card/30">
      <div className="mx-auto grid max-w-6xl items-center gap-12 px-6 py-20 lg:grid-cols-2">
        <div>
          <span className="text-sm font-semibold text-fd-primary">
            Typed layer
          </span>
          <h2 className="mt-2 text-3xl font-bold tracking-tight">
            Your models, end to end type-safe
          </h2>
          <p className="mt-4 text-fd-muted-foreground">
            Declare a model, run the generator, and get typed tables, relation
            accessors, reactive queries and transactions. Relations, cursor
            pagination and whole-model writes — all checked by the compiler.
          </p>
          <ul className="mt-6 space-y-3 text-sm">
            {[
              'Typed query DSL with where / order / pagination',
              'Code generation from @InstantModel classes',
              '@InstantLink relations with typed .include(...)',
              'Typed transactions: create / update / merge / link',
            ].map((t) => (
              <li key={t} className="flex items-start gap-2">
                <ArrowRight className="mt-0.5 size-4 shrink-0 text-fd-primary" />
                <span>{t}</span>
              </li>
            ))}
          </ul>
          <Link
            href="/docs/typed/overview"
            className="mt-8 inline-flex items-center gap-2 text-sm font-semibold text-fd-primary hover:underline"
          >
            Explore the typed layer
            <ArrowRight className="size-4" />
          </Link>
        </div>

        <div className="code-window overflow-hidden rounded-2xl border border-fd-border bg-fd-card/80">
          <div className="flex items-center gap-2 border-b border-fd-border px-4 py-3">
            <span className="size-3 rounded-full bg-[#ff5f57]" />
            <span className="size-3 rounded-full bg-[#febc2e]" />
            <span className="size-3 rounded-full bg-[#28c840]" />
            <span className="ml-2 font-mono text-xs text-fd-muted-foreground">
              models.dart
            </span>
          </div>
          <pre className="overflow-x-auto p-5 text-[13px] leading-relaxed">
            <code className="font-mono">
              <span className="tok-key">@InstantModel</span>(<span className="tok-str">&apos;todos&apos;</span>)
              {'\n'}
              <span className="tok-key">class</span> <span className="tok-typ">Todo</span> {'{'}
              {'\n'}  <span className="tok-key">final</span> <span className="tok-typ">String</span> id;
              {'\n'}  <span className="tok-key">final</span> <span className="tok-typ">String</span> title;
              {'\n'}  <span className="tok-key">final</span> <span className="tok-typ">bool</span> done;
              {'\n'}
              {'\n'}  <span className="tok-key">@InstantLink</span>()
              {'\n'}  <span className="tok-key">final</span> <span className="tok-typ">List</span>&lt;<span className="tok-typ">Tag</span>&gt; tags;
              {'\n'}{'}'}
              {'\n\n'}
              <span className="tok-com">// generated → TodoTable, getAll, tx, include…</span>
            </code>
          </pre>
        </div>
      </div>
    </section>
  );
}

function BottomCTA() {
  return (
    <section className="mx-auto max-w-4xl px-6 py-24 text-center">
      <h2 className="text-3xl font-bold tracking-tight sm:text-4xl">
        Ship a synced app this afternoon
      </h2>
      <p className="mx-auto mt-4 max-w-xl text-fd-muted-foreground">
        Go from an empty project to a real-time, offline-first, reactive todo
        list in minutes.
      </p>
      <div className="mt-8 flex flex-wrap justify-center gap-3">
        <Link
          href="/docs/getting-started/quick-start"
          className="inline-flex items-center gap-2 rounded-xl bg-fd-primary px-6 py-3 text-sm font-semibold text-fd-primary-foreground shadow-lg shadow-fd-primary/30 transition-transform hover:-translate-y-0.5"
        >
          Read the Quick Start
          <ArrowRight className="size-4" />
        </Link>
        <Link
          href="/docs"
          className="inline-flex items-center gap-2 rounded-xl border border-fd-border bg-fd-card px-6 py-3 text-sm font-semibold transition-colors hover:border-fd-primary/50"
        >
          Browse the docs
        </Link>
      </div>
    </section>
  );
}
