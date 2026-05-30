# OCI Production-Ready Deployment Package

This package provides an automated setup for a suite of web services, automation tools, and SFTP storage on Oracle Cloud Infrastructure (OCI).

## 🚀 Getting Started (How to Transfer Files)

1. **Connect to your OCI VM** via SSH.
2. **Download the package**:
   ```bash
   sudo apt-get update && sudo apt-get install -y git
   git clone https://github.com/your-repo/oci-deploy.git /tmp/oci-deploy
   sudo mkdir -p /opt/deploy
   sudo cp -r /tmp/oci-deploy/* /opt/deploy/
   ```
3. **⚠️ IMPORTANT: Port 80**
   Before running the script, ensure **Port 80** is open in your OCI Cloud Console Security List. Let's Encrypt requires this to verify your domain.

4. **Run the Orchestrator**:
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

## 🛡 Security & Firewall

### OCI Cloud Console (Ingress Rules)
You **MUST** open these ports in your OCI Security List:
- **Web**: 80, 443
- **SSH**: 22
- **SFTP**: 2222
- **Services (if using Ports)**: 8080, 5678, 8081, 3000

## 📦 Backups
Automatic backups run every Sunday at 2:00 AM. They include all PostgreSQL and MariaDB databases plus your file storage.

## 🛠 Troubleshooting
- **Certbot failed**: Ensure your domain points to the server IP and Port 80 is open. The script will fall back to self-signed SSL if it fails.
- **"Crontab not found"**: This is now fixed in the updated script by auto-installing the `cron` package.
- **Slow performance**: On 1GB VMs, services may respond slower due to Swap usage.
