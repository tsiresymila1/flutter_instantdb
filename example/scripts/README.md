# InstantDB Schema Scripts

This directory contains InstantDB schema and permissions files for server-side configuration.

## Files

- `instant.schema.ts` - TypeScript schema definition for all entity types (todos, tiles, messages, etc.)
- `instant.perms.ts` - Permissions configuration for InstantDB server

## Usage

Run the InstantDB CLI from this directory (it reads `instant.schema.ts` and
`instant.perms.ts` from the current folder). Use your app id from the Flutter
app's `.env` (`INSTANTDB_API_ID`).

```bash
cd example/scripts

# One-time login
npx instant-cli@latest login

# Push BOTH schema and permissions (no subcommand = both).
# Perms MUST be pushed or storage uploads fail with `not-has-permission`.
npx instant-cli@latest push --app <YOUR_APP_ID>

# Pull the live schema/perms back down
npx instant-cli@latest pull --app <YOUR_APP_ID>
```

> The Dart helper (`dart run bin/schema.dart push`) only pushes the **schema**.
> To apply `instant.perms.ts` you must run `instant-cli push` (or `push perms`).