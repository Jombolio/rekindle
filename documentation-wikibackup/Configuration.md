# Configuration

The server is configured by editing `appsettings.json` in the same directory as the binary. Changes take effect on the next restart.

---

## All options

| Key | Default | Description |
|-----|---------|-------------|
| `Rekindle.DataPath` | `data` | Where the server stores its SQLite database, JWT secret, and other runtime files |
| `Rekindle.CachePath` | `data/cache` | Where extracted page images are cached. Can be on a separate drive from the database |
| `Rekindle.CacheMaxSizeBytes` | `10737418240` | Maximum page cache size in bytes (default 10 GB). Oldest entries are evicted when the limit is reached |
| `Jwt.Secret` | *(auto-generated)* | JWT signing secret. Auto-generated and written to `data/jwt_secret.key` on first run. Set this manually if you run multiple server instances behind a load balancer |
| `Urls` | `http://0.0.0.0:8080` | The address and port Kestrel binds to. Accepts multiple values separated by semicolons |

---

## Examples

### Change the port

```json
{
  "Urls": "http://0.0.0.0:9000"
}
```

### Point at an existing media folder on a separate drive

```json
{
  "Rekindle": {
    "DataPath": "/mnt/media/rekindle/data",
    "CachePath": "/mnt/media/rekindle/cache"
  }
}
```

### Increase the cache size to 25 GB

```json
{
  "Rekindle": {
    "CacheMaxSizeBytes": 26843545600
  }
}
```

### Bind to localhost only (if behind a reverse proxy on the same machine)

```json
{
  "Urls": "http://127.0.0.1:8080"
}
```

---

## Notes

- All paths can be absolute or relative. Relative paths are resolved from the server binary's working directory.
- If `DataPath` or `CachePath` do not exist, the server creates them on first run.
- The JWT secret file (`data/jwt_secret.key`) is generated once and reused on subsequent starts. Do not delete it — doing so will invalidate all existing sessions and log everyone out.

---

## See also

- [HTTPS](HTTPS) — TLS configuration for Kestrel or a reverse proxy
- [Installing the Server](Installing-the-Server) — systemd and Windows Service setup
