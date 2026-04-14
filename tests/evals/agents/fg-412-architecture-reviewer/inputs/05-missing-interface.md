# Eval: Concrete dependency without interface abstraction

## Language: typescript

## Context
Service depends directly on a concrete implementation rather than an interface.

## Code Under Review

```typescript
// file: src/services/notification-service.ts
import { SmtpEmailClient } from '../infrastructure/smtp-client';
import { TwilioSmsClient } from '../infrastructure/twilio-client';

export class NotificationService {
  constructor(
    private emailClient: SmtpEmailClient,
    private smsClient: TwilioSmsClient,
  ) {}

  async notify(user: User, message: string): Promise<void> {
    await this.emailClient.send(user.email, message);
    await this.smsClient.send(user.phone, message);
  }
}
```

## Expected Behavior
Reviewer should flag tight coupling to concrete implementations instead of interfaces.
