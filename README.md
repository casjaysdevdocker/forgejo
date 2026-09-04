# forgejo

A self-hosted Docker image for [Forgejo](https://forgejo.org) — a lightweight, fast Git hosting service (a hard fork of Gitea) — bundled with the Forgejo Actions runner (`act_runner`) and Docker-in-Docker support so CI pipelines run out of the box.

---

## 🐳 Docker

### Quick start

```shell
docker run -d \
  --name casjaysdevdocker-forgejo-latest \
  --privileged \
  --restart always \
  --tty \
  --cgroupns private \
  --hostname git.example.com \
  --domainname example.com \
  --network bridge \
  --cap-add CHOWN \
  --cap-add SYS_TIME \
  --cap-add SYS_ADMIN \
  -e TZ=America/New_York \
  -e HOSTNAME=git.example.com \
  -e FORGEJO_PROTO=http \
  -e DATABASE_DIR_SQLITE=/data/db/sqlite \
  -v /srv/docker/forgejo/data:/data:z \
  -v /srv/docker/forgejo/config:/config:z \
  -v /srv/docker/databases/sqlite/forgejo:/data/db/sqlite:z \
  -p 80:80 \
  -p 22:22 \
  casjaysdevdocker/forgejo:latest
```

### via docker compose

```yaml
# nginx proxy address - http://172.17.0.1:80

x-logging: &default-logging
  driver: json-file
  options:
    max-size: "5m"
    max-file: "1"

services:
  forgejo:
    image: casjaysdevdocker/forgejo:latest
    pull_policy: always
    container_name: casjaysdevdocker-forgejo-latest
    hostname: git.example.com
    domainname: example.com
    privileged: true
    tty: true
    restart: always
    logging: *default-logging
    cgroupns_mode: private
    cap_add:
      - CHOWN
      - SYS_TIME
      - SYS_ADMIN
    environment:
      TZ: ${TZ:-America/New_York}
      CONTAINER_NAME: casjaysdevdocker-forgejo-latest
      HOSTNAME: ${BASE_HOST_NAME:-git.example.com}
      FORGEJO_PROTO: http
      DATABASE_DIR_SQLITE: /data/db/sqlite
    volumes:
      - ./volumes/data:/data:z
      - ./volumes/config:/config:z
      - ./volumes/db/sqlite:/data/db/sqlite:z
    ports:
      - "172.17.0.1:80:80"
      - "172.17.0.1:22:22"
    networks:
      - forgejo

networks:
  forgejo:
    name: forgejo
    external: false
```

### Environment variables

**General**

| Variable | Default | Description |
|----------|---------|-------------|
| `TZ` | `America/New_York` | Timezone |
| `DEBUGGER` | _(empty)_ | Set to `on` to enable shell-level debug tracing |

**Server / domain**

| Variable | Default | Description |
|----------|---------|-------------|
| `FORGEJO_SERVER` | `hostname -f` | Public FQDN — sets ROOT\_URL, DOMAIN, SSH\_DOMAIN, and all email addresses. **Always set this in production.** |
| `FORGEJO_HOSTNAME` | _(empty)_ | Alias for `FORGEJO_SERVER` |
| `FULL_DOMAIN_NAME` | _(empty)_ | Fallback FQDN used when neither `FORGEJO_SERVER` nor `FORGEJO_HOSTNAME` is set |
| `DOMAIN` | _(empty)_ | Overrides the domain used in email addresses (takes precedence over `FORGEJO_SERVER`) |
| `FORGEJO_PROTO` | `http` | Protocol used in ROOT\_URL (`http` or `https`) |
| `FORGEJO_PORT` | `80` | Internal port Forgejo listens on |
| `FORGEJO_NAME` | `SelfHosted GIT Server` | Site title shown in the UI |
| `FORGEJO_TZ` | `$TZ` | Override timezone for Forgejo specifically |
| `FORGEJO_WORK_DIR` | `/data/forgejo` | Override Forgejo's work path |

**Users**

| Variable | Default | Description |
|----------|---------|-------------|
| `FORGEJO_ROOT_USER_NAME` | _(empty)_ | Initial admin account username (created on first run) |
| `FORGEJO_ROOT_PASS_WORD` | _(empty)_ | Initial admin account password |
| `FORGEJO_USER_NAME` | _(empty)_ | Initial normal user username |
| `FORGEJO_USER_PASS_WORD` | _(empty)_ | Initial normal user password |

**Mail**

| Variable | Default | Description |
|----------|---------|-------------|
| `FORGEJO_ADMIN` | `administrator@<FORGEJO_SERVER>` | Admin contact / mailer FROM address |
| `FORGEJO_EMAIL_RELAY` | `172.17.0.1` | SMTP relay host |
| `FORGEJO_EMAIL_CONFIRM` | `false` | Set to `yes` to require email confirmation and enable the mailer |

**Database**

| Variable | Default | Description |
|----------|---------|-------------|
| `FORGEJO_SQL_TYPE` | `sqlite3` | Database type (`sqlite3`, `mysql`, `postgres`) |
| `FORGEJO_SQL_HOST` | `localhost` | Database host (external DB only) |
| `FORGEJO_SQL_DB_HOST` | `$FORGEJO_SQL_HOST` | Alternate database host variable |
| `FORGEJO_SQL_USER` | _(empty)_ | Database user (external DB only) |
| `FORGEJO_SQL_PASS` | _(empty)_ | Database password (external DB only) |
| `FORGEJO_SQL_NAME` | _(empty)_ | Database name (external DB only) |
| `DATABASE_DIR_SQLITE` | `$DATA_DIR/db/sqlite` | Override the SQLite database directory (mount a separate volume here to keep the DB outside `/data`) |

**act\_runner**

| Variable | Default | Description |
|----------|---------|-------------|
| `RUNNERS_START` | `5` | Number of act\_runner instances to register |
| `RUNNER_CACHE_PORT` | `44015` | Port for the act\_runner cache server |
| `RUNNER_IP_ADDRESS` | container IP | IP address act\_runner registers with Forgejo |
| `RUNNER_DEFAULT_HOME` | `/config/act_runner/forgejo` | Directory where runner registration state is stored |
| `RUNNER_CONFIG_NAME` | `act_runner.yaml` | Runner config filename inside `RUNNER_DEFAULT_HOME` |
| `ACT_RUNNER_FALLBACK_VERSION` | `v13.1.0` | Pinned act\_runner version used if code.forgejo.org is unreachable during build |

**Runner labels** are set automatically based on the host architecture. All jobs run inside Docker containers — no bare-metal execution.

| Host arch | Labels registered |
|-----------|------------------|
| `x86_64` | `amd64:docker://ubuntu:latest`, `linux:docker://ubuntu:latest`, `linux/amd64:docker://ubuntu:latest`, + language images |
| `aarch64` | `arm64:docker://ubuntu:latest`, `linux:docker://ubuntu:latest`, `linux/arm64:docker://ubuntu:latest`, + language images |

Language image labels available on both architectures: `node` (14/16/18/20/22/latest), `perl`, `ruby`, `python`/`python3`, `php`/`php7`/`php8`, `alpine`, `debian`, `ubuntu`, `almalinux`/`rhel`/`redhat`, `ubuntu-latest`.

### Volumes

| Path | Purpose |
|------|---------|
| `/data` | Repositories, SQLite database, LFS objects, attachments, indexes |
| `/config` | `app.ini`, SSH host keys, act\_runner config — persisted across container restarts |

### Ports

| Port | Protocol | Purpose |
|------|----------|---------|
| `80` | TCP | Forgejo web UI and API |
| `22` (internal) / `7833` (default external) | TCP | Git over SSH — host port 22 is typically taken by sshd; map container port 22 to an available host port and set `SSH_PORT` to match |

### Notes

- **`--privileged` is required** for Docker-in-Docker (act\_runner runs CI jobs inside containers).
- The container ships its own `/etc/resolv.conf` (Cloudflare + Google DNS, no search domain) so DNS resolution inside the container is not affected by the host's search domain configuration.
- `FORGEJO_SERVER` **must be set** for a production deployment — without it, `ROOT_URL`, SSH clone URLs, and all system email addresses fall back to the container's short hostname.
- The mailer is **disabled by default**. Set `FORGEJO_EMAIL_CONFIRM=yes` to enable it along with the SMTP relay.
- SQLite is the default database. For external MySQL/Postgres set `FORGEJO_SQL_TYPE`, `FORGEJO_SQL_HOST`, `FORGEJO_SQL_USER`, `FORGEJO_SQL_PASS`, and `FORGEJO_SQL_NAME`.

---

## 🏃 Adding external runners

External runners let you add dedicated hardware (e.g. a native ARM64 server) to your Forgejo Actions pool without running the full container. Each runner registers directly against your Forgejo instance and declares its own labels, so matrix workflows can target it by architecture.

### 1 — Get a registration token

In the Forgejo web UI: **Site Administration → Runners → Create Runner Token**

Or via API:

```shell
curl -s -X POST https://git.example.com/api/v1/user/actions/runners/registration-token \
  -H "Authorization: token <your-api-token>"
```

### 2 — Install the act_runner binary

```shell
# Detect arch
ARCH=$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/')
VER=v13.1.0

curl -LSsf "https://code.forgejo.org/forgejo/runner/releases/download/${VER}/forgejo-runner-${VER#v}-linux-${ARCH}" \
  -o /usr/local/bin/act_runner
chmod +x /usr/local/bin/act_runner
```

### 3 — Register against your Forgejo instance

```shell
act_runner register \
  --instance https://git.example.com \
  --token    <registration-token> \
  --name     "arm64-server" \
  --labels   "arm64:docker://ubuntu:latest,linux/arm64:docker://ubuntu:latest,alpine:docker://alpine:latest,debian:docker://debian:latest" \
  --no-interactive
```

Label format: `name:type:image` — all jobs run inside Docker containers, never directly on the host.
- `arm64:docker://ubuntu:latest` — dispatched to this runner, job runs in a native arm64 Ubuntu container
- `linux/arm64:docker://ubuntu:latest` — OCI-style label for the same runner
- Docker must be installed and running on the host machine

### 4 — Run as a systemd service

```ini
# /etc/systemd/system/act_runner.service
[Unit]
Description=Forgejo Actions Runner
After=network.target

[Service]
ExecStart=/usr/local/bin/act_runner daemon
WorkingDirectory=/var/lib/act_runner
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
```

```shell
mkdir -p /var/lib/act_runner
mv .runner /var/lib/act_runner/   # move registration file to working dir
systemctl daemon-reload
systemctl enable --now act_runner
```

### Matrix workflow example

Once both an amd64 and an arm64 runner are registered:

```yaml
jobs:
  build:
    strategy:
      matrix:
        arch: [amd64, arm64]
    runs-on: ${{ matrix.arch }}
    steps:
      - uses: actions/checkout@v4
      - run: uname -m   # confirms native arch
```

---

## 🛠️ Development

### Prerequisites

- Docker with `buildx`
- `bash`, `git`

### Build from source

```shell
git clone https://github.com/casjaysdevdocker/forgejo "$HOME/Projects/github/casjaysdevdocker/forgejo"
cd "$HOME/Projects/github/casjaysdevdocker/forgejo"
buildx
```

### Install via dockermgr

```shell
sudo bash -c "$(curl -q -LSsf https://github.com/systemmgr/installer/raw/main/install.sh)"
sudo systemmgr --config && sudo systemmgr install scripts
dockermgr update forgejo
```

---

## 📄 License

MIT — see [LICENSE.md](LICENSE.md)
