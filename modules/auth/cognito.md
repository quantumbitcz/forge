# Amazon Cognito — Best Practices

## Overview

Amazon Cognito is AWS's managed identity service providing user pools (authentication) and
identity pools (federated access to AWS services). Use Cognito when building on AWS and
needing managed sign-up/sign-in, social/enterprise federation, and IAM-based authorization
to AWS resources. Cognito excels at serverless architectures (Lambda, API Gateway, AppSync).
Avoid it when you need complex RBAC logic beyond Cognito groups, deep UI customization of
the hosted login page, or multi-cloud portability. Consider Auth0 or Keycloak for richer
customization and non-AWS deployments.

## Architecture Patterns

### User Pool + App Client Setup
```hcl
# Terraform
resource "aws_cognito_user_pool" "main" {
  name = "my-app-users"

  password_policy {
    minimum_length    = 12
    require_uppercase = true
    require_numbers   = true
    require_symbols   = true
  }

  account_recovery_setting {
    recovery_mechanism {
      name     = "verified_email"
      priority = 1
    }
  }

  schema {
    name                = "org_id"
    attribute_data_type = "String"
    mutable             = true
  }
}

resource "aws_cognito_user_pool_client" "web" {
  name         = "web-client"
  user_pool_id = aws_cognito_user_pool.main.id

  explicit_auth_flows = [
    "ALLOW_USER_SRP_AUTH",
    "ALLOW_REFRESH_TOKEN_AUTH"
  ]

  generate_secret = false  # false for SPAs and mobile
}
```

### Backend Token Verification
```python
import jwt
from jwt import PyJWKClient

COGNITO_REGION = "us-east-1"
USER_POOL_ID = "us-east-1_XXXXX"
APP_CLIENT_ID = "abc123"

jwks_url = f"https://cognito-idp.{COGNITO_REGION}.amazonaws.com/{USER_POOL_ID}/.well-known/jwks.json"
jwks_client = PyJWKClient(jwks_url)

def verify_token(token: str) -> dict:
    signing_key = jwks_client.get_signing_key_from_jwt(token)
    return jwt.decode(
        token,
        signing_key.key,
        algorithms=["RS256"],
        audience=APP_CLIENT_ID,
        issuer=f"https://cognito-idp.{COGNITO_REGION}.amazonaws.com/{USER_POOL_ID}"
    )
```

### Lambda Triggers for Custom Logic
```python
# Pre-sign-up trigger — auto-confirm email-verified social users
def handler(event, context):
    if event["triggerSource"] == "PreSignUp_ExternalProvider":
        event["response"]["autoConfirmUser"] = True
        event["response"]["autoVerifyEmail"] = True
    return event
```

### API Gateway Integration (Zero-Code Auth)
```yaml
# SAM template
AuthFunction:
  Type: AWS::Serverless::Api
  Properties:
    Auth:
      DefaultAuthorizer: CognitoAuth
      Authorizers:
        CognitoAuth:
          UserPoolArn: !GetAtt UserPool.Arn
```

### Anti-pattern — using Cognito groups as fine-grained permissions: Cognito groups are coarse (admin, user, viewer). For feature-level permissions, use a separate authorization service or store permissions in a database and evaluate per request. Don't create hundreds of groups.

## Configuration

**Amplify SDK initialization:**
```javascript
import { Amplify } from "aws-amplify";
import { signIn, signUp, getCurrentUser } from "aws-amplify/auth";

Amplify.configure({
  Auth: {
    Cognito: {
      userPoolId: "us-east-1_XXXXX",
      userPoolClientId: "abc123",
      loginWith: { oauth: { domain: "auth.myapp.com", scopes: ["openid", "email", "profile"] } }
    }
  }
});
```

**Custom domain for hosted UI:**
```hcl
resource "aws_cognito_user_pool_domain" "main" {
  domain          = "auth.myapp.com"
  certificate_arn = aws_acm_certificate.auth.arn
  user_pool_id    = aws_cognito_user_pool.main.id
}
```

