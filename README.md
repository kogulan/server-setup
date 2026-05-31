# Containerized Server Setup Guide

This repository installs a small self-hosting stack under `/opt/deploy` using Docker Compose. It is designed for Ubuntu 24.04 servers, including Oracle Cloud Infrastructure (OCI), and can be re-run safely when you need to repair or refresh the deployment.

## What gets installed

| Component | Purpose | Default internal container |
| --- | --- | --- |
| Nginx reverse proxy | Public web entry point for all web tools | `nginx-proxy` |
| PHP 8.3 web server | Hosts files from `/opt/deploy/data/web_root` | `php-webserver` |
| PostgreSQL 16 | Database for n8n, Activepieces, and Huginn | `postgres-db` |
| MariaDB LTS | Database for the PHP/web app | `mariadb-db` |
| Adminer | Browser-based database administration | `adminer` |
| n8n | Workflow automation | `n8n-automation` |
| Activepieces | Workflow automation | `activepieces-automation` |
| Huginn | Web monitoring/agent automation | `huginn-automation` |
| Redis | Queue/cache service for automation apps | `redis` |
| SFTP | Secure file uploads for web and storage files | `sftp-server` |

## Before you begin

### Server requirements

- Ubuntu 24.04 minimal or similar modern Ubuntu release.
- A user with `sudo` access.
- At least 1 GB RAM. Servers below 2 GB RAM automatically get a 4 GB swap file and stricter container memory limits.
- A public IP address.
- Optional but recommended: a domain name pointed to the server.

### Required ports

Open these ports in your cloud firewall/security list and on any external firewall:

| Port | Required for |
| --- | --- |
| `22/tcp` | SSH administration |
| `80/tcp` | HTTP and Let's Encrypt validation |
| `443/tcp` | HTTPS |
| `2222/tcp` | SFTP uploads |
| `8080/tcp` | Adminer, only when using port-based access |
| `5678/tcp` | n8n, only when using port-based access |
| `8081/tcp` | Activepieces, only when using port-based access |
| `3000/tcp` | Huginn, only when using port-based access |

The installer opens these ports in the instance firewall. On OCI you must also allow the same inbound TCP ports in the VCN security list or network security group attached to the instance; otherwise external clients can time out even when Docker and UFW are configured correctly. This stack uses SFTP on TCP `2222`; it does not use FTP port `21` or passive FTP ports such as `30000-30009`.

The setup script also configures UFW and inserts local iptables allow rules, but cloud firewall rules must still be configured in your provider console.

### DNS options

Choose one access style before installation:

1. **Subdomains**: recommended for a real domain.
   - `yourdomain.com` → web site
   - `db.yourdomain.com` → Adminer
   - `n8n.yourdomain.com` → n8n
   - `ap.yourdomain.com` → Activepieces
   - `huginn.yourdomain.com` → Huginn
2. **Ports**: useful for IP-only setups or quick tests.
   - `http(s)://SERVER:8080` → Adminer
   - `http(s)://SERVER:5678` → n8n
   - `http(s)://SERVER:8081` → Activepieces
   - `http(s)://SERVER:3000` → Huginn

For Let's Encrypt, DNS records must already point to the server and port `80/tcp` must be reachable from the internet.

## Fresh installation

### 1. Copy the project to the server

Use Git, SCP, or your preferred deployment method. The final deployment directory should be `/opt/deploy`.

```bash
sudo mkdir -p /opt/deploy
sudo chown "$USER:$USER" /opt/deploy
git clone <your-repository-url> /opt/deploy
```

If you cloned somewhere else, that is also supported. Running `setup.sh` from another checkout synchronizes the deployment files into `/opt/deploy` automatically.

### 2. Run the installer

```bash
cd /opt/deploy
sudo chmod +x setup.sh scripts/*.sh
sudo ./setup.sh
```

The script asks for:

