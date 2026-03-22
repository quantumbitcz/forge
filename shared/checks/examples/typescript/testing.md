# Testing Patterns (TypeScript)

## vitest-setup

**Instead of:**
```typescript
test("adds item", () => {
  const list: string[] = [];
  list.push("a");
  expect(list.length === 1).toBe(true);
});
```

**Do this:**
```typescript
test("adds item to the list", () => {
  const list: string[] = [];
  list.push("a");
  expect(list).toHaveLength(1);
  expect(list).toContain("a");
});
```

**Why:** Semantic matchers like `toHaveLength` produce clear failure messages (`expected length 1, received 0`) instead of `expected true, received false`.

## testing-library-queries

**Instead of:**
```typescript
test("renders name", () => {
  const { container } = render(<Profile name="Ada" />);
  expect(container.querySelector(".name")!.textContent).toBe("Ada");
});
```

**Do this:**
```typescript
test("renders name", () => {
  render(<Profile name="Ada" />);
  expect(screen.getByText("Ada")).toBeInTheDocument();
});
```

**Why:** Querying by CSS class couples tests to implementation; `getByText` tests what the user actually sees.

## user-event

**Instead of:**
```typescript
test("submits form", async () => {
  render(<LoginForm onSubmit={onSubmit} />);
  fireEvent.change(screen.getByLabelText("Email"), {
    target: { value: "a@b.com" },
  });
  fireEvent.click(screen.getByRole("button", { name: "Log in" }));
  expect(onSubmit).toHaveBeenCalled();
});
```

**Do this:**
```typescript
test("submits form", async () => {
  const user = userEvent.setup();
  render(<LoginForm onSubmit={onSubmit} />);
  await user.type(screen.getByLabelText("Email"), "a@b.com");
  await user.click(screen.getByRole("button", { name: "Log in" }));
  expect(onSubmit).toHaveBeenCalledWith({ email: "a@b.com" });
});
```

**Why:** `userEvent` simulates real browser interactions (focus, keydown, input, keyup) while `fireEvent` dispatches a single synthetic event.

## mock-api-calls

**Instead of:**
```typescript
vi.mock("../api", () => ({
  fetchUser: vi.fn().mockResolvedValue({ name: "Ada" }),
}));

test("shows user", async () => {
  render(<UserCard id="1" />);
  expect(await screen.findByText("Ada")).toBeInTheDocument();
});
```

**Do this:**
```typescript
const server = setupServer(
  http.get("/api/users/:id", () =>
    HttpResponse.json({ name: "Ada" }),
  ),
);
beforeAll(() => server.listen());
afterEach(() => server.resetHandlers());
afterAll(() => server.close());

test("shows user", async () => {
  render(<UserCard id="1" />);
  expect(await screen.findByText("Ada")).toBeInTheDocument();
});
```

**Why:** MSW intercepts at the network level, testing the real fetch path instead of replacing the module and hiding integration bugs.
