# Eval: Fully accessible form component

## Language: typescript

## Context
Form with proper labels, aria attributes, and keyboard navigation support.

## Code Under Review

```typescript
// file: src/components/ContactForm.tsx
import React from 'react';

export function ContactForm() {
  return (
    <form aria-label="Contact form">
      <label htmlFor="name">Full Name</label>
      <input id="name" type="text" required aria-required="true" />

      <label htmlFor="email">Email Address</label>
      <input id="email" type="email" required aria-required="true" />

      <label htmlFor="message">Message</label>
      <textarea id="message" rows={4} required aria-required="true" />

      <button type="submit">Send Message</button>
    </form>
  );
}
```

## Expected Behavior
No accessibility findings expected. Proper labels, aria attributes, and semantic HTML.
