import type { Account, Transaction } from './schemas/payments.js'

export const accounts: Account[] = [
  {
    id: 'acc-1',
    name: 'Everyday account',
    iban: 'SE35 5000 0000 0549 1000 0003',
    balance: { amount: 24310.5, currency: 'SEK' },
  },
  {
    id: 'acc-2',
    name: 'Savings',
    iban: 'SE35 5000 0000 0549 1000 0004',
    balance: { amount: 118000, currency: 'SEK' },
  },
]

// ponytail: in-memory fixtures, swap for a real store if the demo ever needs persistence
const raw: [string, string, string, string, number][] = [
  ['acc-1', '2026-08-18T09:12:00Z', 'Card purchase', 'ICA Kvantum', -742.5],
  ['acc-1', '2026-08-18T07:45:00Z', 'Card purchase', 'Espresso House', -49],
  ['acc-1', '2026-08-17T18:30:00Z', 'Card purchase', 'SL Access', -395],
  ['acc-1', '2026-08-17T12:02:00Z', 'Card purchase', 'Systembolaget', -289],
  ['acc-1', '2026-08-16T20:15:00Z', 'Card purchase', 'Spotify', -139],
  ['acc-1', '2026-08-16T11:00:00Z', 'Transfer', 'Vattenfall', -1204],
  ['acc-1', '2026-08-15T08:00:00Z', 'Salary', 'SEB AB', 38400],
  ['acc-1', '2026-08-14T16:41:00Z', 'Card purchase', 'Apotek Hjartat', -218.9],
  ['acc-1', '2026-08-14T13:20:00Z', 'Card purchase', 'H&M', -599],
  ['acc-1', '2026-08-13T19:05:00Z', 'Card purchase', 'Max Burgers', -132],
  ['acc-1', '2026-08-13T09:30:00Z', 'Card purchase', 'Circle K', -880.2],
  ['acc-1', '2026-08-12T17:55:00Z', 'Card purchase', 'Filmstaden', -240],
  ['acc-2', '2026-08-15T08:05:00Z', 'Transfer', 'Everyday account', 5000],
  ['acc-2', '2026-08-01T08:05:00Z', 'Interest', 'SEB AB', 96.4],
]

export const transactions: Transaction[] = raw.map(
  ([accountId, bookedAt, description, merchant, amount], i) => ({
    id: `txn-${String(i + 1).padStart(3, '0')}`,
    accountId,
    bookedAt: new Date(bookedAt),
    description,
    merchant,
    amount: { amount, currency: 'SEK' },
  }),
)

export const transactionsFor = (
  accountId: string,
  page = 1,
  limit = 20,
  q?: string,
) => {
  const search = q?.toLocaleLowerCase()
  const all = transactions
    .filter(
      (t) =>
        t.accountId === accountId &&
        (!search ||
          t.description.toLocaleLowerCase().includes(search) ||
          t.merchant.toLocaleLowerCase().includes(search)),
    )
    .sort((a, b) => b.bookedAt.getTime() - a.bookedAt.getTime())
  const start = (page - 1) * limit
  return { rows: all.slice(start, start + limit), total: all.length }
}
