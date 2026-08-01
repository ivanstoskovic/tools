# Contributing to Stoleus

Thank you for contributing to Stoleus.

Although the project is currently maintained by a single developer, contributions are expected to follow the same engineering standards to ensure the project remains predictable, maintainable, and production-ready.

---

# Development Philosophy

Every change should improve one or more of the following:

- Simplicity
- Reliability
- Maintainability
- Readability
- Reusability

Avoid unnecessary complexity.

---

# Engineering Workflow

Every feature follows the same lifecycle.

```
Architecture
      │
      ▼
Implementation
      │
      ▼
Validation
      │
      ▼
Testing
      │
      ▼
Documentation
      │
      ▼
Commit
```

---

# Coding Standards

## General

- Keep functions small.
- One responsibility per function.
- Prefer reusable code over duplication.
- Use meaningful names.
- Document complex logic.
- Validate before committing.

---

## Bash

Every Bash file should begin with:

```bash
#!/usr/bin/env bash

set -Eeuo pipefail
```

Use:

- local variables
- quoted variables
- explicit error handling
- reusable helper functions

---

# Validation

Before every commit run:

```bash
bash -n bin/stoleus
bash -n commands/*.sh
bash -n lib/*.sh
bash -n lib/setup/*.sh
```

Then test on a staging server.

---

# Pull Requests

Every pull request should include:

- Description
- Motivation
- Testing performed
- Documentation updates

---

# Commit Messages

Examples:

```
feat: add Docker installation

fix: improve Chrony verification

refactor: split setup library into modules

docs: add Docker component documentation
```

---

Quality is more important than speed.