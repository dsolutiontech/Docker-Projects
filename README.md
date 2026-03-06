# Docker-Projects

A collection of ready-to-use Docker Compose configurations and automated setup scripts to help you deploy common self-hosted services quickly and confidently.

## Sub-projects

| Project | Description |
|---------|-------------|
| [traefik](./traefik/) | Production-ready Traefik v3 reverse proxy with automatic HTTPS (Let's Encrypt) and a password-protected dashboard |
| [wazuh](./wazuh/) | Single-node Wazuh security monitoring stack (Manager + Indexer + Dashboard) with auto-generated TLS certificates |

## Getting started

Each sub-project is self-contained and ships with:

- A `docker-compose.yml` — ready to run.
- A `.env.example` — copy to `.env` and fill in your values.
- A `setup.sh` — automates the bootstrapping steps.
- A `README.md` — full documentation for that project.

### General workflow

```bash
# Clone the repository
git clone https://github.com/dsolutiontech/Docker-Projects.git
cd Docker-Projects

# Navigate to the sub-project you want
cd traefik        # or: cd wazuh

# Run the setup script
bash setup.sh
```

## Requirements

- **Docker** ≥ 24 with the Compose plugin (`docker compose`)
- A Linux host (recommended; some projects require kernel tuning)

## Contributing

Pull requests are welcome! If you have a Docker Compose stack you'd like to add, please open a PR with:

1. A new top-level directory named after the project.
2. A `docker-compose.yml`, `.env.example`, `setup.sh`, and `README.md`.

## License

[MIT](./LICENSE)
