# Traefik Reverse Proxy

A production-ready [Traefik v3](https://traefik.io/) reverse-proxy setup with:

- Automatic **HTTP → HTTPS** redirection
- **Let's Encrypt** TLS certificates (HTTP challenge)
- Password-protected **dashboard**
- Secure response-header **middleware**
- **Docker provider** (auto-discover containers on the `traefik-proxy` network)
- **File provider** (drop additional YAML config into `config/dynamic/`)

## Directory layout

```
traefik/
├── config/
│   ├── traefik.yml          # Static configuration
│   └── dynamic/
│       └── middlewares.yml  # Reusable middlewares (security headers, etc.)
├── docker-compose.yml
├── .env.example
├── setup.sh
└── README.md
```

## Quick start

### Prerequisites

| Tool | Notes |
|------|-------|
| Docker ≥ 24 | With the Compose plugin (`docker compose`) |
| `htpasswd` | `apt install apache2-utils` / `yum install httpd-tools` |
| A public domain | DNS A record pointing to your server |

### 1. Run the setup script

```bash
cd traefik
bash setup.sh
```

The script will:
1. Copy `.env.example` → `.env` (first run only).
2. Prompt you to edit the `.env` file.
3. Generate bcrypt-hashed dashboard credentials.
4. Start the stack with `docker compose up -d`.

### 2. Manual setup (alternative)

```bash
cp .env.example .env
# Edit .env — set TRAEFIK_DASHBOARD_HOST, ACME_EMAIL, and TRAEFIK_DASHBOARD_AUTH
docker compose up -d
```

#### Generating dashboard credentials

```bash
# Install htpasswd (if not already present)
apt install -y apache2-utils   # Debian / Ubuntu
# yum install -y httpd-tools   # RHEL / CentOS

# Generate a bcrypt hash (double every $ for Docker Compose)
htpasswd -nbB admin 'YourSecurePassword' | sed 's/\$/\$\$/g'
```

Paste the output as the value of `TRAEFIK_DASHBOARD_AUTH` in `.env`.

## Environment variables

| Variable | Description | Example |
|----------|-------------|---------|
| `TRAEFIK_DASHBOARD_HOST` | Hostname for the Traefik dashboard | `traefik.example.com` |
| `TRAEFIK_DASHBOARD_AUTH` | `htpasswd` bcrypt hash (dollars escaped) | `admin:$$2y$$...` |
| `ACME_EMAIL` | Email for Let's Encrypt notifications | `you@example.com` |

## Exposing other containers

Add these labels to any container you want Traefik to proxy:

```yaml
services:
  myapp:
    image: myapp:latest
    networks:
      - traefik-proxy
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.myapp.rule=Host(`app.example.com`)"
      - "traefik.http.routers.myapp.entrypoints=websecure"
      - "traefik.http.routers.myapp.tls.certresolver=letsencrypt"
      - "traefik.http.routers.myapp.middlewares=secure-headers@file"
      - "traefik.http.services.myapp.loadbalancer.server.port=8080"

networks:
  traefik-proxy:
    external: true
```

## Useful commands

```bash
# View logs
docker compose logs -f traefik

# Reload dynamic config (no restart needed)
# Just edit/add files under config/dynamic/ — Traefik watches the directory.

# Stop the stack
docker compose down

# Stop and remove volumes (certificates)
docker compose down -v
```
