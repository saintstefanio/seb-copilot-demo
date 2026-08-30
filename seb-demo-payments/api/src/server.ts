import { NotFoundError } from '@sebspark/openapi-core'
import { TypedRouter } from '@sebspark/openapi-express'
import express, { type Express } from 'express'
import type { PaymentsServerPaths } from './schemas/payments.js'
import { accounts, transactionsFor } from './transactions.js'

const api: PaymentsServerPaths = {
  '/accounts': {
    get: {
      handler: async () => [200, { data: { data: accounts } }],
    },
  },
  '/accounts/:accountId/transactions': {
    get: {
      handler: async ({ params, query }) => {
        if (!accounts.some((a) => a.id === params.accountId)) {
          throw new NotFoundError(`No account ${params.accountId}`)
        }
        // query params arrive as strings regardless of the spec's declared type
        const num = (v: unknown) => (v === undefined ? undefined : Number(v))
        const { rows, total } = transactionsFor(
          params.accountId,
          num(query?.page),
          num(query?.limit),
          query?.q,
        )
        return [
          200,
          {
            data: {
              total,
              data: rows.map((t) => ({
                ...t,
                bookedAt: t.bookedAt.toISOString(),
              })),
            },
          },
        ]
      },
    },
  },
}

export const app: Express = express()
// ponytail: wide-open CORS — this is a localhost demo, lock it down before it leaves a laptop
app.use((_req, res, next) => {
  res.setHeader('Access-Control-Allow-Origin', '*')
  next()
})
app.use(TypedRouter(api))
