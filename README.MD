# 🎮 Minecraft AWS Infrastructure & Server Setup

This project provides a comprehensive, script-based automation suite to deploy a highly available and cost-efficient Minecraft server on AWS. It includes automated infrastructure provisioning, a smart Node.js proxy for traffic management and cost optimization, and support for **Vanilla**, **Forge**, and **Fabric** server types.

## 🏗 Architecture Overview

For a detailed view, see [docs/diagramArchitecture.md](docs/diagramArchitecture.md).

The system follows a tiered architecture for security and scalability:

- **VPC Layer:** A dedicated Virtual Private Cloud with Public and Private subnets.
- **Smart Proxy (Public Subnet):** A custom Node.js application (`proxy/`) that:
  - Provides a "Big Server" aesthetic with a **Purple/Pink Gradient MOTD**.
  - Monitors the backend server status.
  - **Automatically Starts** the backend EC2 instance when a player joins.
  - Proxies traffic transparently to the backend once it is online.
- **Minecraft Server (Private Subnet):** The actual game server (Fabric/Forge/Vanilla), isolated from the public internet, receiving traffic only through the proxy.

## 🛠 Project Structure

| Directory/File | Description |
| :--- | :--- |
| `infra/` | AWS infrastructure setup (`setupAWSInfrastructure.sh`) and cleanup (`cleanupAWSInfrastructure.sh`) scripts. |
| `proxy/` | Node.js application for the smart proxy server. |
| `scripts/` | Installation scripts for the Minecraft server (Vanilla, Forge, Fabric). |
| `docs/` | Architecture diagrams and documentation. |
| `backups/` | Storage for server backups and snapshots. |
| `README.MD` | Project documentation and quick start guide. |

---

## 🚀 Quick Start Guide

### 1. Prerequisites

- [AWS CLI](https://aws.amazon.com/cli/) or [Antigravity](https://antigravity.dev/) configured with Administrator privileges.
- `jq` and `git` installed locally.

### 2. Provision Infrastructure

Run the infrastructure script. This will create the VPC, Security Groups, IAM Roles, and launch the EC2 instances. It will also generate a `mcServer-kp.pem` key if one doesn't exist.

```bash
./infra/setupAWSInfrastructure.sh
```

### 3. Deploy the Smart Proxy

Connect to the **Proxy** instance (Public IP provided by previous step) and install the proxy:

```bash
# On the Proxy EC2 Instance
cd /opt/proxy
npm install
npm start
```

*Note: The proxy runs on port `25565` (or configured port) and listens for player connections.*

### 4. Setup the Minecraft Server

Connect to the **Minecraft** instance (via the Proxy as a bastion). Run the main setup wizard:

```bash
# On the Minecraft EC2 Instance
./scripts/setupMain-mcServer.sh
```

Follow the interactive wizard:

1. **Select Server Type:**
    - `1) Vanilla`
    - `2) Forge`
    - `3) Fabric` (Recommended for performance/mods)
2. **Select Game Mode:** Survival, Creative, or Hardcore.
3. **Action Menu:** Create, Reinstall, or Delete server instances.

---

## ✨ Features

### 🟣 "Purple Kingdom" Aesthetic

The proxy server presents a premium "Official Server" look in the server list, customizable via `proxy/config.json`.

### 💰 Cost Optimization (Auto-Wake)

You don't need to keep the expensive backend server running 24/7.

1. **Stop the backend** when no one is playing.
2. The **Proxy** (t4g.nano) stays online for pennies a day.
3. When a player tries to join, the Proxy says "Server is sleeping... Starting up!" and **automatically boots the backend**.
4. After ~30 seconds, the player can join.

### 🛡 Security

- **Least Privilege IAM:** The Proxy EC2 role only has permissions to `Start`/`Stop` and `Describe` instances.
- **Private Isolation:** The Game Server has no Public IP and cannot be reached directly from the internet.

---

## ⚙️ Configuration details

### Minecraft Server Management (Systemd)

Servers are managed by **systemd** with unique service names based on their ID/Type.

**Commands:**

- **Start:** `sudo systemctl start 01-fabric-1.20.1-survival`
- **Stop:** `sudo systemctl stop 01-fabric-1.20.1-survival`
- **Logs:** `journalctl -u 01-fabric-1.20.1-survival -f`

## 📜 License

MIT License. Feel free to modify and adapt for your own server needs!
