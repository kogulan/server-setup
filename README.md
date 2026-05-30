# OCI Production-Ready Deployment Package

This package provides an automated setup for a suite of web services, automation tools, and SFTP storage on Oracle Cloud Infrastructure (OCI).

## 🚀 Getting Started (How to Transfer Files)

To get this setup onto your fresh OCI VM, follow these steps:

1. **Connect to your OCI VM** via SSH.
2. **Download the package**:
   ```bash
   sudo apt-get update && sudo apt-get install -y git
   git clone https://github.com/your-repo/oci-deploy.git /tmp/oci-deploy
   sudo mkdir -p /opt/deploy
   sudo cp -r /tmp/oci-deploy/* /opt/deploy/
   ```
3. **Run the Orchestrator**:
   ```bash
   cd /opt/deploy
   sudo chmod +x setup.sh
   sudo ./setup.sh
   ```

## 🏗 Architecture & Features

- **SFTP (Port 2222)**: Secure File Transfer replacing insecure FTP.
- **RAM-Aware**:
  - **1GB RAM (E2.1.Micro)**: Configures 4GB swap and a tiny Redis (64MB) for stability.
  - **24GB RAM (A1.Flex)**: Configures standard performance without strict limits.
- **SSL Support**: Every service (n8n, Activepieces, etc.) is served over HTTPS, even when using port-based access.
- **Centralized Credentials**: All generated passwords are saved securely in `/opt/deploy/credentials.txt`.

## 📂 Folder Structure

- `/opt/deploy/setup.sh`: The main orchestrator.
- `/opt/deploy/data/`: ALL persistent data.
- `/opt/deploy/backups/`: Weekly compressed backups (7-day retention).
- `/opt/deploy/credentials.txt`: Generated passwords and access links.

## 🛡 Security & Firewall

### OCI Cloud Console (Ingress Rules)
You **MUST** open these ports in your OCI Security List:
- **Web**: 80, 443
- **SSH**: 22
- **SFTP**: 2222
- **Services (if using Ports)**: 8080, 5678, 8081, 3000

### Internal SFTP
- **Web Root**: Connect to Port **2222** with user `webuser`. Files are in `web_root/`.
- **File Storage**: Connect to Port **2222** with user `filesuser`. Files are in `my_ftp_files/`.

## 📦 Backups
Automatic backups run every Sunday at 2:00 AM. They include all PostgreSQL and MariaDB databases plus your file storage.

## 🛠 Troubleshooting
If a service is slow on a 1GB VM, it's normal as it uses Swap. Check `sudo docker ps` to ensure all 10 containers are healthy.
