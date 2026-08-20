import {
  GdsCard,
  GdsFilterChip,
  GdsFilterChips,
  GdsFlex,
  GdsTable,
  GdsText,
  GdsTheme,
} from '@sebgroup/green-core/react'
import type { GdsFilterChips as GdsFilterChipsElement } from '@sebgroup/green-core/components/filter-chips/filter-chips.component.js'
import type { Column, Request } from '@sebgroup/green-core/components/table/table.types.js'
import { useCallback, useEffect, useRef, useState } from 'react'
import {
  type Account,
  type Transaction,
  getAccounts,
  getTransactions,
} from './api'

const money = (m: Transaction['amount']) =>
  new Intl.NumberFormat('sv-SE', {
    style: 'currency',
    currency: m.currency,
  }).format(m.amount)

const columns: Column[] = [
  {
    key: 'bookedAt',
    label: 'Date',
    width: '10rem',
    value: (r: Transaction) => r.bookedAt.slice(0, 10),
  },
  { key: 'description', label: 'Description' },
  { key: 'merchant', label: 'Merchant' },
  {
    key: 'amount',
    label: 'Amount',
    justify: 'end',
    width: '12rem',
    value: (r: Transaction) => money(r.amount),
  },
]

export default function App() {
  const [accounts, setAccounts] = useState<Account[]>([])
  const [accountId, setAccountId] = useState<string>()
  const [error, setError] = useState<string>()
  const chips = useRef<GdsFilterChipsElement<string>>(null)

  // gds-filter-chips emits `change`, but green-core's React wrapper binds
  // onChange to `input` — so the prop never fires. Listen for the real event.
  useEffect(() => {
    const el = chips.current
    if (!el) return
    const onChange = () => setAccountId(el.value)
    el.addEventListener('change', onChange)
    return () => el.removeEventListener('change', onChange)
  }, [])

  useEffect(() => {
    getAccounts()
      .then(({ data }) => {
        setAccounts(data)
        setAccountId(data[0]?.id)
      })
      .catch((e) => setError(String(e)))
  }, [])

  // gds-table drives pagination; the API does the slicing.
  const provider = useCallback(
    async ({ page, rows }: Request) => {
      if (!accountId) return { rows: [], total: 0 }
      const { data, total } = await getTransactions(accountId, page, rows)
      return { rows: data, total }
    },
    [accountId],
  )

  const account = accounts.find((a) => a.id === accountId)

  return (
    <GdsTheme colorScheme="light">
      <GdsFlex
        flex-direction="column"
        gap="l"
        padding="l"
        max-width="72rem"
        margin="0 auto"
      >
        <GdsText tag="h1">Payments</GdsText>

        <GdsFilterChips ref={chips} label="Select account" value={accountId}>
          {accounts.map((a) => (
            <GdsFilterChip key={a.id} value={a.id}>
              {a.name}
            </GdsFilterChip>
          ))}
        </GdsFilterChips>

        {account && (
          <GdsCard variant="neutral-02" padding="m" border-radius="s">
            <GdsText tag="h2">{account.name}</GdsText>
            <GdsText>{account.iban}</GdsText>
            <GdsText tag="h3">{money(account.balance)}</GdsText>
          </GdsCard>
        )}

        {error && <GdsText>{error}</GdsText>}

        {accountId && (
          <GdsTable
            key={accountId}
            headline="Transactions"
            columns={columns}
            data={provider}
            density="comfortable"
            rows={10}
            options={[10, 20, 50]}
          />
        )}
      </GdsFlex>
    </GdsTheme>
  )
}
