# 🚀 OCI One-Click Automation Server

Welcome to your all-in-one automation and web hosting powerhouse! This repository contains a set of scripts and configurations designed to turn a fresh **Ubuntu 24.04** server (optimized for Oracle Cloud Infrastructure) into a fully functional automation hub in minutes.

Whether you're a developer or a complete beginner, this guide will help you set up and manage your own server with ease.

---

## 🏗️ What's Inside?

When you run this setup, your server will be equipped with:

*   **n8n**: A powerful workflow automation tool to connect your favorite apps.
*   **Activepieces**: A user-friendly, no-code alternative for automation.
*   **Huginn**: Your personal "agents" that monitor the web and take actions for you.
*   **Adminer**: A lightweight tool to manage your MariaDB and PostgreSQL databases.
*   **PHP 8.3 Webserver**: Ready to host your own website or custom scripts.
*   **SFTP Access**: Securely upload and download files using a familiar interface.
*   **Automatic SSL**: Secured by Let's Encrypt so your tools are always safe (HTTPS).

### High-Level Architecture
```text
                          ┌────────────────────────┐
                          │      Your Domain       │
                          └───────────┬────────────┘
                                      │
                         HTTPS (443)  ▼  HTTP (80)
                    ┌──────────────────────────────────┐
                    │       Nginx Reverse Proxy        │
                    └─────────────────┬────────────────┘
                                      │
            ┌─────────────────────────┼─────────────────────────┐
            │                         │                         │
    ┌───────▼───────┐         ┌───────▼───────┐         ┌───────▼───────┐
    │  n8n (Auto)   │         │ Activepieces  │         │ Huginn (Agents)│
    └───────┬───────┘         └───────┬───────┘         └───────┬───────┘
            │                         │                         │
            └───────────┐             │             ┌───────────┘
                        ▼             ▼             ▼
                ┌───────────────────────────────────────────┐
                │        Shared Databases (Postgres)        │
                └───────────────────────────────────────────┘
```

---

## 📋 Prerequisites

### 1. The Server
*   **OS**: Ubuntu 24.04 (Minimal is fine).
*   **Provider**: Highly optimized for **Oracle Cloud Infrastructure (OCI)**, but works on any Ubuntu VPS.
*   **RAM**: Minimum 1GB. If your server has less than 2GB, the script will automatically enable **Swap Memory** to keep things stable.

### 2. OCI Dashboard Settings (Very Important!)
If you are using Oracle Cloud, you **must** open the following ports in your "Ingress Rules" (Virtual Cloud Network):
*   **TCP 80**: For web traffic and SSL setup.
*   **TCP 443**: For secure web traffic.
*   **TCP 2222**: For SFTP access.
*   **TCP 5678, 8081, 3000, 8080**: (Only if you choose "Port Mode" during setup).

---

## 🌐 Step 1: DNS Setup

Before running the script, you need to point your domain to your server's IP address.

1.  Go to your Domain Provider (e.g., Namecheap, Cloudflare, GoDaddy).
2.  Create an **A Record** pointing `@` to your server's IP.
3.  If you want to use **Subdomains** (recommended), create a **CNAME Record** with `*` pointing to your domain (or create individual A records for `n8n`, `ap`, `huginn`, `db`, and `ftp`).

---

## 🛠️ Step 2: Installation

Connect to your server via SSH and run these commands:

```bash
# 1. Update your system
sudo apt update && sudo apt upgrade -y

# 2. Clone this repository
git clone https://github.com/your-repo/deploy-scripts.git deploy
cd deploy

# 3. Run the setup script
sudo chmod +x setup.sh
sudo ./setup.sh
```

### What happens during setup?
*   The script will ask for your **Domain** and **Email**.
*   It will ask if you want **Subdomains** (e.g., `n8n.yourdomain.com`) or **Ports** (e.g., `yourdomain.com:5678`).
*   It will automatically generate strong passwords for everything.
*   **Important**: At the end, it will display a list of credentials. **Copy and save these immediately!** They are also stored in `/opt/deploy/credentials.txt`.

---

## 📂 Step 3: Managing Files (SFTP)

We have set up a dedicated SFTP server on **port 2222**. This is much safer than using the standard SSH port.

### How to connect with FileZilla:
1.  Open **FileZilla**.
2.  Go to **File > Site Manager**.
3.  Click **New Site** and name it (e.g., "My Automation Server").
4.  **Protocol**: Select `SFTP - SSH File Transfer Protocol`.
5.  **Host**: Your domain or IP address.
6.  **Port**: `2222`.
7.  **Logon Type**: `Normal`.
8.  **User**: `webuser` (for your website files) or `filesuser` (for general storage).
9.  **Password**: Find this in your `credentials.txt`.
10. Click **Connect**.

---

## 💾 Step 4: Backups & Restoration

The system automatically backs up your databases and files every **Sunday at 2:00 AM**.

*   **Location**: `/opt/deploy/backups/`
*   **Retention**: Backups older than 7 days are automatically deleted.

### How to Restore a Backup:

#### To restore MariaDB (Web App DB):
```bash
# Unzip your backup file
gunzip /opt/deploy/backups/mariadb_full_YYYY-MM-DD.sql.gz

# Restore the data
sudo docker exec -i mariadb-db mariadb -u root -pYOUR_ROOT_PASSWORD < /opt/deploy/backups/mariadb_full_YYYY-MM-DD.sql
```

#### To restore PostgreSQL (n8n/AP/Huginn):
```bash
# Unzip your backup file
gunzip /opt/deploy/backups/postgres_full_YYYY-MM-DD.sql.gz

# Restore the data
cat /opt/deploy/backups/postgres_full_YYYY-MM-DD.sql | sudo docker exec -i -e PGPASSWORD=YOUR_ROOT_PASSWORD postgres-db psql -U admin postgres
```

#### To restore Files:
```bash
sudo tar -xzf /opt/deploy/backups/files_YYYY-MM-DD.tar.gz -C /opt/deploy/data/
```

---

## ❓ Troubleshooting

### 1. I can't access the website/tools!
*   **Check OCI Firewall**: Did you open the ports in the Oracle Cloud Dashboard?
*   **Check UFW**: Run `sudo ufw status` to see if the server's internal firewall is allowing traffic.
*   **Check Containers**: Run `cd /opt/deploy/proxy && sudo docker compose ps` to see if the services are running.

### 2. SSL (HTTPS) is not working.
*   Make sure your domain is correctly pointed to your server IP.
*   Ensure port 80 is not being used by another service before running the setup.
*   You can try running the SSL setup again: `sudo /opt/deploy/scripts/ssl_setup.sh letsencrypt yourdomain.com your@email.com 1`.

### 3. My server is slow or lagging.
*   If you have 1GB of RAM, n8n and Huginn can be heavy. The script adds a swapfile, but consider upgrading to a 2GB or 4GB "Ampere" instance on OCI for the best experience.

### 4. Where are my passwords?
*   Type `sudo cat /opt/deploy/credentials.txt` to see all your generated passwords.

---

## 🛡️ Security Note
This setup uses a shared Docker network and firewall rules to keep services isolated. However, always keep your Ubuntu system updated (`sudo apt update && sudo apt upgrade`) and never share your `credentials.txt` file.

Enjoy your new automated world! 🤖