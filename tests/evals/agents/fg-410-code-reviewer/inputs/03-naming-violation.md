# Eval: Inconsistent naming conventions

## Language: typescript

## Context
Variable and function names violate standard TypeScript naming conventions.

## Code Under Review

```typescript
// file: src/utils/helpers.ts
const MAX_retries = 3;
const user_name = "admin";

function Get_User_By_Id(User_Id: string) {
  const DB_Result = fetchFromDb(User_Id);
  return DB_Result;
}

function calculate_total(item_list: number[]): number {
  let Total = 0;
  for (const Item of item_list) {
    Total += Item;
  }
  return Total;
}
```

## Expected Behavior
Reviewer should flag inconsistent naming (snake_case, PascalCase variables, PascalCase function names in TypeScript).
