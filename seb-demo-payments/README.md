# seb-demo-payments

Runnable glue for the SEB Copilot demo: a small payments API and a UI that
consumes it, both typed off one OpenAPI spec.

```
api/src/schemas/payments.json     the contract
        │
        └── openapi-typegen ──► payments.ts
                                   │
              ┌────────────────────┴────────────────────┐
        api/  PaymentsServerPaths              web/  response types
        @sebspark/openapi-express              @sebgroup/green-core
```

Change the spec and the type system breaks on both sides. That's the demo.

## Run it

```sh
npm install     # installs and generates types
npm run dev     # api :3001, web :5173
```

Open http://localhost:5173.

## Layout

| Path | What |
|---|---|
| `api/src/schemas/payments.json` | OpenAPI spec — source of truth |
| `api/src/schemas/payments.ts` | Generated, gitignored, never hand-edited |
| `api/src/server.ts` | `TypedRouter` handlers |
| `api/src/transactions.ts` | In-memory fixtures |
| `api/src/server.test.ts` | Vitest |
| `web/src/api.ts` | `fetch` typed off the generated types |
| `web/src/App.tsx` | `gds-*` components: theme, filter-chips, card, table |

## Endpoints

- `GET /accounts`
- `GET /accounts/:accountId/transactions?page=&limit=`

`gds-table` drives pagination; the API does the slicing.

## Notes

- `@sebspark/openapi-client` pulls Node-only OTel deps, so the browser uses
  plain `fetch` against the same generated types.
- Green's SEB brand fonts live in `@sebgroup/chlorophyll`, which isn't
  installed — `gds-theme` alone gives every token and colour. Add chlorophyll
  if the demo needs the exact typeface.
- `gds-filter-chips` emits `change`, but green-core's React wrapper binds
  `onChange` to `input`, so the prop never fires. `App.tsx` attaches the
  listener via a ref. Worth an upstream issue against `green`.
