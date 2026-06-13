
## Unreleased

### Query operators (InstaQL parity)
- Added `$like` (case-sensitive) and `$ilike` (case-insensitive) string match operators with SQL `%`/`_` wildcards.
- Added `$not` operator (alias of `$ne`).
- Added `and` / `or` logical combinators in `where` clauses.
- Added dot-notation nested-field matching (e.g. `where: { 'todos.title': 'Run' }`).
- Existing `$nin` / `$exists` / `$eq` extensions remain supported.

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