- Main domain or server IP.
- Admin email for certificate notifications.
- Access mode: subdomains or ports.
- SSL mode: Let's Encrypt, self-signed, or HTTP-only.

### 3. Wait for completion

The script performs these phases:

1. Creates `/opt/deploy` directories.
2. Loads or creates `/opt/deploy/.env`.
3. Installs Docker, Compose plugin, Certbot, UFW, cron, and helper packages.
4. Generates persistent passwords.
5. Writes service `.env` files.
6. Configures Nginx templates and SSL certificates.
7. Starts databases and verifies real database login.
8. Creates application databases and users.
9. Starts web, automation, storage, and proxy containers.
10. Writes `/opt/deploy/credentials.txt`.
11. Installs a weekly backup cron job.

### 4. Save credentials immediately

After a successful run, read and save the credential file:

```bash
sudo cat /opt/deploy/credentials.txt
```

The file is permission-restricted and contains database, SFTP, and Huginn invitation credentials.

## Re-running or repairing setup

The installer is intended to be re-runnable:

```bash
cd /opt/deploy
sudo ./setup.sh
```

It preserves existing generated secrets from the service `.env` files and reuses existing Docker data directories.

### Fix for `ERROR 1045 (28000): Access denied for user 'root'@'localhost'`

This error usually means MariaDB already had a data directory initialized with a different root password than the one in `/opt/deploy/db/.env`. The setup script now verifies an actual MariaDB login instead of only checking that the server process is alive. It also tries common recoverable passwords, including the current generated password, the container environment password, and the old default `password`. When one of those works, the script synchronizes MariaDB back to the generated password in `/opt/deploy/db/.env` and continues.

If the error still appears, the old MariaDB root password is unknown. Choose one of these paths:

#### Fresh install / no data to keep

This resets only MariaDB data. PostgreSQL and uploaded files are not removed by these commands.

```bash
cd /opt/deploy/db
sudo docker compose down
sudo mv /opt/deploy/data/mariadb "/opt/deploy/data/mariadb.bak.$(date +%Y%m%d%H%M%S)"
sudo mkdir -p /opt/deploy/data/mariadb
cd /opt/deploy
sudo ./setup.sh
```

#### Existing server / data must be kept

Do not delete `/opt/deploy/data/mariadb`. Find the previous MariaDB root password from an older `/opt/deploy/db/.env`, backup, password manager, or deployment notes. After you can log in, update `/opt/deploy/db/.env` to match or manually reset the MariaDB root password, then re-run:

```bash
cd /opt/deploy
sudo ./setup.sh
```

## Accessing services after installation

### Subdomain mode

| Service | URL |
| --- | --- |
| Website | `https://yourdomain.com` |
| Adminer | `https://db.yourdomain.com` |
| n8n | `https://n8n.yourdomain.com` |
| Activepieces | `https://ap.yourdomain.com` |
| Huginn | `https://huginn.yourdomain.com` |

### Port mode

| Service | URL |
| --- | --- |
| Website | `https://yourdomain.com` or `https://SERVER_IP` |
| Adminer | `https://yourdomain.com:8080` or `https://SERVER_IP:8080` |
| n8n | `https://yourdomain.com:5678` or `https://SERVER_IP:5678` |
| Activepieces | `https://yourdomain.com:8081` or `https://SERVER_IP:8081` |
| Huginn | `https://yourdomain.com:3000` or `https://SERVER_IP:3000` |

If you selected HTTP-only, replace `https://` with `http://`. The landing page reads the installer-selected access mode from `/opt/deploy/webserver/.env`, so after switching between subdomain and port mode, re-run `sudo ./setup.sh` to refresh the page links and restart the PHP container.

## Troubleshooting 502 responses and SFTP timeouts

After changing configuration, restart the stack from `/opt/deploy`:

```bash
sudo ./setup.sh
```

If n8n, Activepieces, or Huginn still returns `502 Bad Gateway`, check whether the upstream containers are running and healthy:

