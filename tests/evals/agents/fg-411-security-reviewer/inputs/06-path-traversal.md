# Eval: Path traversal via unsanitized file path

## Language: typescript

## Context
File serving endpoint uses user-supplied path without sanitization.

## Code Under Review

```typescript
// file: src/handlers/files.ts
import { readFile } from 'fs/promises';
import { Request, Response } from 'express';

async function serveFile(req: Request, res: Response): Promise<void> {
  const filename = req.params.filename;
  const content = await readFile(`./uploads/${filename}`, 'utf-8');
  res.send(content);
}
```

## Expected Behavior
Reviewer should flag path traversal risk from unsanitized filename parameter (e.g., ../../etc/passwd).
