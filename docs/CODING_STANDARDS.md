# Stoleus Tools — Coding Standards and Conventions

This document defines the coding standards and conventions used by the `tools` repository.

The purpose of these rules is not only to keep the code consistent, but also to make the infrastructure scripts predictable, safe, maintainable, readable, easy to troubleshoot, easy to extend, suitable for automation, and understandable months or years later.

The repository primarily uses Bash for Linux infrastructure automation.

---

# 1. Bash Script Header

Every Bash script should start with:

```bash
#!/usr/bin/env bash
```

This line is called the **shebang**. It tells Linux which interpreter should execute the script.

We use `#!/usr/bin/env bash` instead of `#!/bin/bash` because `/usr/bin/env` searches for `bash` using the current system `PATH`. This makes the script slightly more portable between different Linux environments.

Mental model:

```text
Script
  |
  v
/usr/bin/env
  |
  v
Find bash
  |
  v
Execute script
```

---

# 2. Strict Bash Mode

Scripts should normally contain:

```bash
set -Eeuo pipefail
```

This makes Bash behave more strictly and helps detect problems early.

## `-e`

Exit when a command fails.

Example:

```bash
cp missing-file.txt /tmp/
echo "Continue"
```

Without `-e`, Bash may continue executing the script even though the `cp` command failed. With `-e`, the script stops. This is important in infrastructure automation because continuing after a critical failure can leave the server in an inconsistent state.

## `-u`

Treat undefined variables as errors.

Example:

```bash
echo "$SERVER_NAME"
```

If `SERVER_NAME` has never been defined, the script fails. Without `-u`, Bash may silently interpret it as an empty value. This helps detect spelling mistakes, missing configuration, and incorrectly initialized variables.

## `-o pipefail`

Normally, Bash often uses the exit status of the final command in a pipeline.

Example:

```bash
some_command | grep "value"
```

If `some_command` fails but `grep` succeeds, the pipeline may appear successful. With `pipefail`, if any important command in the pipeline fails, the pipeline is considered failed.

This is especially important in CI/CD, GitHub Actions, installation scripts, health checks, and deployment automation.

## `-E`

Preserves `ERR` traps inside functions and subshells. This becomes useful when we later add centralized error handling.

---

# 3. Indentation

Use **4 spaces**. Do not use tabs.

Example:

```bash
if [[ "$status" == "active" ]]; then
    echo "Service is running"
fi
```

Consistent indentation makes shell scripts significantly easier to read. Bad formatting makes nested conditions and loops difficult to understand.

---

# 4. Always Quote Variable Expansions

Prefer:

```bash
echo "$SERVER_NAME"
```

instead of:

```bash
echo $SERVER_NAME
```

Suppose:

```bash
SERVER_NAME="my server"
```

An unquoted variable can be split into multiple shell arguments. Quoted variables preserve their contents correctly.

Use `"$variable"` unless there is a specific reason not to quote it.

Examples:

```bash
cp "$source" "$destination"
systemctl status "$service_name"
echo "$message"
```

Quoting prevents many subtle shell scripting bugs.

---

# 5. Prefer Bash `[[ ... ]]` Conditions

Use:

```bash
if [[ -f "$FILE" ]]; then
```

instead of:

```bash
if [ -f "$FILE" ]; then
```

`[[ ... ]]` is Bash's more powerful conditional syntax. Because this project specifically targets Bash, there is no need to restrict ourselves to older generic POSIX shell syntax.

Examples:

```bash
if [[ "$status" == "active" ]]; then
if [[ -d "$directory" ]]; then
if [[ "$usage" =~ ^[0-9]+$ ]]; then
if [[ -z "$value" ]]; then
```

It is clearer and safer for many Bash operations.

---

# 6. Function Naming

Functions use `snake_case`.

Examples:

```bash
check_docker()
check_postgresql()
check_network()
print_error()
```

Do not mix styles such as `CheckDocker()` or `checkDocker()`.

Using one naming convention keeps the project predictable.

---

# 7. Variable Naming

Regular and local variables use lowercase snake case.

Examples:

```bash
server_name
docker_status
log_file
available_memory
```

Constants, configuration values, and environment-style values use uppercase snake case.

Examples:

```bash
DEPLOY_USER
LOG_DIR
DISK_WARNING_PERCENT
DISK_CRITICAL_PERCENT
```

Mental model:

- `lowercase_snake_case` = local variable, temporary value, function name
- `UPPERCASE_SNAKE_CASE` = constant, configuration value, environment variable

---

