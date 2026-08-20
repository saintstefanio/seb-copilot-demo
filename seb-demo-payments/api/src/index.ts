import { app } from './server.js'

const port = Number(process.env.PORT) || 3001
app.listen(port, () => console.log(`payments-api on http://localhost:${port}`))
