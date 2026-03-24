# NestJS + GraphQL — API Protocol Binding

## Integration Setup
- `@nestjs/graphql` + `@nestjs/apollo` + `@apollo/server` + `graphql`
- Code-first (recommended): define types with TypeScript classes + decorators
- Schema-first: load SDL files via `autoSchemaFile` set to a `.graphql` glob
- DataLoader: `dataloader` package; create per-request in context factory

## Framework-Specific Patterns

### Code-First Setup
```typescript
// app.module.ts
GraphQLModule.forRootAsync<ApolloDriverConfig>({
  driver: ApolloDriver,
  inject: [ConfigService],
  useFactory: (config: ConfigService) => ({
    autoSchemaFile: join(process.cwd(), 'src/schema.gql'),
    sortSchema: true,
    playground: config.get('NODE_ENV') !== 'production',
    introspection: config.get('NODE_ENV') !== 'production',
    context: ({ req }) => ({ req }),
  }),
}),
```

### Object Types
```typescript
// users/models/user.model.ts
@ObjectType()
export class UserModel {
  @Field(() => ID)
  id: string;

  @Field()
  name: string;

  @Field()
  email: string;

  @Field(() => [PostModel], { nullable: true })
  posts?: PostModel[];
}
```

### Resolver
```typescript
// users/users.resolver.ts
@Resolver(() => UserModel)
export class UsersResolver {
  constructor(
    private readonly usersService: UsersService,
    @Inject(POST_LOADER) private readonly postLoader: DataLoader<string, PostModel[]>,
  ) {}

  @Query(() => UserModel, { nullable: true })
  async user(@Args('id', { type: () => ID }) id: string): Promise<UserModel | null> {
    return this.usersService.findOne(id);
  }

  @Mutation(() => UserModel)
  async createUser(@Args('input') input: CreateUserInput): Promise<UserModel> {
    return this.usersService.create(input);
  }

  @ResolveField(() => [PostModel])
  async posts(@Parent() user: UserModel): Promise<PostModel[]> {
    return this.postLoader.load(user.id);   // batched via DataLoader
  }
}
```

### Input Types
```typescript
@InputType()
export class CreateUserInput {
  @Field()
  @IsString()
  @MinLength(2)
  name: string;

  @Field()
  @IsEmail()
  email: string;
}
```

### DataLoader Factory (per-request)
```typescript
// posts/loaders/post-by-user.loader.ts
export const POST_LOADER = 'POST_LOADER';

export const postByUserLoaderFactory = (postsService: PostsService) =>
  new DataLoader<string, PostModel[]>(async (userIds) => {
    const posts = await postsService.findByUserIds([...userIds]);
    return userIds.map((id) => posts.filter((p) => p.userId === id));
  });
```

Provide per-request in `GraphQLModule` context or use `REQUEST`-scoped providers.

## Scaffolder Patterns
```
src/
  graphql/
    users/
      users.module.ts
      users.resolver.ts
      models/
        user.model.ts          # @ObjectType() class
      dto/
        create-user.input.ts   # @InputType() class
    posts/
      loaders/
        post-by-user.loader.ts
  schema.gql                   # auto-generated; commit to source control
```

## Dos
- Use `@ResolveField` with DataLoader for every one-to-many or many-to-one relationship
- Validate `@InputType()` fields with `class-validator` decorators — NestJS applies `ValidationPipe` automatically
- Commit the auto-generated `schema.gql` so schema changes appear in PRs
- Use `nullable: true` on optional fields; never return `null` for non-nullable fields

## Don'ts
- Don't put business logic in resolvers — delegate to service layer
- Don't share DataLoader instances across requests — they must be per-request to avoid cache pollution
- Don't disable `introspection` in development; disable it in production
- Don't use `any` as a `@Field()` type — define explicit `@ObjectType()` classes
