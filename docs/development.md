# Development Guide

---

## Project Structure

```
bin/

commands/

lib/

docs/
```

---

## Adding a Component

1. Create module

```
lib/setup/example.sh
```

2. Load module

```
lib/setup.sh
```

3. Add command

```
commands/setup.sh
```

4. Update documentation.

---

## Validation

```
bash -n ...
```

Run local validation before testing on Linux.

---

## Testing

1. Local syntax validation

2. Test on staging

3. Test on production

---

## Documentation

Every feature requires documentation before it is considered complete.