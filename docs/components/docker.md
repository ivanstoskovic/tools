# Docker

## Purpose

Install and verify Docker Engine.

---

## Responsibilities

- remove legacy packages
- configure Docker repository
- install packages
- enable Docker
- verify installation

---

## Installed Packages

- docker-ce
- docker-ce-cli
- containerd.io
- docker-buildx-plugin
- docker-compose-plugin

---

## Verification

```bash
docker version

docker compose version

docker buildx version
```

---

## Future Improvements

- Docker daemon configuration
- Registry mirrors
- Build cache configuration