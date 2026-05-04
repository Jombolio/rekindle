# HTTPS

The Rekindle Server speaks plain HTTP by default. This is fine for local network use, but if you expose the server to the internet you should add TLS.

Three options are available.

---

## Option A | Caddy (recommended)

[Caddy](https://caddyserver.com) is the simplest option. It automatically obtains and renews a Let's Encrypt certificate for your domain, no manual certificate management required.

### Prerequisites

- A domain name with a DNS A record pointing at your server's public IP.
- Port 80 and 443 open on the server firewall.
- Caddy installed ([install instructions](https://caddyserver.com/docs/install)).

### Caddyfile

Create a file named `Caddyfile`:

```
your.domain.com {
    reverse_proxy localhost:8080 {
        transport http {
            read_buffer  32KiB
            write_timeout 30m
            dial_timeout  30s
        }
    }
}
```

The extended `write_timeout` is important, without it, large archive uploads (several hundred MB) may time out mid-transfer.

### Start Caddy

```bash
caddy run --config Caddyfile
```

Caddy handles port 80/443 and forwards traffic to Rekindle on 8080. Your server is now accessible at `https://your.domain.com`.

---

## Option B | Nginx

If you prefer Nginx, you must raise the body size limit and extend the proxy timeouts. The Nginx defaults (`client_max_body_size 1m` and a 60-second read timeout) will cause large uploads to fail mid-transfer.

```nginx
server {
    listen 443 ssl;
    server_name your.domain.com;

    # SSL certificate config (e.g. from Certbot)
    ssl_certificate     /etc/letsencrypt/live/your.domain.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/your.domain.com/privkey.pem;

    # Required: allow large archive uploads (the Rekindle limit is 4 GB).
    client_max_body_size 4G;

    # Required: give uploads time to transfer over slow connections.
    proxy_read_timeout    1800;
    proxy_send_timeout    1800;
    proxy_connect_timeout   30;

    location / {
        proxy_pass http://localhost:8080;
        proxy_set_header Host              $host;
        proxy_set_header X-Real-IP         $remote_addr;
        proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        # Stream the upload body directly to Kestrel rather than buffering to disk.
        proxy_request_buffering off;
    }
}
```

> **Without `client_max_body_size 4G`** Nginx drops the TCP connection mid-upload and the client shows *Connection reset by peer*. This is the most common upload error when running behind Nginx.

---

## Option C | Kestrel direct TLS

If you already have a PEM certificate and key and do not want to run a reverse proxy, configure Kestrel to serve HTTPS directly in `appsettings.json`:

```json
{
  "Urls": "https://0.0.0.0:8443",
  "Kestrel": {
    "Endpoints": {
      "Https": {
        "Url": "https://0.0.0.0:8443",
        "Certificate": {
          "Path": "cert.pem",
          "KeyPath": "key.pem"
        }
      }
    }
  }
}
```

Place `cert.pem` and `key.pem` in the same directory as the server binary, then restart.

Certificate renewal is your responsibility, Kestrel will not renew certificates automatically.

---

## LAN-only use

If the server is only accessible on your home network, plain HTTP over an IP address (`http://192.168.1.x:8080`) is perfectly fine. No TLS setup is needed.
