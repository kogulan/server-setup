# OCI Production-Ready Deployment Package

This package provides a complete, automated setup for deploying a suite of web services, automation tools, and FTP storage on Oracle Cloud Infrastructure (OCI) Ubuntu 24.04 Minimal VMs.

## 🏗 Architecture Overview

The solution uses a modular Docker Compose architecture:
- **Proxy**: Nginx handles incoming traffic, SSL termination, and routing.
- **Database**: Shared PostgreSQL (for automation) and MariaDB (for PHP web root) containers.
- **Web Server**: PHP 8.3-FPM with a blank environment.
- **Automation**: n8n, Activepieces, and Huginn sharing a tiny Redis instance.
- **Storage**: Pure-FTPd providing isolated access to the web root and a separate file folder.
- **Security**: UFW firewall on the host, Docker network isolation, and optional Let's Encrypt SSL.

## 📂 Folder Structure

```text
/opt/deploy/
├── setup.sh             # Main installation and configuration script
├── proxy/               # Nginx configuration and Compose file
├── db/                  # PostgreSQL, MariaDB, and Adminer
├── webserver/           # PHP-FPM service
├── automation/          # n8n, Activepieces, Huginn, Redis
├── storage/             # Pure-FTPd service
├── data/                # Persistent volumes for all services
│   ├── web_root/        # Web server files (linked to FTP)
│   └── ftp_storage/     # General FTP files (no web access)
├── backups/             # Automated weekly backups
├── scripts/             # Utility scripts (SSL, Backup)
└── templates/           # Configuration templates
```

## 🚀 Installation

1. **Prerequisites**: A fresh OCI Ubuntu 24.04 Minimal VM (x86_64 or ARM64).
2. **Download & Run**:
   ```bash
   sudo chmod +x /opt/deploy/setup.sh
   sudo /opt/deploy/setup.sh
   ```
3. **Interactive Setup**: Follow the prompts to configure your domain, email, and access method (Subdomains vs Ports).

## 🛡 Firewall Configuration

### Internal (UFW)
The script automatically configures UFW. If you use the **Ports** access method, additional ports (5678, 8081, 3000, 8080) are opened.

### External (OCI Security Lists)
You **MUST** manually open the following ports in the OCI Console:
- **Core**: 80, 443, 22
- **FTP**: 21, 30000-30009
- **Services (if using Ports)**: 8080, 5678, 8081, 3000

## 🧪 Verification & Testing

- **Web Access**: Visit `http://yourdomain.com` (or IP). You should see the Deployment Status page.
- **DB Management**: Visit the Adminer URL to manage both Postgres and MariaDB.
- **FTP Connectivity**:
  - **Web Root**: Connect to Port 21 with `webuser`. Files appear in `/opt/deploy/data/web_root`.
  - **File Storage**: Connect to Port 21 with `filesuser`. Files appear in `/opt/deploy/data/ftp_storage`.
- **Docker Status**: `sudo docker ps` should show 10 running containers.

## 📦 Backups

- **Automatic**: A cron job runs `/opt/deploy/scripts/backup.sh` every Sunday at 2:00 AM.
- **Manual**: Run `sudo /opt/deploy/scripts/backup.sh` anytime.
- **Retention**: Only the last 7 days of backups are kept in `/opt/deploy/backups`.

## 🛠 Troubleshooting

- **Containers not starting**: Check logs with `docker compose logs -f` inside the specific service directory.
- **Permission Issues**: Ensure files in `data/` are owned by the respective user/UID. The `setup.sh` handles initial ownership.
- **SSL Failures**: Ensure your domain is correctly pointed to the server IP and port 80 is open before running the Let's Encrypt setup.
- **RAM Issues**: If services crash on 1GB RAM, verify that the swap file is active: `swapon --show`.

---
*Optimized for performance, security, and low resource usage on OCI Free Tier.*
