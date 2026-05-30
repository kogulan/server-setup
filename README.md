# OCI Production-Ready Deployment Package

This package provides a complete, automated setup for web services, automation tools, and SFTP storage on Oracle Cloud Infrastructure (OCI).

## 🚀 Quick Start (Automated Installation)

You do **NOT** need to fill out any `.env` files manually. The `setup.sh` script will automatically generate secure passwords, configure environment files, and set up your databases.

1. **Connect to your OCI VM** via SSH.
2. **Transfer the package** to `/opt/deploy` (see "Manual Transfer" below).
3. **Run the Orchestrator**:
   ```bash
   cd /opt/deploy
   sudo chmod +x setup.sh
   sudo ./setup.sh
   ```
   *The script will ask for your domain and email once, then handle everything else.*

## 🏗 Features

- **Idempotent & Resumable**: If the script stops, just run it again. It saves your settings in `/opt/deploy/.env`.
- **Auto-Configured SWAP**: Automatically creates a 4GB swap file on 1GB RAM instances to prevent crashes.
- **Secure SFTP**: Replaces insecure FTP with SFTP on Port **2222**.
- **SSL Protection**: All tools (n8n, Activepieces, etc.) are served over HTTPS.

## 🛡 OCI Firewall (Security List)

You **MUST** manually open these ports in your OCI Cloud Console:
- **Web**: 80, 443
- **SSH**: 22
- **SFTP**: 2222
- **Services (Port mode only)**: 8080, 5678, 8081, 3000

## 📂 Folder Structure

- `/opt/deploy/setup.sh`: Main installation script.
- `/opt/deploy/credentials.txt`: **All generated passwords and links (Check here after setup!)**
- `/opt/deploy/data/`: All persistent data (back up this folder).
- `/opt/deploy/backups/`: Automated weekly backups (.sql and .tar.gz).

## 🛠 Manual Transfer Guide

If you are not using Git, you can transfer files using SCP or by creating the folder:
```bash
sudo mkdir -p /opt/deploy
# Upload your files to /opt/deploy/ using WinSCP or FileZilla (SFTP)
```

## 📦 Troubleshooting
- **Port 80 Error**: Ensure your domain points to the server IP and Port 80 is open *before* selecting Let's Encrypt.
- **Resuming**: If the script fails during DB init, simply run it again. It will detect the existing containers and try again.
