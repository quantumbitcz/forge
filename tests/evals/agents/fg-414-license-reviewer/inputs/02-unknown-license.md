# Eval: Dependency with unrecognised SPDX identifier

## Language: python

## Context
A pinned dependency declares a license string that is not a recognised SPDX identifier and is not mapped in the project's policy file. Fail-open default: emit WARNING.

## Code Under Review

```
# file: requirements.txt
requests==2.31.0
obscure-pkg==0.4.1
```

```
# site-packages/obscure-pkg-0.4.1.dist-info/METADATA
License: Some-Custom-License v2.0
```

## Expected Behavior
Reviewer should emit `LICENSE-UNKNOWN` at WARNING for `obscure-pkg@0.4.1` because the declared license string does not resolve to a known SPDX identifier. Fail-open default means this does not escalate to CRITICAL.
