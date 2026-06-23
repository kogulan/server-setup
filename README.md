# 🚀 OCI One-Click Automation & Hosting Server

An optimized, production-ready orchestrator to transform a fresh Ubuntu 24.04 VM (specifically for Oracle Cloud Infrastructure) into a powerful self-hosted hub for automation, web development, and secure storage.

---

## 📑 Table of Contents
1. [Overview of Services](#-overview-of-services)
2. [Prerequisites & OCI Provisioning](#-prerequisites--oci-provisioning)
3. [OCI Network Configuration (Firewall)](#-oci-network-configuration-firewall)
4. [Cloning the Repository](#-cloning-the-repository)
5. [Installation & Setup](#-installation--setup)
6. [Usage Guide](#-usage-guide)
7. [Day 2 Operations (Updates & Backups)](#-day-2-operations-updates--backups)
8. [Troubleshooting & Debugging](#-troubleshooting--debugging)

---

## 🛠 Overview of Services

This setup deploys a curated stack of powerful open-source tools:

*   **n8n**: A fair-code workflow automation tool with over 400+ integrations. It allows you to build complex logic without writing code.
*   **Activepieces**: A modern, no-code automation alternative focused on ease of use and business workflows.
*   **Huginn**: A system for building agents that perform automated tasks for you online. They can read the web, watch for events, and take actions.
*   **Adminer**: A lightweight, single-file database management tool for PostgreSQL and MariaDB.
*   **PHP 8.3 Webserver**: A performance-tuned environment for hosting your own websites or custom scripts.
*   **SFTP Storage**: Secure file access and management via a dedicated container.

---

## 🏗 Prerequisites & OCI Provisioning

This repository is optimized for **Oracle Cloud Infrastructure (OCI)** but works on any VPS running Ubuntu 24.04.

### 1. Recommended OCI Instance Specs
*   **Operating System**: `Ubuntu 24.04` or `Ubuntu 24.04 Minimal`.
*   **Shape**:
    *   **Always Free Compatible**: `VM.Standard.A1.Flex` (ARM-based Ampere) with at least 6GB RAM (recommended).
    *   **Minimum**: Any shape with at least **1GB RAM**. (The script automatically configures 4GB Swap if RAM is below 2GB).
*   **Networking**: Assign a **Public IPv4 Address**.

### 2. DNS Requirements
Before starting, point your domain to your server's IP address:
*   **A Record**: Point your domain (e.g., `example.com`) to the server IP.
*   **CNAME Record**: Point `*` to your domain (e.g., `*.example.com`) to support subdomains like `n8n.example.com`.

---

## 🔒 OCI Network Configuration (Firewall)

OCI instances are protected by a Virtual Cloud Network (VCN) firewall. You **must** add Ingress Rules in the OCI Console (Networking > VCNs > Your VCN > Security Lists) to allow traffic:

| Stateless | Source | IP Protocol | Source Port Range | Destination Port Range | Description |
| :--- | :--- | :--- | :--- | :--- | :--- |
| No | 0.0.0.0/0 | TCP | All | 80, 443 | HTTP/HTTPS (Web Access) |
| No | 0.0.0.0/0 | TCP | All | 22 | SSH (Remote Access) |
| No | 0.0.0.0/0 | TCP | All | 2222 | SFTP (File Transfers) |
| No | 0.0.0.0/0 | TCP | All | 5678, 8081, 3000, 8080 | **Port Mode Only** (Service access) |

---

## 📥 Cloning the Repository

Connect to your VM via SSH and choose one of the following methods to clone the setup:

### Method A: HTTPS (Simplest)
```bash
git clone https://github.com/kogulan/server-setup.git deploy
cd deploy
```

### Method B: SSH (Recommended for Devs)
```bash
git clone git@github.com:kogulan/server-setup.git deploy
cd deploy
```

### Method C: Personal Access Token (PAT)
Required if the repository is private or for automated scripts.
```bash
git clone https://<YOUR_TOKEN>@github.com/kogulan/server-setup.git deploy
cd deploy
```

### Method D: GitHub CLI (`gh`)
```bash
gh repo clone kogulan/server-setup deploy
cd deploy
```

### Method E: ZIP Download (Not recommended for production)
> ⚠️ **Warning**: This method makes it harder to use the `update.sh` script later as it lacks Git history.
```bash
wget https://github.com/kogulan/server-setup/archive/refs/heads/main.zip
unzip main.zip -d deploy
cd deploy/server-setup-main
```

---

## 🚀 Installation & Setup

Once cloned, run the orchestrator script:

```bash
sudo chmod +x setup.sh
sudo ./setup.sh
```

### Setup Choices:
1.  **Domain/IP**: Enter your domain name (e.g., `myserver.com`).
2.  **Access Mode**:
    *   **Subdomains**: `n8n.myserver.com`, `ap.myserver.com`, etc. (Requires CNAME record).
    *   **Ports**: `myserver.com:5678`, `myserver.com:8081`, etc.
3.  **SSL Choice**:
    *   **Let's Encrypt**: Free, automatic HTTPS (Requires Port 80 open).
    *   **Self-Signed**: Encrypted but triggers browser warnings (Use for IP-based access).
    *   **None**: Plain HTTP (Insecure).

---

## 📖 Usage Guide

### Service Access Table
| Service | Subdomain Mode | Port Mode | Default Host (Internal) |
| :--- | :--- | :--- | :--- |
| **Main Website** | `https://yourdomain.com` | `https://yourdomain.com` | - |
| **n8n** | `https://n8n.yourdomain.com` | `https://yourdomain.com:5678` | `n8n` |
| **Activepieces** | `https://ap.yourdomain.com` | `https://yourdomain.com:8081` | `activepieces` |
| **Huginn** | `https://huginn.yourdomain.com` | `https://yourdomain.com:3000` | `huginn` |
| **Adminer** | `https://db.yourdomain.com` | `https://yourdomain.com:8080` | `adminer` |

### File Management (SFTP)
Connect using **FileZilla** or WinSCP:
*   **Host**: Your Domain or IP
*   **Port**: `2222`
*   **Users**:
    *   `webuser`: Manages files in `/web_root` (Your website).
    *   `filesuser`: General secure storage.

### Database Management
Login to **Adminer** using the credentials provided at the end of setup.
*   To manage the Website DB: Use System `MySQL`, Server `mariadb-db`.
*   To manage Automation DBs: Use System `PostgreSQL`, Server `postgres-db`.

---

## 🔄 Day 2 Operations (Updates & Backups)

### 1. Update Everything
Run the update script to backup data, update the OS, and pull the latest Docker images:
```bash
cd /opt/deploy
sudo ./update.sh
```

### 2. Manual Backups
Backups are scheduled every Sunday at 2 AM, but you can trigger one manually:
```bash
sudo /opt/deploy/scripts/backup.sh
```
Files are stored in `/opt/deploy/backups/`.

### 3. Retrieve Credentials
If you forget your passwords, run:
```bash
sudo /opt/deploy/scripts/show_credentials.sh
```

---

## ❓ Troubleshooting & Debugging

### Common Issues
*   **Connection Lost (n8n)**: Often caused by incorrect `N8N_WEBHOOK_URL` in Port Mode. Check `/opt/deploy/automation/.env`.
*   **SSL Failure**: Ensure Port 80 is open and DNS is fully propagated. Check logs: `cat /var/log/letsencrypt/letsencrypt.log`.
*   **Timeout/Refused**: Check OCI Ingress Rules first, then check local firewall: `sudo ufw status`.

### Technical Debugging Commands
If a service is down, use these commands to find the cause:

**1. Check Container Logs:**
```bash
sudo docker logs n8n
sudo docker logs mariadb-db
```

**2. Check Service Status:**
```bash
sudo docker compose -f /opt/deploy/automation/docker-compose.yml ps
```

**3. Check Disk Space:**
```bash
df -h
```

**4. Monitor System Resources:**
```bash
htop  # (Install with sudo apt install htop)
```

**5. Check for Port Conflicts:**
```bash
sudo lsof -i :80
```

---

## 🛡️ Security Note
This setup implements basic hardening, including restricted directory permissions (`700`) and security headers. However, always ensure your VM is updated and avoid exposing database ports directly to the internet in OCI.

---
*Created with ❤️ for the OCI Community.*
