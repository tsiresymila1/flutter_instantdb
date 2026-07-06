import { i } from '@instantdb/react';

// `id` is implicit on every entity — do NOT declare it here (the CLI rejects it).
const schema = i.schema({
  entities: {
    // System entities.
    $files: i.entity({
      path: i.string().unique().indexed(),
      url: i.string().optional(),
    }),
    $users: i.entity({
      email: i.string().unique().indexed().optional(),
    }),

    // Todo items — TodosPage / Aggregations / Playground.
    todos: i.entity({
      text: i.string(),
      completed: i.boolean(),
      createdAt: i.number().optional(),
    }),

    // Collaborative painting tiles — TileGamePage.
    tiles: i.entity({
      row: i.number(),
      col: i.number(),
      userId: i.string(),
      userName: i.string(),
      color: i.number(),
      timestamp: i.number(),
    }),

    // Chat messages — TypingPage.
    messages: i.entity({
      userId: i.string(),
      userName: i.string(),
      text: i.string(),
      timestamp: i.number(),
    }),
  },
  links: {},
  rooms: {},
});

export type AppSchema = typeof schema;
export default schema;
