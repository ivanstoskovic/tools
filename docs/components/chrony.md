# Chrony

## Purpose

Chrony provides accurate system time synchronization using NTP.

Reliable system time is essential for:

- TLS certificates
- Docker
- Logging
- Scheduled jobs
- Authentication

---

## Responsibilities

The Chrony component:

- installs Chrony
- enables the service
- starts the service
- verifies synchronization

---

## Verification

Verification includes:

- service enabled
- service running
- successful synchronization

---

## Troubleshooting

Useful commands

```bash
systemctl status chrony

chronyc tracking

chronyc sources
```

---

## Future Improvements

- configurable synchronization timeout
- configurable NTP servers