```bash
sudo docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'
sudo docker logs --tail=100 n8n-automation
sudo docker logs --tail=100 activepieces-automation
sudo docker logs --tail=100 huginn-automation
sudo docker logs --tail=100 nginx-proxy
```

For SFTP timeouts, verify both the container and network path:

```bash
sudo docker ps --filter name=sftp-server
sudo ss -ltnp | grep ':2222'
sftp -P 2222 webuser@localhost
```

If local SFTP works but FileZilla from your computer times out, open TCP port `2222` in the OCI VCN security list or network security group for the instance. Opening FTP port `21` and passive FTP ranges does not open this SFTP service; FileZilla must use protocol `SFTP - SSH File Transfer Protocol`, host `yourdomain.com`, port `2222`, and the `webuser` or `filesuser` credentials.

## Adminer database login guide

Open Adminer and use these server names:

### MariaDB web database

- System: `MySQL` or `MariaDB`
- Server: `mariadb-db`
- Username: `web_app_user`
- Password: value shown for `Web App DB` in `/opt/deploy/credentials.txt`
- Database: `web_app_db`

### PostgreSQL automation databases

- System: `PostgreSQL`
- Server: `postgres-db`
- Username: `admin`
- Password: value shown for `PostgreSQL Admin` in `/opt/deploy/credentials.txt`
- Database: `n8n`, `activepieces`, or `huginn`

## Uploading files with SFTP

SFTP runs on port `2222`. In FileZilla, choose `SFTP - SSH File Transfer Protocol`; do not choose plain FTP/FTPS, because this deployment does not run an FTP server on port `21`.

### Website files

Use the `webuser` credentials from `/opt/deploy/credentials.txt`:

```bash
sftp -P 2222 webuser@yourdomain.com
```

Files uploaded to `web_root` appear in:

```text
/opt/deploy/data/web_root
```

### General storage files

Use the `filesuser` credentials from `/opt/deploy/credentials.txt`:

```bash
sftp -P 2222 filesuser@yourdomain.com
```

Files uploaded to `my_ftp_files` appear in:

```text
/opt/deploy/data/ftp_storage
```

## Daily operations

### Check running containers

```bash
sudo docker ps
```

### View logs

```bash
sudo docker logs nginx-proxy --tail=100
sudo docker logs mariadb-db --tail=100
sudo docker logs postgres-db --tail=100
sudo docker logs n8n-automation --tail=100
sudo docker logs activepieces-automation --tail=100
sudo docker logs huginn-automation --tail=100
```

### Restart one service

```bash
sudo docker restart nginx-proxy
sudo docker restart mariadb-db
sudo docker restart postgres-db
```

### Restart one compose group

```bash
cd /opt/deploy/proxy && sudo docker compose up -d
cd /opt/deploy/db && sudo docker compose up -d
cd /opt/deploy/automation && sudo docker compose up -d
cd /opt/deploy/webserver && sudo docker compose up -d --build
cd /opt/deploy/storage && sudo docker compose up -d
```

### Stop the stack

```bash
cd /opt/deploy/proxy && sudo docker compose down
cd /opt/deploy/storage && sudo docker compose down
cd /opt/deploy/automation && sudo docker compose down
cd /opt/deploy/webserver && sudo docker compose down
cd /opt/deploy/db && sudo docker compose down
```

### Start the stack again

```bash
sudo docker network create deploy-network || true
cd /opt/deploy/db && sudo docker compose up -d
cd /opt/deploy/webserver && sudo docker compose up -d --build
cd /opt/deploy/automation && sudo docker compose up -d
cd /opt/deploy/storage && sudo docker compose up -d
cd /opt/deploy/proxy && sudo docker compose up -d
```

## Backups

The installer adds this cron job:

```text
0 2 * * 0 /opt/deploy/scripts/backup.sh >> /opt/deploy/backups/backup.log 2>&1
```

