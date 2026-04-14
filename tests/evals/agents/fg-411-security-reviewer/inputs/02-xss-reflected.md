# Eval: Reflected XSS via unsanitized user input in HTML

## Language: typescript

## Context
Server-side handler renders user input directly into HTML response without escaping.

## Code Under Review

```typescript
// file: src/handlers/search.ts
import { Request, Response } from 'express';

function handleSearch(req: Request, res: Response): void {
  const query = req.query.q as string;
  res.send(`
    <html>
      <body>
        <h1>Search results for: ${query}</h1>
        <div id="results"></div>
      </body>
    </html>
  `);
}
```

## Expected Behavior
Reviewer should flag reflected XSS from rendering unsanitized query parameter into HTML.
