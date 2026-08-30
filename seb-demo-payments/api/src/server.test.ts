import { expect, test } from 'vitest'
import { app } from './server.js'
import { transactionsFor } from './transactions.js'

const listen = async () => {
  const server = app.listen(0)
  await new Promise((r) => server.once('listening', r))
  const { port } = server.address() as { port: number }
  return { url: `http://localhost:${port}`, close: () => server.close() }
}

test('lists accounts', async () => {
  const { url, close } = await listen()
  const res = await fetch(`${url}/accounts`)
  expect(res.status).toBe(200)
  expect((await res.json()).data).toHaveLength(2)
  close()
})

test('lists transactions newest first', async () => {
  const { url, close } = await listen()
  const res = await fetch(`${url}/accounts/acc-1/transactions`)
  const body = await res.json()
  expect(body.total).toBe(12)
  expect(body.data[0].merchant).toBe('ICA Kvantum')
  expect(typeof body.data[0].bookedAt).toBe('string')
  close()
})

test('404s on unknown account', async () => {
  const { url, close } = await listen()
  expect((await fetch(`${url}/accounts/nope/transactions`)).status).toBe(404)
  close()
})

test('paginates', () => {
  expect(transactionsFor('acc-1', 2, 5).rows).toHaveLength(5)
  expect(transactionsFor('acc-1', 3, 5).rows).toHaveLength(2)
  expect(transactionsFor('acc-1', 1, 5).total).toBe(12)
})

test('searches transaction descriptions and merchants case-insensitively', async () => {
  const { url, close } = await listen()
  const merchant = await fetch(
    `${url}/accounts/acc-1/transactions?q=eSpReSsO`,
  )
  const description = await fetch(
    `${url}/accounts/acc-1/transactions?q=transfer`,
  )
  const noMatch = await fetch(
    `${url}/accounts/acc-1/transactions?q=does-not-exist`,
  )

  expect((await merchant.json()).data.map((t: { merchant: string }) => t.merchant)).toEqual([
    'Espresso House',
  ])
  expect((await description.json()).data.map((t: { description: string }) => t.description)).toEqual([
    'Transfer',
  ])
  expect(await noMatch.json()).toMatchObject({ data: [], total: 0 })
  close()
})

test('paginates the filtered transaction set', () => {
  expect(transactionsFor('acc-1', 1, 2, 'card purchase').total).toBe(11)
  expect(transactionsFor('acc-1', 2, 10, 'card purchase').rows).toHaveLength(1)
})
