# n8n Troubleshoot Guide — OCI Docker Setup

## Problem
Browser open `https://kvmautosrv.ddns.net:5678` → n8n reject connection → show **"Connection lost"** top right → workflow fail with **"Lost connection to server"**

**Root cause:** Browser send origin with `:5678` in header. n8n expect no port. Mismatch → reject.

---

## Fix 1 — Update `.env` File

**File:** `/opt/deploy/automation/.env`

Change this:
```
N8N_WEBHOOK_URL=https://kvmautosrv.ddns.net/
```
To this:
```
N8N_WEBHOOK_URL=https://kvmautosrv.ddns.net:5678/
```

---

## Fix 2 — Update `docker-compose.yml`

**File:** `/opt/deploy/automation/docker-compose.yml`

Add these lines under n8n `environment:` section:
```yaml
- N8N_EDITOR_BASE_URL=https://kvmautosrv.ddns.net:5678
- N8N_ALLOWED_ORIGINS=https://kvmautosrv.ddns.net:5678
```

Full n8n environment block look like this after fix:
```yaml
environment:
  - DB_TYPE=postgresdb
  - DB_POSTGRESDB_DATABASE=${N8N_DB:-n8n}
  - DB_POSTGRESDB_HOST=postgres-db
  - DB_POSTGRESDB_PORT=5432
  - DB_POSTGRESDB_USER=${N8N_DB_USER:-n8n_user}
  - DB_POSTGRESDB_PASSWORD=${N8N_DB_PASS:-n8n_pass}
  - N8N_PORT=5678
  - WEBHOOK_URL=${N8N_WEBHOOK_URL}
  - N8N_ENCRYPTION_KEY=${N8N_ENCRYPTION_KEY}
  - N8N_EDITOR_BASE_URL=https://kvmautosrv.ddns.net:5678
  - N8N_ALLOWED_ORIGINS=https://kvmautosrv.ddns.net:5678
```

---

## Fix 3 — Update Nginx Config

**File:** `/opt/deploy/proxy/conf.d/default.conf`

Find n8n server block. Replace location block with this:
```nginx
# n8n (Internal 5678 -> External 5678 SSL)
server {
    listen 5678 ssl;
    server_name kvmautosrv.ddns.net;
    ssl_certificate /etc/nginx/certs/fullchain.pem;
    ssl_certificate_key /etc/nginx/certs/privkey.pem;
    location / {
        proxy_pass http://n8n-automation:5678;
        proxy_set_header Host $server_name;
        proxy_set_header Origin https://kvmautosrv.ddns.net;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_read_timeout 86400;
    }
}
```

---

## Apply All Changes — Commands

```bash
# restart n8n
cd /opt/deploy/automation && sudo docker compose down n8n && sudo docker compose up -d n8n

# reload nginx (no restart needed)
sudo docker exec nginx-proxy nginx -s reload
```

---

## Verify Fix Working

```bash
# check n8n env loaded correct
sudo docker exec n8n-automation env | grep -E "N8N|WEBHOOK"

# check logs clean (no origin error)
sudo docker logs n8n-automation --tail 20
```

Expected env output:
```
WEBHOOK_URL=https://kvmautosrv.ddns.net:5678/
N8N_EDITOR_BASE_URL=https://kvmautosrv.ddns.net:5678
N8N_ALLOWED_ORIGINS=https://kvmautosrv.ddns.net:5678
```

---

## Workflow JSON Fixes

| Node | Problem | Fix |
|---|---|---|
| Cache Collections (node-2) | `$workflow.staticData` undefined | Use `$getWorkflowStaticData('global')` |
| Match Collection ID (node-8) | Same as above | Use `$getWorkflowStaticData('global')` |
| Skip Update? (node-9) | IF node broken — `rightType` undefined | Replaced with Code node branch logic |
| All HTTP nodes | Credential warning in n8n UI | Set `authentication: "none"`, keep token in header |

---

## Quick Debug Commands

```bash
# see all containers status
sudo docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

# check n8n logs
sudo docker logs n8n-automation --tail 50

# check RAM
free -h

# check n8n env vars
sudo docker exec n8n-automation env | grep -E "N8N|WEBHOOK"
```
