# Architecture

---

## Philosophy

The project follows a layered architecture.

```
CLI

↓

Commands

↓

Libraries

↓

Infrastructure Components

↓

Linux
```

Every layer has a single responsibility.

---

## Repository Layout

```
bin/
commands/
lib/
docs/
```

---

## Command Layer

Responsible for:

- parsing arguments
- displaying help
- invoking libraries

No infrastructure logic belongs here.

---

## Library Layer

Contains reusable implementation.

Examples:

```
common.sh

pipeline.sh

setup/
```

---

## Component Layer

Each infrastructure component lives in its own module.

Example:

```
docker.sh

chrony.sh

firewall.sh
```

This keeps the project modular and maintainable.

---

## Pipeline Engine

Server profiles are built from reusable pipeline steps.

Example:

```
Chrony

↓

Firewall

↓

Docker

↓

Directories
```

Pipelines stop immediately on failure.