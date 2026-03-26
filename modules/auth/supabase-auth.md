# Supabase Auth — Best Practices

## Overview

Supabase Auth is an open-source authentication service built on GoTrue, providing email/password,
magic links, social login (Google, GitHub, Apple, etc.), phone auth, and SSO (SAML). Use it for
projects already on Supabase or when you want an open-source Auth0 alternative with tight
PostgreSQL row-level security integration. Avoid it when you need complex enterprise IdP features
beyond what GoTrue supports, or when your stack is not on Supabase/PostgreSQL.

## Architecture Patterns

### Client-Side Authentication
```typescript
import { createClient } from "@supabase/supabase-js";

const supabase = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_ANON_KEY);

// Sign up
const { data, error } = await supabase.auth.signUp({ email, password });

// Sign in
const { data, error } = await supabase.auth.signInWithPassword({ email, password });

// Social login
const { data, error } = await supabase.auth.signInWithOAuth({ provider: "google" });

// Get current user
const { data: { user } } = await supabase.auth.getUser();
```

### Row-Level Security (PostgreSQL integration)
```sql
-- Enable RLS on tables
ALTER TABLE posts ENABLE ROW LEVEL SECURITY;

-- Users can only read their own posts
CREATE POLICY "Users read own posts" ON posts
  FOR SELECT USING (auth.uid() = user_id);

-- Users can only insert their own posts
CREATE POLICY "Users insert own posts" ON posts
  FOR INSERT WITH CHECK (auth.uid() = user_id);
```

### Server-Side Token Verification
```typescript
import { createClient } from "@supabase/supabase-js";

const supabase = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_SERVICE_ROLE_KEY);

const { data: { user }, error } = await supabase.auth.getUser(accessToken);
if (error) throw new UnauthorizedError();
```

### Anti-pattern — using the `anon` key for admin operations: The `anon` key respects RLS policies. For server-side admin operations, use the `service_role` key which bypasses RLS. Never expose the `service_role` key to clients.

## Configuration

```sql
-- Custom claims via database function
CREATE OR REPLACE FUNCTION custom_access_token_hook(event jsonb)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE claims jsonb;
BEGIN
  claims := event->'claims';
  claims := jsonb_set(claims, '{user_role}', to_jsonb(
    (SELECT role FROM user_roles WHERE user_id = (event->>'user_id')::uuid)
  ));
  event := jsonb_set(event, '{claims}', claims);
  RETURN event;
END;
$$;
```

## Dos
- Use Row-Level Security policies for data access control — they're enforced at the database level.
- Use `auth.uid()` in RLS policies to reference the authenticated user.
- Use `onAuthStateChange` for reactive auth state management in client apps.
- Use the `service_role` key only in trusted server environments — never in client-side code.
- Use custom claims hooks for role-based access without extra database queries.
- Enable email confirmation in production to verify user email addresses.
- Use Supabase's built-in rate limiting and CAPTCHA support for auth endpoints.

## Don'ts
- Don't expose the `service_role` key in client-side code — it bypasses all RLS policies.
- Don't skip RLS on tables accessed by authenticated users — without RLS, all data is accessible.
- Don't use `anon` key for admin operations — it respects RLS and can't access restricted data.
- Don't store sensitive data without RLS policies — Supabase tables are accessible via the API by default.
- Don't skip email confirmation in production — unverified emails enable account takeover.
- Don't ignore Supabase's auth rate limits — brute-force protection is built in but has limits.
- Don't use direct database connections to bypass auth — route through Supabase client for RLS enforcement.