# 8. Use `local` Variables Inside Functions

Example:

```bash
check_service() {
    local service_name="$1"

    systemctl status "$service_name"
}
```

Without `local`, Bash variables can affect the global shell scope. That means one function could accidentally overwrite a variable used by another function.

This is similar to variable scope in C#.

Prefer `local` whenever a variable belongs only to a function.

---

# 9. Use `readonly` for Constants

Values that should not change after initialization should use `readonly`.

Examples:

```bash
readonly LOG_FILE="/var/log/stoleus/health.log"
readonly DEPLOY_USER="deployer"
readonly DISK_WARNING_PERCENT=85
```

This prevents accidental reassignment and communicates intent clearly: the value is expected to remain constant throughout execution.

---

# 10. Standard Output and Standard Error

Linux programs have separate output channels.

- Normal output goes to `stdout`.
- Errors go to `stderr`.

Normal message:

```bash
echo "Docker is running"
```

Error message:

```bash
echo "Docker is not installed" >&2
```

The `>&2` redirects the message to stderr.

This distinction matters for automation, GitHub Actions, logging, pipes, monitoring, and scripting.

Example:

```bash
stoleus health > health-report.txt
```

Normal output can be redirected while errors remain visible separately.

---

# 11. Exit Codes

Linux programs communicate success or failure through exit codes.

Convention:

- `0` = success
- non-zero = failure

Example:

```bash
exit 0
```

means the operation completed successfully.

Example:

```bash
exit 1
```

means the operation failed.

Different non-zero exit codes can later represent different types of errors, for example:

```text
1 = general error
2 = invalid command or arguments
3 = configuration error
```

Systemd, GitHub Actions, and CI/CD tools rely heavily on exit codes.

---

# 12. Idempotency

Infrastructure commands should be **idempotent whenever possible**.

Idempotent means:

> Running the same operation multiple times should leave the system in the same desired state without causing damage.

Instead of:

```bash
mkdir /opt/apps
```

prefer:

```bash
mkdir -p /opt/apps
```

If the directory already exists, the second command remains safe.

Another example: before adding a user to the Docker group, check whether the user is already a member.

Infrastructure scripts are frequently run repeatedly during deployment, recovery, server provisioning, CI/CD, and troubleshooting. A command should not break simply because it has already been executed once.

---

# 13. Health Checks Must Be Read-Only by Default

The command:

```bash
stoleus health
```

should inspect the server.

It should not unexpectedly restart services, modify firewall rules, install packages, create users, delete files, or change system configuration.

Health checks should answer:

> Is the system healthy?

Repair operations should be explicit.

Examples:

```bash
stoleus repair
```

or:

```bash
stoleus health --repair
```

This protects production systems from unexpected changes.

---

# 14. One Command Should Have One Responsibility

Commands should be separated by purpose.

Example:

```text
commands/
├── health.sh
├── docker.sh
├── postgres.sh
├── runner.sh
├── backup.sh
└── update.sh
```

Avoid creating a giant script such as `commands/everything.sh`.

Smaller focused commands are easier to understand, test, troubleshoot, maintain, and reuse.

This follows the Single Responsibility Principle.

---

# 15. Shared Logic Belongs in `lib/`

If several commands need the same function, do not duplicate it.

Example shared functions:

```bash
command_exists()
unit_exists()
print_error()
read_config()
```

These should live in `lib/`, for example `lib/common.sh`.

Commands then reuse the same implementation.

This follows the DRY principle:

> Don't Repeat Yourself.

---

# 16. Project Directory Responsibilities

The repository structure has specific responsibilities.

## `bin/`

Contains public executable entry points.

Example:

```text
bin/stoleus
```

This should remain small. Its main responsibility is to read the command requested by the user, find the corresponding command implementation, and execute it.

Example:

```text
stoleus health
       |
       v
commands/health.sh
```

## `commands/`

Contains individual command implementations.

Examples:

```text
commands/help.sh
commands/version.sh
commands/health.sh
commands/docker.sh
commands/postgres.sh
```

Each command should focus on one responsibility.

## `lib/`

Contains shared reusable Bash code.

Examples:

```text
lib/common.sh
lib/logging.sh
lib/colors.sh
lib/system.sh
lib/docker.sh
```

Functions used by several commands belong here.

## `config/`

Contains example or default configuration files.

Example:

```text
config/stoleus.conf.example
```

The actual production configuration may eventually live under `/etc/stoleus/`. The repository contains the template or example.

## `templates/`

Contains files that the toolkit may install somewhere else.

Examples:

