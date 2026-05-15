<div align="center">
  <a href="index.md">← Index</a> &nbsp;·&nbsp;
  <a href="../es/operations.md">🇪🇸 Ver en Español</a>
</div>

<br>

# Operations

Everything is managed with a single script from the project root.

---

## First launch

Clone the repository, copy the example configuration file, fill in the required values, and run the startup script. The platform will be available at `http://localhost` when it finishes.

The backend automatically creates an administrator account the first time it starts. The credentials are printed to the service logs:

```bash
docker logs iagentshub-backend-1 2>&1 | grep -A6 "Administrador"
```

If you missed them at startup, you can generate a new password by adding `GAIA_ADMIN_RESET: "true"` to the `environment` block of the `backend` service in the compose file, restarting, and reading the logs. **Remember to remove that line afterwards.**

---

## Available commands

| Command | What it does |
|---|---|
| `start` | Builds and starts all services |
| `stop` | Stops the services |
| `update` | Downloads the latest version and restarts |
| `logs` | Shows live activity |
| `status` | Current status of the services |

---

## Execution modes

**Production mode** — the default behavior. Always downloads the latest version of each repository from GitHub before building. Recommended for real environments.

**Development mode** — activated with the `--dev` flag. Instead of downloading from GitHub, uses the developer's local repositories. Allows iterating without pushing every change.

---

## Private repositories

If your repositories are on GitHub with private access, add a personal access token to the configuration. The script injects it automatically when starting in production mode.

---

## Updating

The update command stops the services, downloads the latest code, and restarts them. Existing data is not affected.
