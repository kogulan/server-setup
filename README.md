# 🚀 OCI Production-Ready Deployment Package

Welcome! If you've ever wanted to host your own automation tools, a website, and secure storage without the headache of manual configuration, you're in the right place.

This package is designed for **Oracle Cloud Infrastructure (OCI)** (specifically Ubuntu 24.04), but it works on almost any modern Linux server. It's built to be as close to "one-click" as possible, handling all the technical heavy lifting for you.

---

## 📦 What's inside the box?

We’ve bundled some of the best open-source tools to help you automate your life and host your projects:

*   **[n8n](https://n8n.io/)**: A powerful workflow automation tool. Think of it as a self-hosted Zapier. Connect your apps and automate tasks without writing code.
*   **[Activepieces](https://www.activepieces.com/)**: Another fantastic automation platform that's incredibly easy to use and great for business processes.
*   **[Huginn](https://github.com/huginn/huginn)**: Like your own personal agent. It can watch the web for you, scrape data, and send you alerts.
*   **[Adminer](https://www.adminer.org/)**: A lightweight, single-file database management tool. It makes managing your databases (PostgreSQL & MariaDB) a breeze.
*   **Secure SFTP**: A safe way to upload and download files to your server (replaces old, insecure FTP).
*   **PHP 8.3 Webserver**: Ready to host your website or landing pages.

---

## 🛠 How it Works (The "Magic" Explained)

You don't need to be a DevOps pro to use this, but here is what happens under the hood:

1.  **Shared Network**: All services live in a private "Docker network." This means they can talk to each other securely without being exposed to the whole internet.
2.  **Traffic Control (Nginx)**: We use Nginx as a "Reverse Proxy." It sits at the front door, takes incoming requests (like `n8n.yourdomain.com`), and points them to the right tool.
3.  **Smart Databases**: Instead of every tool having its own database, we use two powerful shared instances (PostgreSQL for automation tools, MariaDB for your web app). This saves memory and makes backups easier!
4.  **Auto-Tuning**: If your server has less than 2GB of RAM, our script automatically sets up a **4GB Swap file** and puts the services on a "diet" so they don't crash your server.
5.  **Always Secure**: All your passwords are randomly generated and never stored in plain sight. Plus, we use Let's Encrypt to give you those shiny green padlocks (SSL) for free.

---

## 📥 Getting the Code

First, you need to get these files onto your server. Open your terminal (or use OCI Cloud Shell) and follow these steps:

### Option A: Using a GitHub Token (Easiest for beginners)
1.  Go to your GitHub [Fine-grained personal access tokens](https://github.com/settings/tokens?type=beta) and create a token with "Contents" read access.
2.  On your server, run:
    ```bash
    git clone https://<your-token>@github.com/username/repository-name.git /opt/deploy
    ```

### Option B: Using SSH Keys (More secure)
1.  Check if you have an SSH key: `cat ~/.ssh/id_rsa.pub`. If not, create one with `ssh-keygen`.
2.  Copy the output and add it to your [GitHub SSH Keys](https://github.com/settings/keys).
3.  Run:
    ```bash
    git clone git@github.com:username/repository-name.git /opt/deploy
    ```

---

## 🚀 Quick Start Guide

Ready to go? Follow these 3 simple steps:

1.  **Move to the folder**:
    ```bash
    cd /opt/deploy
    ```
2.  **Make the script executable**:
    ```bash
    sudo chmod +x setup.sh
    ```
3.  **Run the Orchestrator**:
    ```bash
    sudo ./setup.sh
    ```

**What happens next?** The script will ask you for your domain name and email. Then, it will generate secure passwords, set up SSL (HTTPS), and start all your services. Grab a coffee—it takes about 2–5 minutes!

> **Pro Tip:** If the script ever stops or your connection drops, don't worry! Just run the `sudo ./setup.sh` command again. It’s smart enough to pick up right where it left off.

---

## 🛡 OCI Firewall (Crucial Step!)

For your services to be reachable, you **must** tell Oracle to let traffic through. In your OCI Cloud Console, open these ports in the "Security List":

*   **Web Browsing**: `80` (HTTP) and `443` (HTTPS)
*   **File Transfer (SFTP)**: `2222`
*   **Direct Access (if not using subdomains)**: `8080`, `5678`, `8081`, `3000`

---

## 📂 Where to find your stuff

*   **Passwords**: Everything is saved in `/opt/deploy/credentials.txt`. **Keep this safe!**
*   **Your Website Files**: Upload your HTML/PHP files to `/opt/deploy/data/web_root/`.
*   **Backups**: Found in `/opt/deploy/backups/`. We automatically back up your databases every week and keep the last 7 days of history.
*   **Logs**: If something goes wrong, check `/opt/deploy/data/nginx/` for web logs.

---

## 🤝 Contributing, Support & License

### Contributing
Found a bug or have a suggestion? Feel free to open an **Issue** or submit a **Pull Request**. We love community help!

### Support
If you're stuck, please check the [Troubleshooting] section in the script output or open a GitHub Issue.

### License
This project is licensed under the **MIT License**. You are free to use, copy, and modify it however you like!

---

*Made with ❤️ for the self-hosting community.*
