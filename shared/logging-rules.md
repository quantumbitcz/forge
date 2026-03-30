# Shared Logging Rules

Cross-cutting logging conventions that apply regardless of language or framework. Language-specific modules reference this file and add their language-specific library choices and API patterns.

## Universal Rules

- **No PII in logs**: Never log email, name, phone, credentials (tokens, passwords, API keys), or financial data (card numbers). Log internal IDs (`userId`, `orderId`) instead.
- **No print-style logging**: Never use the language's print/console function for operational logging — it lacks levels, structure, and routing.
- **Structured logging**: Use key-value or structured format for searchability. Avoid string interpolation/concatenation in log messages.
- **Lazy evaluation**: Log messages should only be constructed if the level is enabled (use lambda/supplier patterns where available).
- **Request-scoped context**: Use the language's MDC/context propagation mechanism for correlation IDs and trace IDs — set once in middleware, not per call site.
- **Log levels**: Use appropriate levels — DEBUG for development diagnostics, INFO for business events, WARN for recoverable issues, ERROR for failures requiring attention.