```text
templates/server-health.service
templates/backup.service
templates/backup.timer
templates/docker-compose.yml
```

For example, `tools/templates/server-health.service` may later be copied to `/etc/systemd/system/server-health.service`.

Important: systemd does not read files directly from `tools/templates`. They are source templates managed in Git.

## `docs/`

Contains project documentation.

Examples:

```text
docs/CODING_STANDARDS.md
docs/ARCHITECTURE.md
docs/DOCKER.md
docs/HEALTH.md
```

## `tests/`

Contains automated tests.

Example:

```text
tests/smoke.sh
```

Tests should verify basic command behavior.

---

# 17. Configuration Files

This project will primarily use shell-compatible key/value configuration.

Example:

```bash
DEPLOY_USER="deployer"
LOG_DIR="/var/log/stoleus"
DISK_WARNING_PERCENT=85
DISK_CRITICAL_PERCENT=95
```

Bash can load this with:

```bash
source "/etc/stoleus/stoleus.conf"
```

We intentionally avoid introducing unnecessary INI, YAML, or JSON parsers while the project remains Bash-based.

Simple configuration is easier to understand, load, maintain, and troubleshoot.

---

# 18. Git Branch Naming

Branches should clearly describe their purpose.

Feature branches:

```text
feature/<name>
```

Examples:

```text
feature/entry-point
feature/health-command
feature/docker-command
```

Bug fixes:

```text
fix/<name>
```

Examples:

```text
fix/docker-permissions
fix/health-inode-check
```

Documentation:

```text
docs/<name>
```

Examples:

```text
docs/readme
docs/docker-guide
```

This makes the repository history easier to understand.

---

# 19. Git Commit Messages

Commit messages should clearly describe the change.

Use imperative mood.

Good examples:

```text
Add stoleus entry point
Add health command
Fix Docker service detection
Add coding standards documentation
Update installation instructions
```

Avoid vague messages such as:

```text
changes
update
stuff
fix
```

A commit message should explain what the commit does.

---

# 20. Release Commit Naming

Release commits use:

```text
Release vX.Y.Z
```

Example:

```text
Release v0.1.0
```

This makes release points easy to identify in Git history.

---

# 21. Semantic Versioning

The project follows Semantic Versioning.

Format:

```text
MAJOR.MINOR.PATCH
```

Example:

```text
0.1.0
```

## MAJOR

Changes when incompatible or major architectural changes are introduced.

Example:

```text
1.0.0 -> 2.0.0
```

## MINOR

Changes when new backward-compatible functionality is added.

Example:

```text
0.1.0 -> 0.2.0
```

For example, introducing `stoleus health` may justify a new minor release.

## PATCH

Changes when backward-compatible bug fixes are added.

Example:

```text
0.1.0 -> 0.1.1
```

Examples include fixing incorrect Docker detection, output formatting, or a typo in a script.

---

# 22. Bash Syntax Validation

Before committing Bash code, run:

```bash
bash -n script.sh
```

Example:

```bash
bash -n bin/stoleus
```

This checks Bash syntax without executing the script.

Multiple files:

```bash
bash -n bin/stoleus commands/*.sh lib/*.sh
```

No output usually means the syntax is valid.

This should be part of the normal development workflow.

---

# 23. ShellCheck

We will use **ShellCheck** as the static analyzer for Bash.

Example:

```bash
shellcheck bin/stoleus
```

Eventually:

```bash
shellcheck bin/stoleus commands/*.sh lib/*.sh tests/*.sh
```

ShellCheck detects unsafe quoting, unused variables, suspicious pipelines, incorrect conditionals, common Bash mistakes, and portability concerns.

Think of ShellCheck similarly to a static code analyzer in C#.

---

# 24. Avoid Unnecessary `sudo` Inside Scripts

Do not sprinkle `sudo` throughout scripts.

Instead, if a command requires root privileges, verify it explicitly.

Example:

```bash
if [[ "$EUID" -ne 0 ]]; then
    echo "Run this command as root." >&2
    exit 1
fi
```

Then the user runs:

```bash
sudo stoleus repair
```

This makes privilege requirements clear and makes automation easier to reason about.

---

# 25. Never Store Secrets in Git

Do not commit:

- passwords
- database passwords
- API keys
- GitHub tokens
- private SSH keys
- production `.env` files
- cloud credentials
- certificates containing private keys

Example configuration files should use placeholders.

Example:

```bash
DATABASE_PASSWORD="CHANGE_ME"
```

Real secrets should live outside Git.

