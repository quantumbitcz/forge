# Eval: Image without alt text

## Language: typescript

## Context
React component renders images without alt attributes, violating WCAG accessibility guidelines.

## Code Under Review

```typescript
// file: src/components/ProductCard.tsx
import React from 'react';

interface Props {
  name: string;
  imageUrl: string;
  price: number;
}

export function ProductCard({ name, imageUrl, price }: Props) {
  return (
    <div className="product-card">
      <img src={imageUrl} />
      <h3>{name}</h3>
      <span>${price.toFixed(2)}</span>
    </div>
  );
}
```

## Expected Behavior
Reviewer should flag the img element missing an alt attribute.
