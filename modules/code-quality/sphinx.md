---
name: sphinx
categories: [doc-generator]
languages: [python]
exclusive_group: python-doc-generator
recommendation_score: 90
detection_files: [conf.py, docs/conf.py, sphinx.toml]
---

# sphinx

## Overview

Sphinx is the standard Python documentation generator. Install via `pip install sphinx`. Configuration lives in `conf.py`. Sphinx natively uses reStructuredText (reST), but MyST-Parser enables full CommonMark/Markdown support. Core extensions: `autodoc` (pull docstrings into API pages), `napoleon` (Google/NumPy docstring styles), `intersphinx` (cross-project linking). Read the Docs hosts Sphinx projects for free with automatic PR preview builds.

## Architecture Patterns

### Installation & Setup

```bash
pip install sphinx sphinx-autodoc-typehints myst-parser furo
# Optional extensions
pip install sphinx-copybutton sphinx-design sphinxcontrib-mermaid

# Scaffold a new project
sphinx-quickstart docs/
```

**`docs/conf.py`:**
```python
project = "My Package"
author = "Your Team"
release = "1.0.0"

extensions = [
    "sphinx.ext.autodoc",
    "sphinx.ext.napoleon",
    "sphinx.ext.intersphinx",
    "sphinx.ext.viewcode",
    "sphinx.ext.autosummary",
    "sphinx_autodoc_typehints",
    "myst_parser",
]

# HTML theme
html_theme = "furo"

# Autodoc settings
autodoc_default_options = {
    "members": True,
    "undoc-members": False,
    "private-members": False,
    "show-inheritance": True,
    "member-order": "bysource",
}
autodoc_typehints = "description"
autodoc_typehints_format = "short"

# Napoleon (Google-style docstrings)
napoleon_google_docstring = True
napoleon_numpy_docstring = False
napoleon_include_init_with_doc = True

# Intersphinx — cross-link to other Sphinx projects
intersphinx_mapping = {
    "python": ("https://docs.python.org/3", None),
    "requests": ("https://requests.readthedocs.io/en/latest/", None),
}

# MyST Markdown support
myst_enable_extensions = ["colon_fence", "deflist"]
source_suffix = {".rst": "restructuredtext", ".md": "markdown"}
```

### Rule Categories

| Category | Pattern | Pipeline Severity |
|---|---|---|
| Missing module docstring | Public module without top-level docstring | WARNING |
| Missing function docstring | Public function/method without docstring | WARNING |
| Missing `Args` / `Returns` | Google-style function without param docs | INFO |
| Broken cross-reference | ``:class:`Foo` `` pointing to undefined symbol | WARNING |
| Deprecated `automodule` without `:members:` | Automodule that hides all members | INFO |

### Configuration Patterns

**Google-style docstring (recommended with Napoleon):**
```python
def fetch_users(org_id: int, active_only: bool = True) -> list[User]:
    """Fetches all users belonging to the given organisation.

    Args:
        org_id: The organisation's database identifier.
        active_only: When True, only returns non-suspended accounts.

    Returns:
        A list of :class:`User` objects sorted by creation date (newest first).

    Raises:
        NotFoundError: If the organisation does not exist.
        PermissionError: If the caller lacks read access to the organisation.

    Example:
        >>> users = fetch_users(org_id=42)
        >>> len(users) > 0
        True
    """
```

**Auto-generating API pages:**
```rst
.. docs/api/users.rst
Users API
=========

.. automodule:: mypackage.users
   :members:
   :undoc-members:
   :show-inheritance:
```

**`autosummary` for large packages:**
```rst
.. autosummary::
   :toctree: generated/
   :recursive:

   mypackage
```

**Read the Docs config (`.readthedocs.yaml`):**
```yaml
version: 2

build:
  os: ubuntu-22.04
  tools:
    python: "3.12"

sphinx:
  configuration: docs/conf.py

python:
  install:
    - requirements: docs/requirements.txt
    - method: pip
      path: .
```

### CI Integration

```yaml
# .github/workflows/docs.yml
- name: Install Sphinx dependencies
  run: pip install -r docs/requirements.txt

- name: Build Sphinx docs (strict mode)
  run: sphinx-build -W --keep-going -b html docs/ docs/_build/html

- name: Upload docs artifact
  uses: actions/upload-artifact@v4
  with:
    name: sphinx-html
    path: docs/_build/html/
```

`-W` promotes warnings to errors. `--keep-going` reports all issues before failing.

## Performance

- `autodoc` imports every module it documents — keep `conf.py` imports minimal and mock heavy dependencies with `autodoc_mock_imports`.
- `autosummary :recursive:` generates stub `.rst` files on first run. Commit generated stubs or add them to `.gitignore` and regenerate in CI.
- Sphinx incremental builds are fast for unchanged pages. Use `sphinx-build -E` only when resetting the environment cache is needed.
- Large projects: parallelize with `sphinx-build -j auto` (uses all available cores).

## Security

- Sphinx executes Python during `autodoc` — `conf.py` and all documented modules run at build time. Do not run Sphinx on untrusted code.
- `.. code-block::` and `.. literalinclude::` directives do not execute code, but `doctest` and `testcode` directives do.
- Avoid including secrets in docstrings — they appear verbatim in generated HTML and are often indexed by search engines.

## Testing

```bash
# Build HTML docs
sphinx-build -b html docs/ docs/_build/html

# Strict mode — fail on any warning
sphinx-build -W -b html docs/ docs/_build/html

# Check external links
sphinx-build -b linkcheck docs/ docs/_build/linkcheck

# Run doctest examples embedded in docs
sphinx-build -b doctest docs/ docs/_build/doctest

# Auto-rebuild on file change (local development)
sphinx-autobuild docs/ docs/_build/html
```

## Dos

- Use `-W --keep-going` in CI to treat all warnings as errors while reporting every issue in one pass.
- Enable `intersphinx` for every major dependency — cross-project links give readers context without duplicating docs.
- Write Google-style docstrings and enable `napoleon` — they are more readable in source code than reST field lists.
- Use `autosummary :recursive:` for large packages to auto-generate the API index rather than hand-maintaining `.rst` files.
- Configure Read the Docs with `.readthedocs.yaml` versioned in the repo — ensures reproducible doc builds.
- Add `sphinx.ext.viewcode` to link generated docs back to the highlighted source code.

## Don'ts

- Don't use `autodoc_default_options: {undoc-members: True}` in public libraries — it exposes undocumented internals. Document intentionally.
- Don't run `sphinx-build` without `-W` in CI — warnings about broken references are silently ignored.
- Don't mix reST and Markdown in the same file — MyST-Parser handles `.md` files but cannot parse inline reST syntax inside them.
- Don't commit `docs/_build/` — regenerate on every CI run and deploy the artifact.
- Don't skip `docs/requirements.txt` — pinning Sphinx and extension versions prevents surprise CI breakage on version updates.
- Don't use the default Alabaster theme for public projects — Furo or PyData Sphinx Theme provide modern mobile-friendly layouts.