**Token expiration settings:**
- Access token: 5 minutes–1 day (default: 1 hour)
- ID token: 5 minutes–1 day (default: 1 hour)
- Refresh token: 1 hour–10 years (default: 30 days)

## Performance

**Cache JWKS keys:** The JWKS endpoint is rate-limited. Cache the signing keys for at least 1 hour, refreshing only when encountering an unknown `kid` in a token.

**Use `USER_SRP_AUTH` over `USER_PASSWORD_AUTH`:** SRP (Secure Remote Password) never sends the password over the wire, even with TLS. `USER_PASSWORD_AUTH` transmits the password and should only be used for server-side authentication or migration.

**Batch user operations via Admin API:**
```python
import boto3
client = boto3.client("cognito-idp")
# List users with pagination
response = client.list_users(UserPoolId=pool_id, Limit=60, PaginationToken=token)
```

**Pre-token generation trigger for custom claims:** Add custom claims to ID/access tokens via Lambda trigger instead of fetching from a database on every request.

## Security

**Enable MFA:**
```hcl
resource "aws_cognito_user_pool" "main" {
  mfa_configuration = "ON"  # or "OPTIONAL"
  software_token_mfa_configuration {
    enabled = true
  }
}
```

**Advanced Security Features (adaptive auth):**
```hcl
user_pool_add_ons {
  advanced_security_mode = "ENFORCED"  # risk-based adaptive auth
}
```

**Never use `ADMIN_NO_SRP_AUTH` from client-side code** — it requires AWS credentials and bypasses SRP security. Use only from trusted server environments.

**WAF integration for the hosted UI:**
```hcl
resource "aws_wafv2_web_acl_association" "cognito" {
  resource_arn = aws_cognito_user_pool.main.arn
  web_acl_arn  = aws_wafv2_web_acl.main.arn
}
```

**Secret rotation for app clients with secrets:** Use AWS Secrets Manager to rotate client secrets automatically.

## Testing

**Use `moto` for mocking Cognito in Python tests:**
```python
from moto import mock_cognitoidp

@mock_cognitoidp
def test_create_user():
    client = boto3.client("cognito-idp", region_name="us-east-1")
    pool = client.create_user_pool(PoolName="test")
    pool_id = pool["UserPool"]["Id"]
    client.admin_create_user(UserPoolId=pool_id, Username="testuser")
```

**For integration tests, use a dedicated test user pool** — never test against production. Create test users via Admin API, run tests, then clean up.

**Test Lambda triggers locally** with SAM CLI:
```bash
sam local invoke PreSignUpFunction -e events/pre-signup.json
```

## Dos
- Use SRP authentication flow (`USER_SRP_AUTH`) — it never transmits passwords over the wire.
- Enable MFA for all production user pools — at minimum, TOTP-based software MFA.
- Use Lambda triggers (pre-sign-up, pre-token-generation) for custom validation and claims enrichment.
- Cache JWKS signing keys and refresh only when encountering an unknown `kid`.
- Use separate user pools for each environment (dev, staging, production).
- Leverage API Gateway's built-in Cognito authorizer for zero-code authentication on REST APIs.
- Set refresh token rotation to detect token reuse attacks — Cognito automatically invalidates the family.

## Don'ts
- Don't use `USER_PASSWORD_AUTH` for client-side authentication — use SRP to prevent password transmission.
- Don't create hundreds of Cognito groups for fine-grained permissions — use a separate authorization layer.
- Don't expose AWS credentials in client-side code for admin operations — use the client SDK flows.
- Don't skip email/phone verification before allowing access to sensitive features.
- Don't hardcode user pool IDs or client IDs — use environment variables or SSM Parameter Store.
- Don't use the same user pool for production and testing — test data and configuration changes affect prod.
- Don't ignore Cognito's rate limits (default: 5 RPS for some APIs) — implement exponential backoff and request quota increases before launch.
