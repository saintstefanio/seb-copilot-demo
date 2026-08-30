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

test('searches transaction description and merchant case-insensitively', () => {
  expect(transactionsFor('acc-1', 1, 20, 'ESPRESSO').rows).toHaveLength(1)
  expect(transactionsFor('acc-1', 1, 20, 'transfer').rows).toHaveLength(1)
  expect(transactionsFor('acc-1', 1, 20, 'no match').total).toBe(0)
})

test('search filters before pagination', async () => {
  const { url, close } = await listen()
  const res = await fetch(
    `${url}/accounts/acc-1/transactions?q=card%20purchase&page=2&limit=5`,
  )
  const body = await res.json()
  expect(body.total).toBe(10)
  expect(body.data).toHaveLength(5)
  close()
})
