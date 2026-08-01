# Architecture Decision Record

This document records important architectural decisions made during the development of Stoleus.

---

# ADR-0001

## Title

Split setup into feature modules.

## Status

Accepted

## Motivation

The setup library had grown beyond 1,500 lines.

Maintenance and navigation became increasingly difficult.

## Decision

Split the setup library into dedicated feature modules.

Example

```
chrony.sh

firewall.sh

docker.sh

directories.sh
```

## Consequences

Advantages

- Smaller files
- Easier maintenance
- Better scalability
- Cleaner reviews

Tradeoff

- More files to manage

---

# ADR-0002

## Title

Introduce the Pipeline Engine.

## Status

Accepted

## Motivation

Server profiles required reusable execution logic.

## Decision

Introduce a generic pipeline engine responsible for:

- step execution
- progress reporting
- failure handling

## Consequences

- reusable pipelines
- cleaner server profiles
- centralized reporting

---

# ADR-0003

## Title

Use Docker's official APT repository.

## Status

Accepted

## Motivation

Docker packages in Ubuntu repositories may lag behind.

## Decision

Install Docker using Docker's official repository.

## Consequences

- newer versions
- officially supported packages

---

Future architectural decisions should be added here.