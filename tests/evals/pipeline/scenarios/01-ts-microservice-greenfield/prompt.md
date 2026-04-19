# Scenario 01 — TypeScript microservice greenfield

Build a minimal Express-based TypeScript HTTP service with:

- `GET /health` returning `{ "status": "ok" }` with 200
- `GET /users/:id` returning a fixture user; 404 on unknown id
- Vitest unit tests for both routes
- TypeScript strict mode, ESLint, Prettier
- `npm start` boots on port `PORT` (default 3000)

Pinned versions: express 4.21.x, typescript 5.5.x, vitest 2.x, node 20 LTS.

Pipeline mode: `standard`.