Possible future locations include environment variables, protected `.env` files, GitHub Secrets, and secret managers.

---

# 26. Prefer Explicit Commands Over Clever Commands

Infrastructure scripts should prioritize readability over cleverness.

A shorter command is not automatically better.

Prefer:

```bash
if systemctl is-active --quiet docker; then
```

over extremely compact expressions that are difficult to understand.

Operational code should be boring, clear, and predictable. This is a positive quality in infrastructure tooling.

---

# 27. Comments Explain Why, Not the Obvious

Bad comment:

```bash
# Start Docker
systemctl start docker
```

The code already explains what it does.

Better:

```bash
# Docker must be available before deployment containers can be restored.
systemctl start docker
```

Comments should explain why something exists, why a special decision was made, why a failure is ignored, or why a workaround is required.

Do not comment every obvious line.

---

# 28. Avoid Silent Failures

Do not hide meaningful failures using:

```bash
command || true
```

unless failure is explicitly acceptable.

If `|| true` is used, there should normally be a reason.

Example:

```bash
# This cleanup is optional; failure must not block deployment.
rm -f "$temporary_file" || true
```

Critical failures should remain visible.

---

# 29. Validate Inputs

Commands should validate user-provided input before making system changes.

Example:

```bash
if [[ -z "$service_name" ]]; then
    echo "Service name is required." >&2
    exit 2
fi
```

Before using a path:

```bash
if [[ ! -d "$directory" ]]; then
    echo "Directory does not exist: $directory" >&2
    exit 1
fi
```

Never blindly assume input is correct.

This is especially important for commands that delete files, restart services, change permissions, modify firewall rules, or modify databases.

---

# 30. Prefer Predictable Output

Commands should use consistent output.

Eventually we will standardize statuses such as:

```text
PASS
WARN
FAIL
SKIP
INFO
```

Example:

```text
Docker Engine        PASS
Docker Compose       PASS
PostgreSQL           SKIP
Disk Space           WARN
```

Predictable output helps both humans and future automation.

Avoid random output styles between commands.

---

# 31. Separate Detection From Modification

Prefer separate functions:

```bash
check_docker()
```

and:

```bash
repair_docker()
```

instead of one function that silently checks and changes the system.

Mental model:

```text
check_docker
    |
    +--> inspect only

repair_docker
    |
    +--> make changes
```

This separation makes the program safer and easier to reason about.

---

# 32. Repository Philosophy

The `tools` repository should follow these principles:

1. Safe by default.
2. Readable over clever.
3. Modular instead of monolithic.
4. Repeatable and idempotent.
5. Explicit when modifying the system.
6. Easy to troubleshoot.
7. Suitable for automation.
8. Version controlled.
9. Properly documented.
10. Testable.
11. Predictable in its output.
12. Conservative with root privileges.
13. Never store secrets in Git.
14. Separate health checking from repair behavior.
15. Prefer simple solutions unless complexity is justified.

The long-term goal is that a Linux administrator or developer can understand what a command does, what files it changes, what privileges it requires, what happens when it fails, and whether it is safe to run again before executing it.

---

# Quick Reference

## Bash header

```bash
#!/usr/bin/env bash
set -Eeuo pipefail
```

## Naming

```text
Functions:
snake_case

Local variables:
snake_case

Constants/config:
UPPERCASE_SNAKE_CASE
```

## Conditions

Prefer:

```bash
[[ ... ]]
```

## Variables

Prefer:

```bash
"$variable"
```

## Function variables

Prefer:

```bash
local value
```

## Constants

Prefer:

```bash
readonly VALUE="something"
```

## Errors

Use:

```bash
echo "Error" >&2
```

## Success

Return:

```bash
exit 0
```

## Failure

Return non-zero:

```bash
exit 1
```

## Syntax check

```bash
bash -n bin/stoleus commands/*.sh lib/*.sh
```

## Static analysis

```bash
shellcheck bin/stoleus commands/*.sh lib/*.sh tests/*.sh
```

## Feature branch

```text
feature/<name>
```

## Fix branch

```text
fix/<name>
```

## Documentation branch

```text
docs/<name>
```

## Release commit

```text
Release vX.Y.Z
```

## Version format

```text
MAJOR.MINOR.PATCH
```

Example:

```text
0.1.0
```

---

# Final Principle

Infrastructure code should be easy to understand when something goes wrong.

The most important rule for this repository is:

> Prefer clear, explicit, predictable code over clever code.

A script that is slightly longer but easy to understand is usually better than a compact script that is difficult to troubleshoot during a production incident.