Backups are written to `/opt/deploy/backups` and retained for 7 days by default.

Run a manual backup:

```bash
sudo /opt/deploy/scripts/backup.sh
```

Backup contents include:

- Full PostgreSQL dump.
- Full MariaDB dump.
- File archive of `/opt/deploy/data`, excluding raw database directories.

## Updating the deployment

1. Pull or copy the latest repository files.
2. Re-run setup.

```bash
cd /opt/deploy
git pull
sudo ./setup.sh
```

If your repository is not in `/opt/deploy`, run the updated `setup.sh` from the checkout. It copies the current service files into `/opt/deploy` before continuing.

## Important file locations

| Path | Purpose |
| --- | --- |
| `/opt/deploy/.env` | Main installer choices and SFTP passwords |
| `/opt/deploy/db/.env` | PostgreSQL and MariaDB root credentials used by Compose |
| `/opt/deploy/automation/.env` | n8n, Activepieces, and Huginn settings |
| `/opt/deploy/webserver/.env` | PHP/web database settings |
| `/opt/deploy/credentials.txt` | Human-readable generated credentials |
| `/opt/deploy/data/web_root` | Website files |
| `/opt/deploy/data/ftp_storage` | General SFTP storage |
| `/opt/deploy/data/postgres` | PostgreSQL persistent data |
| `/opt/deploy/data/mariadb` | MariaDB persistent data |
| `/opt/deploy/proxy/conf.d/default.conf` | Generated Nginx configuration |
| `/opt/deploy/proxy/certs` | Certificates used by Nginx |
| `/opt/deploy/backups` | Backup output |

## Troubleshooting checklist

### Website or tools do not load

1. Confirm containers are running:
   ```bash
   sudo docker ps
   ```
2. Confirm cloud firewall ports are open.
3. Confirm local firewall rules:
   ```bash
   sudo ufw status
   ```
4. Check Nginx logs:
   ```bash
   sudo docker logs nginx-proxy --tail=100
   ```
5. For subdomain mode, verify DNS records point to the server IP.

### Let's Encrypt fails

- Confirm `A` records point to the server.
- Confirm port `80/tcp` is open in the cloud firewall.
- Stop other host web servers if needed:
  ```bash
  sudo systemctl stop nginx apache2 2>/dev/null || true
  ```
- Re-run setup:
  ```bash
  cd /opt/deploy
  sudo ./setup.sh
  ```

### Database login fails

Check the generated password:

```bash
sudo cat /opt/deploy/credentials.txt
sudo cat /opt/deploy/db/.env
```

Verify MariaDB directly:

```bash
DB_ROOT_PASS=$(sudo awk -F= '/^MARIADB_ROOT_PASSWORD=/{print $2}' /opt/deploy/db/.env)
sudo docker exec -i mariadb-db mariadb -u root --password="$DB_ROOT_PASS" -e "SELECT 1;"
```

Verify PostgreSQL directly:

```bash
DB_ROOT_PASS=$(sudo awk -F= '/^POSTGRES_PASSWORD=/{print $2}' /opt/deploy/db/.env)
sudo docker exec -e PGPASSWORD="$DB_ROOT_PASS" postgres-db psql -U admin -c "SELECT 1;"
```

### Low-memory server becomes slow

The installer enables swap on servers under 2 GB RAM. You can inspect memory with:

```bash
free -h
sudo docker stats
```

If automation tools are still slow, use a larger VM or stop tools you do not need.

## Security notes

- Keep `/opt/deploy/credentials.txt` private.
- Prefer Let's Encrypt over self-signed certificates for public domains.
- Do not expose database ports directly to the internet; this stack keeps database containers on the private Docker network.
- Keep Ubuntu and Docker updated with regular system maintenance.
- Back up `/opt/deploy/credentials.txt`, service `.env` files, and `/opt/deploy/backups` to a safe off-server location.
