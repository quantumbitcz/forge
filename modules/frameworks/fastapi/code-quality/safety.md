# FastAPI + safety

> Extends `modules/code-quality/safety.md` with FastAPI-specific integration.
> Generic Safety conventions (policy file, CI integration, pip-audit) are NOT repeated here.

## Integration Setup

FastAPI projects typically use `pyproject.toml` optional dependencies — scan all groups:

```bash
# Install all groups then scan the environment
pip install -e ".[dev,test]"
safety scan

# Or scan requirements files if present
safety scan -r requirements.txt
safety scan -r requirements-dev.txt
```

```yaml
# .github/workflows/security.yml
- name: Install dependencies
  run: pip install -e ".[dev,test]"

- name: Safety scan
  env:
    SAFETY_API_KEY: ${{ secrets.SAFETY_API_KEY }}
  run: safety scan --exit-code
```

## Framework-Specific Patterns

### FastAPI and Starlette CVE Awareness

FastAPI is built on Starlette — CVEs in Starlette affect FastAPI directly:

| Package | Vulnerability Class | Notes |
|---|---|---|
| `starlette` | HTTP header injection, request smuggling, path traversal in `StaticFiles` | FastAPI depends on Starlette; patch both together |
| `fastapi` | Response injection via unvalidated `response_model` (rare) | Keep on latest stable |
| `uvicorn` | HTTP/1.1 request parsing edge cases | Production ASGI server — monitor security advisories |
| `python-multipart` | File upload parsing vulnerabilities | Required for `UploadFile`; has had DoS CVEs |
| `python-jose` / `PyJWT` | JWT algorithm confusion attacks | Common in FastAPI auth patterns; pin and audit |
| `httpx` | SSRF via redirect following (if used as internal client) | Configure `follow_redirects=False` for untrusted URLs |
| `pydantic` | ReDoS via regex validators (v1 only) | Upgrade to Pydantic v2 |

### python-multipart Awareness

FastAPI requires `python-multipart` for form data and file uploads (`UploadFile`). This package has had DoS vulnerabilities via crafted multipart boundaries:

```yaml
# .safety-policy.yml
ignore-vulnerabilities:
  # Only suppress after verifying: affected version, scope, and patched alternative
  # - id: "XXXXX"
  #   reason: "DoS only exploitable with >100MB uploads; uploads limited to 10MB at nginx"
  #   expires: "2025-06-30"
```

Set upload size limits at the ASGI/nginx layer rather than relying on application-level validation alone.

### JWT Library Guidance

`python-jose` has had critical algorithm confusion CVEs. Prefer `PyJWT` with explicit algorithm enforcement:

```python
# Specify allowed algorithms explicitly — never use "none" or wildcard
import jwt
payload = jwt.decode(token, secret, algorithms=["HS256"])
```

Safety scans will flag `python-jose` CVEs — evaluate migration to `PyJWT` or `joserfc`.

## Additional Dos

- Scan the full virtual environment after `pip install -e ".[dev,test]"` — pyproject.toml optional dependencies are not always scanned by requirements file scans.
- Monitor Starlette and uvicorn release notes alongside FastAPI — Starlette CVEs are often patched in a Starlette release before a FastAPI release bundles it.
- Add `python-multipart` to active monitoring — it is a required transitive dependency for file upload endpoints and has a CVE history.

## Additional Don'ts

- Don't suppress Starlette CVEs without also checking whether a patched FastAPI release is available — FastAPI pins Starlette to a version range; you may need to override it explicitly.
- Don't use `python-jose` for new projects — it has had multiple critical CVEs and is no longer actively maintained; use `PyJWT` or `joserfc` instead.
- Don't skip scanning `requirements-dev.txt` or `[project.optional-dependencies.test]` — test utilities like `faker` and `httpx` have had vulnerabilities that affect CI pipeline security.
