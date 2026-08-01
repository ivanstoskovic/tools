# Architecture

```
                 User
                   │
                   ▼
            bin/stoleus
                   │
                   ▼
             Command Layer
                   │
                   ▼
             Library Layer
                   │
      ┌────────────┼────────────┐
      ▼            ▼            ▼
   Chrony      Firewall      Docker
                   │
                   ▼
            Linux Services
                   │
                   ▼
             Linux Kernel
```