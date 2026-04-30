# DFIR-IRIS + Cortex — Universal Stack v2

> **Evergreen** · All versions configurable via `.env` · One script to upgrade

| Component | Default | Config key |
|---|---|---|
| **DFIR-IRIS** | `v2.4.27` | `IRIS_VERSION` |
| **Cortex** | `latest` (4.0.0) | `CORTEX_VERSION` |
| **Elasticsearch** | `8.13.0` | `ES_VERSION` |
| **iris-cortex-analyzer-module** | `1.0.0` | (rebuilt from source) |

> ⚠️ **Cortex 4.x requires Elasticsearch 8.x only.** ES 7.x is no longer supported.

---

## Supported Platforms

### Debian / Ubuntu

| Distro | Version | Codename | Status |
|---|---|---|---|
| Ubuntu | 22.04 LTS | jammy | ✅ Tested |
| Ubuntu | 24.04 LTS | noble | ✅ Tested |
| Ubuntu | 25.04 | plucky | ✅ Auto-fallback to noble Docker packages |
| Ubuntu | 26.04 LTS | questing | ✅ Auto-fallback to noble Docker packages |
| Debian | 11 / 12 | bullseye / bookworm | ✅ Tested |

### RPM / Enterprise Linux

| Distro | Version | Status |
|---|---|---|
| RHEL | 8, 9 | ✅ Supported |
| Rocky Linux | 8, 9 | ✅ Supported |
| AlmaLinux | 8, 9 | ✅ Supported |
| CentOS Stream | 8, 9 | ✅ Supported |
| Fedora | 39, 40, 41+ | ✅ Supported (rolling) |
| Amazon Linux | 2, 2023 | ✅ Supported |

---

## Prerequisites

| Requirement | Minimum |
|---|---|
| RAM | 16 GB recommended |
| Disk | 40 GB+ |
| Docker | 24.x+ (auto-installed by `setup.sh`) |
| Docker Compose | v2.x+ plugin (auto-installed) |
| Python | 3.9+ (for module build) |

---

## Architecture

```
┌──────────────────────────────────────────────────────────────┐
│              DFIR-IRIS (iris_backend network)                  │
│  nginx:443  →  app:8000  ↔  worker (celery)                  │
│                    │  iris_cortex_analyzer_module             │
└─────────────────┼───────────────────────────────────────────┘
                 │ cortex4py REST (http://cortex:9001)
┌───────────────┼───────────────────────────────────────────────┐
│               ▼        Cortex 4.0.0 (cortex_net)               │
│  cortex:9001  →  elasticsearch:9200 (8.x, xpack.security=off) │
└──────────────────────────────────────────────────────────────┘
```

---

## Quick Start (5 commands)

```bash
# 1. Clone
git clone https://github.com/Ramkumar2545/dfir-iris-cortex-v2.git
cd dfir-iris-cortex-v2

# 2. Setup (OS-aware: Debian + RPM — auto-installs Docker)
sudo bash scripts/setup.sh

# 3. Start full stack
docker compose up -d

# 4. Install IRIS-Cortex module
bash scripts/install_module.sh

# 5. Configure module in IRIS UI (see Step 7 below)
```

---

## Step-by-Step Guide

### Step 1 — Clone
```bash
git clone https://github.com/Ramkumar2545/dfir-iris-cortex-v2.git
cd dfir-iris-cortex-v2
```

---

### Step 2 — Setup (all OS)

```bash
sudo bash scripts/setup.sh
```

What happens (auto, OS-detected):

| # | Action | Debian/Ubuntu | RPM (RHEL/Rocky/Alma/Fedora) |
|---|---|---|---|
| 1 | Install system packages | `apt` | `dnf` / `yum` |
| 2 | Install Docker CE | docker.com apt repo | docker.com rpm repo |
| 3 | vm.max_map_count=262144 | `/etc/sysctl.conf` | `/etc/sysctl.conf` |
| 4 | Create runtime dirs | `cortex/`, `/tmp/cortex-jobs` | same |
| 5 | Generate TLS cert (10yr) | `openssl req -x509` | same |
| 6 | Auto-generate `.env` | `python3 secrets.token_hex` | same |
| 7 | Validate `.env` keys | fails if CHANGE_ME remains | same |
| 8 | Enable pgcrypto in DB | `pg_isready` + `psql` | same |

> **Ubuntu 25.04 / 26.04 note:** Docker CE apt packages are pulled from the `noble` (24.04)
> repo as a fallback if Docker hasn't published packages for the new codename yet.
> This is fully automatic.

---

### Step 3 — Start the stack

```bash
docker compose up -d
```

Wait ~90s for all services to become healthy:

```bash
docker compose ps
```

Expected:
```
NAME                   STATUS
iriswebapp_app         running (healthy)
iriswebapp_worker      running
iriswebapp_nginx       running
iriswebapp_rabbitmq    running
iriswebapp_db          running (healthy)
cortex                 running (healthy)
cortex_es              running (healthy)
```

---

### Step 4 — IRIS first login

1. Open: **https://\<SERVER-IP\>**
2. Accept self-signed cert warning
3. Login: `administrator` / `administrator`
4. **Change password immediately**

---

### Step 5 — Cortex first-time setup

1. Open: **http://\<SERVER-IP\>:9001**
2. Click **"Update & Migrate Database"**
3. Create an **Organisation** (e.g. `SOC`)
4. Create an **org admin user**; log in
5. Go to **Organisation → Analyzers** → enable what you need:
   - `VirusTotal_GetReport_3_1`, `AbuseIPDB_1_0`, `Shodan_Host_1_0`, etc.
