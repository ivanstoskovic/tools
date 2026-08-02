# GitHub Runner Component

## Overview

The GitHub Runner component installs and configures a GitHub Actions
self-hosted runner on a Linux server.

After installation, GitHub Actions workflows can execute directly on the
server without requiring GitHub-hosted runners.

The component is fully idempotent.

Running the command multiple times does not create duplicate runners or
duplicate systemd services.

---

# Purpose

This component automates the complete lifecycle of a GitHub Actions runner.

It performs:

- validation
- download
- extraction
- registration
- service installation
- verification

No manual runner installation is required.

---

# Command

```bash
sudo stoleus setup github-runner \
    --url https://github.com/OWNER/REPOSITORY \
    --name repository-name \
    --labels self-hosted,linux,x64
```

Example:

```bash
sudo stoleus setup github-runner \
    --url https://github.com/ivanstoskovic/tools \
    --name tools \
    --labels self-hosted,linux,x64
```

---

# Command Line Options

| Option | Required | Description |
|---------|----------|-------------|
| `--url` | Yes | GitHub repository URL |
| `--name` | Yes | Short runner identifier |
| `--labels` | No | Runner labels (default: `self-hosted,linux`) |
| `--user` | No | Linux user that owns the runner (default: `deployer`) |
| `--version` | No | GitHub Runner version (default: pinned version) |

---

# Installation Directory

Each repository receives its own installation directory.

Example:

```text
/opt/runners/tools
```

Advantages:

- isolated installations
- independent upgrades
- simple removal
- easier troubleshooting

---

# Runner Name

The runner name visible inside GitHub is generated automatically.

Format:

```text
<hostname>-<repository>
```

Example:

```text
stoleusstage-tools
```

This guarantees uniqueness across multiple servers.

---

# Service Name

GitHub creates a systemd service.

Example:

```text
actions.runner.owner-repository.stoleusstage-tools.service
```

Stoleus automatically discovers the service created during installation and
verifies that the correct runner service is enabled and running.

---

# Installation Pipeline

The component follows a pipeline architecture.

```text
Validate
        │
        ▼
Detect Architecture
        │
        ▼
Resolve Version
        │
        ▼
Download
        │
        ▼
Extract
        │
        ▼
Configure
        │
        ▼
Install Service
        │
        ▼
Verify
```

Each step has exactly one responsibility.

---

# Download

The runner archive is downloaded from the official GitHub releases.

Example:

```text
https://github.com/actions/runner/releases/download/v2.334.0/
actions-runner-linux-x64-2.334.0.tar.gz
```

Downloads use the shared

```
download_file()
```

helper.

Features:

- HTTPS only
- temporary download file
- automatic cleanup
- atomic move
- download verification

---

# Extraction

Archives are extracted using

```
extract_tar_gz()
```

into

```text
/opt/runners/<repository>
```

Ownership is assigned to the configured runner user.

---

# Registration

Registration is performed using GitHub's

```
config.sh
```

script.

Configuration is executed non-interactively.

The runner receives:

- repository URL
- runner name
- labels
- work directory

---

# Registration Token

The GitHub registration token is **never stored**.

The token:

- is requested interactively
- is hidden while typing
- exists only in memory
- is removed immediately after registration

Stoleus never:

- writes the token to disk
- stores it in configuration files
- prints it in logs
- accepts it as a command-line argument

---

# Service Installation

The component installs the systemd service using GitHub's

```
svc.sh
```

The service is installed for the configured Linux user.

Example:

```text
deployer
```

The service is automatically:

- installed
- enabled
- started

---

# Verification

The component verifies:

- runner archive downloaded
- extraction succeeded
- registration completed
- systemd service exists
- service is enabled
- service is running

The setup completes successfully only when every verification succeeds.

---

# Idempotency

Running the command multiple times is safe.

Existing resources are reused whenever possible.

Examples:

- existing installation directory
- existing runner registration
- existing service
- existing download

No duplicate runners are created.

---

# Shared Infrastructure Helpers

The component uses reusable helpers from

```
lib/common.sh
```

including:

- `download_file()`
- `extract_tar_gz()`
- `create_directory()`
- `ensure_service_enabled_and_running()`

This keeps component code small and focused.

---

# Design Principles

The GitHub Runner component follows the Stoleus architecture guidelines.

- one responsibility per function
- reusable infrastructure helpers
- fail fast
- explicit validation
- idempotent operations
- predictable behavior
- detailed logging
- no hidden side effects

---

# Future Improvements

Planned enhancements include:

- automatic runner removal
- runner upgrades
- checksum verification
- automatic latest-version discovery
- organization-level runners
- enterprise runners
- runner groups
- runner replacement
- offline installation
- proxy configuration
- non-interactive token providers

These features will build on the current architecture without changing the
public command interface.