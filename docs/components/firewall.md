# Firewall

## Purpose

Configure UFW with secure default settings.

---

## Responsibilities

- install UFW
- configure default policies
- allow required services
- enable firewall
- verify configuration

---

## Default Rules

Incoming

```
deny
```

Outgoing

```
allow
```

Allowed services

- OpenSSH
- HTTP
- HTTPS

---

## Verification

```bash
sudo ufw status
```

---

## Future Improvements

- custom profiles
- configurable ports
- application presets