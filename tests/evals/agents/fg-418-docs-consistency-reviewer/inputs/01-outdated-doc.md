# Eval: README documents API endpoint that no longer exists

## Language: markdown

## Context
README documents a GET /api/users endpoint but the actual code only has POST /api/users.

## Code Under Review

```markdown
// file: README.md
## API Reference

### Get Users
`GET /api/users` - Returns a list of all users.

### Create User
`POST /api/users` - Creates a new user.

### Delete User
`DELETE /api/users/:id` - Deletes a user by ID.
```

```typescript
// file: src/routes.ts
router.post('/api/users', createUser);
router.patch('/api/users/:id', updateUser);
```

## Expected Behavior
Reviewer should flag that README documents GET /api/users and DELETE /api/users/:id which do not exist in the code, and the code has PATCH which is not documented.
