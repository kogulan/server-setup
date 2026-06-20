# 🚀 OCI One-Click Automation & Hosting Server

Welcome to your all-in-one automation and web hosting powerhouse! This repository turns a fresh **Ubuntu 24.04** server (optimized for Oracle Cloud Infrastructure) into a fully functional hub for automation, web development, and secure file storage in minutes.

---

## 🏗️ What's Inside?

*   **n8n**: Powerful workflow automation.
*   **Activepieces**: No-code automation alternative.
*   **Huginn**: Personal agents for web monitoring.
*   **Adminer**: Lightweight database management (MariaDB & PostgreSQL).
*   **PHP 8.3 Webserver**: Ready for your website or custom scripts.
*   **SFTP Access**: Secure file management on port 2222.
*   **Automatic SSL**: Secured by Let's Encrypt (HTTPS).

---

## 📋 Prerequisites

### 1. Server Requirements
*   **OS**: Ubuntu 24.04 (Minimal recommended).
*   **Provider**: Optimized for **Oracle Cloud (OCI)**, but works on any VPS.
*   **RAM**: Minimum 1GB. (The script automatically adds 4GB Swap if RAM < 2GB).

### 2. DNS Setup (Do this first!)
Point your domain to your server's IP address:
*   **A Record**: Point `@` (or your domain) to your server's IP.
*   **CNAME Record**: (Optional but recommended) Point `*` to your domain to allow subdomains like `n8n.yourdomain.com`.

### 3. OCI Firewall (Security List)
Open these ports in your OCI Dashboard (Ingress Rules):
*   **TCP 80 & 443**: Standard Web/SSL.
*   **TCP 2222**: SFTP Access.
*   **TCP 5678, 8081, 3000, 8080**: (Required if using **Port Mode**).

---

## 🛠️ Step 1: Installation

Connect to your server via SSH and follow these steps.

### 1. Clone the Repository
Choose one of the methods below:

**Standard Clone:**
```bash
git clone https://github.com/your-username/your-repo-name.git deploy
cd deploy
```

**Clone with Personal Access Token (For Private Repos):**
```bash
git clone https://<YOUR_TOKEN>@github.com/your-username/your-repo-name.git deploy
cd deploy
```

### 2. Run the Setup
```bash
sudo chmod +x setup.sh
sudo ./setup.sh
```

**During Setup:**
*   Enter your **Domain** and **Email**.
*   Choose **Subdomains** (`n8n.domain.com`) or **Ports** (`domain.com:5678`).
*   **IMPORTANT**: Save the credentials displayed at the end! They are also saved in `/opt/deploy/credentials.txt`.

---

## 📖 Step 2: Usage Guide

### 🚀 Accessing Your Services
| Service | Subdomain Mode | Port Mode | Tips |
| :--- | :--- | :--- | :--- |
| **n8n** | `https://n8n.yourdomain.com` | `https://yourdomain.com:5678` | First visitor becomes Admin. |
| **Activepieces** | `https://ap.yourdomain.com` | `https://yourdomain.com:8081` | First visitor becomes Admin. |
| **Huginn** | `https://huginn.yourdomain.com` | `https://yourdomain.com:3000` | Requires Invitation Code from `credentials.txt`. |
| **Adminer** | `https://db.yourdomain.com` | `https://yourdomain.com:8080` | Use `postgres-db` or `mariadb-db` as host. |
| **Website** | `https://yourdomain.com` | `https://yourdomain.com` | Managed via SFTP. |

### 📁 File Management (SFTP)
Use **FileZilla** to manage your website files and general storage.

1.  **Protocol**: `SFTP - SSH File Transfer Protocol`.
2.  **Host**: Your Domain or IP.
3.  **Port**: `2222`.
4.  **Logon Type**: `Normal`.
5.  **Users**:
    - `webuser`: For website files (located in `/web_root`).
    - `filesuser`: For general storage.
6.  **Password**: Find these in `/opt/deploy/credentials.txt`.

### 🌐 Website File Management
Your website's files are served from `/opt/deploy/data/web_root/`.
- Upload your `index.php` or `index.html` here using the `webuser` SFTP account.
- The webserver supports PHP 8.3 and is connected to MariaDB and PostgreSQL.

---

## 🔄 Step 3: Update & Upgrade

To keep your server secure and your tools up to date, run the one-click update script:

```bash
cd /opt/deploy
sudo ./update.sh
```

**What this script does:**
1.  **Backs up** all your data (DBs and Files).
2.  **Updates** the Ubuntu OS packages.
3.  **Pulls** the latest Docker images for all services.
4.  **Restarts** services safely to apply updates.
5.  **Reminds** you if a system reboot is needed.

---

## 💾 Step 4: Backup & Restore

### How Backups Work
- **Automatic**: Runs every Sunday at 2:00 AM via Cron.
- **Manual**: Run `sudo /opt/deploy/scripts/backup.sh`.
- **Contents**: Full SQL dumps of MariaDB & Postgres, plus a compressed archive of all files.
- **Location**: `/opt/deploy/backups/`.

### How to Restore
Replace `YYYY-MM-DD` with your backup date.

#### 1. Restore MariaDB (Web App DB)
```bash
gunzip /opt/deploy/backups/mariadb_full_YYYY-MM-DD.sql.gz
sudo docker exec -i mariadb-db sh -c 'export MYSQL_PWD="$MARIADB_ROOT_PASSWORD"; mariadb -u root' < /opt/deploy/backups/mariadb_full_YYYY-MM-DD.sql
```

#### 2. Restore PostgreSQL (n8n/AP/Huginn)
```bash
gunzip /opt/deploy/backups/postgres_full_YYYY-MM-DD.sql.gz
sudo docker exec -i postgres-db sh -c 'export PGPASSWORD="$POSTGRES_PASSWORD"; psql -U admin postgres' < /opt/deploy/backups/postgres_full_YYYY-MM-DD.sql
```

#### 3. Restore Files
```bash
sudo tar -xzf /opt/deploy/backups/files_YYYY-MM-DD.tar.gz -C /opt/deploy/data/
```

---

## ❓ Troubleshooting

### 1. "Connection Lost" error in n8n
If you see "Connection Lost" or "Lost connection to server" in n8n:
- **Check `.env`**: Ensure `N8N_WEBHOOK_URL` in `/opt/deploy/automation/.env` includes your port (if in Port Mode).
- **Check Docker**: Ensure `N8N_EDITOR_BASE_URL` and `N8N_ALLOWED_ORIGINS` match your access URL.
- **Nginx**: Ensure WebSocket support is enabled in your Nginx config (the setup script handles this by default).

### 2. Can't access services (Timeout)
- **Firewall**: Check your OCI Ingress Rules and `sudo ufw status`.
- **DNS**: Ensure your domain points to the correct IP (`ping yourdomain.com`).

### 3. SSL (HTTPS) is not working
- Ensure port 80 is open and not used by another service.
- Re-run SSL setup: `sudo /opt/deploy/scripts/ssl_setup.sh letsencrypt yourdomain.com your@email.com 1`.

### 4. Forgot Passwords
Run this to see all credentials:
```bash
sudo cat /opt/deploy/credentials.txt
```

---

## 🛡️ Security Note
Keep your system updated regularly using `./update.sh`. Never share your `credentials.txt` file. For OCI users, always use the dedicated SFTP port (2222) for file transfers.
