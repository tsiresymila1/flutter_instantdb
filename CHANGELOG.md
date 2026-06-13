
## Unreleased

### Query operators (InstaQL parity)
- Added `$like` (case-sensitive) and `$ilike` (case-insensitive) string match operators with SQL `%`/`_` wildcards.
- Added `$not` operator (alias of `$ne`).
- Added `and` / `or` logical combinators in `where` clauses.
- Added dot-notation nested-field matching (e.g. `where: { 'todos.title': 'Run' }`).
- Existing `$nin` / `$exists` / `$eq` extensions remain supported.

### Query pagination & fields
- Added cursor pagination: `first`/`after`/`last`/`before` (+ `afterInclusive`/`beforeInclusive`) under a namespace's `$` options.
- Added `pageInfo` on `QueryResult` (`startCursor`/`endCursor`/`hasNextPage`/`hasPreviousPage` per namespace).
- Added `fields` projection: `$: { fields: ['title', 'status'] }` (id always included).
- Added `db.infiniteQuery(...)` accumulator + `InstantInfiniteBuilder` widget.

### Transactions (InstaML parity)
- Added chainable `lookup` target: `db.tx.profiles.lookup('email', 'a@b.com').update({...})` — upsert by unique attribute (also works with `merge`, `delete`, `link`, `unlink`).
- Added `{upsert: false}` strict mode: `db.tx.goals[id].update({...}, opts: TxOpts(upsert: false))` does not create the entity if it does not exist.
- Added `ruleParams`: `db.tx.docs[id].update({...}).ruleParams({...})`, forwarded to the server for permission rules.

### Connection status & local id
- Added `ConnectionStatus` enum (`connecting`/`opened`/`authenticated`/`closed`/`errored`) exposed via `db.connectionStatus` and the new `ConnectionStateBuilder` widget.
- Added persistent `db.getLocalId(name)` — a stable id per name that survives restarts (matches `useLocalId`).
- Deprecated `db.isOnline` (use `connectionStatus`; online == `authenticated`) and `db.getAnonymousUserId()` (use `getLocalId`). Both still work.

## 1.1.2+1
### 🎉 Docs
Update docs
## 1.1.2
### 🎉 Docs
Full update docs
## 1.1.1
### 🎉 Docs
Partial update docs
## 1.1.0
### 🎉 Auth manager
Use runtime api url

## 1.0.0
### 🎉 Initial Release
