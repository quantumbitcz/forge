# Angular + Apollo Angular GraphQL — API Protocol Binding

## Integration Setup

```bash
npm install @apollo/client apollo-angular graphql
```

```typescript
// src/app/graphql.provider.ts
import { ApplicationConfig } from '@angular/core';
import { provideApollo } from 'apollo-angular';
import { ApolloClientOptions, InMemoryCache } from '@apollo/client/core';

const apolloOptions: ApolloClientOptions<unknown> = {
  uri: '/graphql',
  cache: new InMemoryCache(),
};

export const apolloProvider = provideApollo(() => apolloOptions);
```

```typescript
// app.config.ts
export const appConfig: ApplicationConfig = {
  providers: [
    apolloProvider,
    // ...other providers
  ],
};
```

## Code Generation

Use `@graphql-codegen/cli` with `typescript`, `typescript-operations`, and `typescript-apollo-angular` plugins:

```typescript
// codegen.ts
import type { CodegenConfig } from '@graphql-codegen/cli';

const config: CodegenConfig = {
  schema: 'http://localhost:4000/graphql',
  documents: 'src/**/*.graphql',
  generates: {
    'src/__generated__/graphql.ts': {
      plugins: ['typescript', 'typescript-operations', 'typescript-apollo-angular'],
    },
  },
};
export default config;
```

## Framework-Specific Patterns

- Define operations in `.graphql` files co-located with feature modules; generate typed services at build time
- Use generated `GQL_<OperationName>GQL` service classes injected via `inject()`
- Cache policies: `cache-first` for stable data, `network-only` for real-time, `no-cache` for one-off fetches
- Signal integration: wrap query observables with `toSignal()` for OnPush-compatible templates

```typescript
// users.component.ts
import { Component, inject } from '@angular/core';
import { toSignal } from '@angular/core/rxjs-interop';
import { map } from 'rxjs/operators';
import { GetUsersGQL } from '../__generated__/graphql';

@Component({
  standalone: true,
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    @if (loading()) { <p>Loading...</p> }
    @for (user of users(); track user.id) { <p>{{ user.name }}</p> }
  `,
})
export class UsersComponent {
  private getUsersGql = inject(GetUsersGQL);

  private result = toSignal(this.getUsersGql.watch().valueChanges, { initialValue: undefined });

  users = computed(() => this.result()?.data?.users ?? []);
  loading = computed(() => this.result()?.loading ?? true);
}
```

## Mutations with Signal State

```typescript
// create-user.component.ts
import { CreateUserGQL, CreateUserMutationVariables } from '../__generated__/graphql';

@Component({ ... })
export class CreateUserComponent {
  private createUserGql = inject(CreateUserGQL);
  private apollo = inject(Apollo);

  submitting = signal(false);
  error = signal<string | null>(null);

  createUser(variables: CreateUserMutationVariables): void {
    this.submitting.set(true);
    this.error.set(null);

    this.createUserGql.mutate(variables, {
      update: (cache, { data }) => {
        cache.modify({
          fields: {
            users: (existingUsers = []) => [...existingUsers, data?.createUser],
          },
        });
      },
    }).subscribe({
      next: () => this.submitting.set(false),
      error: (err) => {
        this.error.set(err.message);
        this.submitting.set(false);
      },
    });
  }
}
```

## Scaffolder Patterns

```
src/
  graphql/
    operations/
      users.graphql               # query/mutation/subscription documents
    fragments/
      userFields.graphql          # reusable fragments
  __generated__/
    graphql.ts                    # codegen output (gitignored or committed)
  app/
    graphql.provider.ts           # Apollo client configuration
    features/{feature}/
      {feature}.component.ts      # consumes generated GQL services
codegen.ts                        # graphql-codegen configuration
```

## Dos

- Co-locate `.graphql` operation files with the feature components that own them
- Run `graphql-codegen --watch` in development to keep types in sync
- Use `toSignal()` to bridge Apollo Observable queries into signal-based templates
- Handle loading, error, and empty states explicitly for every query

## Don'ts

- Don't write GraphQL queries as inline template literals — use `.graphql` files + codegen
- Don't use `Apollo.watchQuery` directly in components — use the generated GQL service classes
- Don't store remote GraphQL data in component signals — Apollo cache is the source of truth
- Don't skip error handling — unhandled GraphQL errors cause silent component failures with OnPush
