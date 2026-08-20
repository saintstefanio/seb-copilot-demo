import type {
  AccountListResponse,
  TransactionListResponse,
} from '@seb-demo/payments-api/schema'
import type { Serialized } from '@sebspark/openapi-core'

// The API and the UI are both typed off api/src/schemas/payments.json via
// openapi-typegen. Change the spec and this file stops compiling — that's the point.
export type Account = Serialized<AccountListResponse>['data'][number]
export type Transaction = Serialized<TransactionListResponse>['data'][number]

const get = async <T>(path: string): Promise<T> => {
  const res = await fetch(`/api${path}`)
  if (!res.ok) throw new Error(`${res.status} ${res.statusText} on ${path}`)
  return res.json() as Promise<T>
}

export const getAccounts = () =>
  get<Serialized<AccountListResponse>>('/accounts')

export const getTransactions = (accountId: string, page: number, limit: number) =>
  get<Serialized<TransactionListResponse>>(
    `/accounts/${accountId}/transactions?page=${page}&limit=${limit}`,
  )