6. Go to **Organisation → API Keys** → **Create API Key**
7. **Copy the key** (you need it for Step 7)
8. Edit `.env` → set `CORTEX_API_KEY=<paste-here>`

---

### Step 6 — Install iris-cortex module

```bash
bash scripts/install_module.sh
```

Expected:
```
[OK]   Verified in iriswebapp_app
[OK]   Verified in iriswebapp_worker
[OK]   Module installation complete!
```

---

### Step 7 — Register module in IRIS UI

1. **Advanced → Modules → Add Module**
2. Module name: `iris_cortex_analyzer_module`  → **Save**
3. Click **Configure**:

| Parameter | Value |
|---|---|
| `cortex_url` | `http://cortex:9001` |
| `cortex_api_key` | API key from Step 5 |
| `cortex_analyzers` | `VirusTotal_GetReport_3_1` (one per line) |
| `verify_ssl` | `false` |
| `manual_hook_enabled` | `true` |
| `report_as_attribute` | `true` |

4. **Save** → **Enable**

---

### Step 8 — Test

1. Open any **Case → IOC tab**
2. Add an IOC: type `ip`, value = any public IP
3. **Action dropdown → Run Cortex Analyzer**
4. Wait ~30s → click IOC → **Attributes tab**
5. See: **CORTEX: VirusTotal_GetReport_3_1** with full report

---

## Upgrading Components

Edit `.env` to change any version, then:

```bash
# Example: upgrade IRIS to v2.5.0 (when released)
sed -i 's/IRIS_VERSION=.*/IRIS_VERSION=v2.5.0/' .env
bash scripts/update.sh

# Or pass inline (doesn't persist):
IRIS_VERSION=v2.5.0 bash scripts/update.sh

# Upgrade Cortex to a specific tag:
CORTEX_VERSION=4.1.0 bash scripts/update.sh
```

`update.sh` will:
1. Validate ES version is still 8.x
2. Create a pre-upgrade backup
3. `docker compose pull`
4. `docker compose up -d --force-recreate`
5. Re-install the iris-cortex module

---

## Backup & Restore

```bash
# Backup (timestamped)
bash scripts/backup.sh

# Backup with custom tag
bash scripts/backup.sh --tag before-upgrade

# Restore from backup tag
bash scripts/backup.sh --restore 20260430-093000
```

Backups are saved to `./backups/<tag>/` and include:
- `iris_pg_dump.sql.gz` — full PostgreSQL dump
- `dfir-iris-cortex-v2_db_data.tar.gz` — raw PG volume
- `dfir-iris-cortex-v2_cortex_es_data.tar.gz` — ES data volume
- `manifest.txt` — version snapshot

---

## Supported IOC Types

| IRIS IOC Type | Cortex `dataType` |
|---|---|
| `ip`, `ip-src`, `ip-dst`, `ipv4`, `ipv6`, `ip-any` | `ip` |
| `domain`, `fqdn`, `hostname` | `domain` |
| `md5`, `sha1`, `sha256`, `sha512`, `ssdeep`, `tlsh`, `imphash` | `hash` |
| `url`, `uri`, `link` | `url` |
| `email`, `mail` | `mail` |
| `filename`, `filepath` | `filename` |
| `regkey`, `registry` | `registry` |
| `asn`, `as` | `autonomous-system` |
| `user-agent` | `user-agent` |
| `mac-address` | `mac-address` |
| `cve`, `vulnerability` | `other` |

---

## Troubleshooting

### Ubuntu 25.04/26.04 — Docker install fails
```bash
# setup.sh auto-falls back to noble packages — if that also fails:
curl -fsSL https://get.docker.com | sh
```

### RHEL/Rocky — permission denied on Docker socket
```bash
sudo usermod -aG docker $USER
newgrp docker
```

### Worker error: `encoding without a string argument`
`SECRET_KEY` not in worker environment:
```bash
docker compose down && docker compose up -d
```

### Module not found after install
```bash
bash scripts/install_module.sh
```

### Elasticsearch won't start
```bash
sudo sysctl -w vm.max_map_count=262144
docker compose restart elasticsearch
```

### General debug
```bash
docker compose ps
docker compose logs --tail=30
docker logs iriswebapp_worker --tail=50
docker logs cortex --tail=30
```

---

## File Structure

```
dfir-iris-cortex-v2/
├── docker-compose.yml            ← All versions from .env
├── .env.example                  ← Copy → .env, fill CHANGE_ME
├── scripts/
│   ├── detect_os.sh              ← OS family + pkg manager detection
│   ├── install_docker.sh         ← Docker CE for Debian + RPM
│   ├── setup.sh                  ← Full first-time setup (OS-aware)
│   ├── install_module.sh         ← Build + install iris_cortex module
│   ├── update.sh                 ← Pull new versions + recreate
│   ├── backup.sh                 ← Backup / restore volumes
│   └── init-extensions.sql       ← pgcrypto auto-init
├── cortex/{config,logs,neurons}/  ← Cortex runtime (git-tracked)
├── certificates/                 ← TLS certs (generated by setup.sh)
└── iris_module/                  ← iris_cortex_analyzer_module source
    └── iris_cortex_analyzer_module/
        ├── __init__.py
        ├── IrisCortexAnalyzerConfig.py
        ├── IrisCortexAnalyzerInterface.py
        └── cortex_handler/cortex_handler.py
```

---

## Author

Ram Kumar G — Chennai, Tamil Nadu
