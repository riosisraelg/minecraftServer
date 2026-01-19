# 🎮 Minecraft AWS Infrastructure & Server Setup

This project provides a comprehensive, script-based automation suite to deploy a highly available and cost-efficient Minecraft server on AWS. It includes automated infrastructure provisioning, a smart Node.js proxy for traffic management and cost optimization, and support for **Vanilla**, **Forge**, and **Fabric** server types.

## 🏗 Architecture Overview

For a detailed view, see [docs/diagramArchitecture.md](docs/diagramArchitecture.md).

The system follows a tiered architecture for security and scalability:

- **VPC Layer:** A dedicated Virtual Private Cloud with Public and Private subnets.
- **Smart Proxy (Public Subnet):** A custom Node.js application (`proxy/`) that:
  - Provides a "Big Server" aesthetic with a **Purple/Pink Gradient MOTD**.
  - Monitors the backend server status via AWS API.
  - **Automatically Starts** the backend EC2 instance when a player joins.
  - Proxies traffic transparently to the backend once it is online.
- **Minecraft Server (Private Subnet):** The actual game server (Fabric/Forge/Vanilla), isolated from the public internet, receiving traffic only through the proxy.

## 🛠 Project Structure

```
minecraftServer/
├── infra/                  # AWS infrastructure
│   ├── lib/
│   │   └── aws-common.sh   # Shared functions
│   ├── awsConfig.json      # Configuration
│   ├── setupAWSInfrastructure.sh
│   └── cleanupAWSInfrastructure.sh
├── proxy/                  # Smart proxy server
│   ├── src/
│   │   ├── index.js        # Main proxy
│   │   ├── aws.js          # AWS EC2 controller
│   │   └── utils/          # Protocol utilities
│   ├── config.json         # Proxy configuration
│   └── package.json
├── scripts/                # Server installation
│   ├── main-mcServer.sh    # Unified installer (Fabric/Forge/Vanilla)
│   └── setupMain-mcServer.sh  # Entry point wizard
├── docs/                   # Documentation
└── backups/                # Server backups
```

---

## 🚀 Quick Start Guide

### 1. Prerequisites

- [AWS CLI](https://aws.amazon.com/cli/) configured with Administrator privileges.
- `jq` and `git` installed locally.

### 2. Provision Infrastructure

```bash
./infra/setupAWSInfrastructure.sh
```

This creates VPC, Security Groups, IAM Roles, and launches EC2 instances.

### 3. Deploy the Smart Proxy

SSH to the **Proxy** instance and run:

```bash
cd /home/ec2-user
git clone https://github.com/riosisraelg/minecraftServer.git
cd minecraftServer/proxy
npm install
npm start
```

Or use PM2 for production:
```bash
npm install -g pm2
pm2 start src/index.js --name minecraft-proxy
pm2 save
```

### 4. Setup the Minecraft Server

SSH to the **Minecraft** instance (via Proxy as bastion) and run:

```bash
./scripts/setupMain-mcServer.sh
```

The wizard will ask you to:
1. **Select Server Type:** Fabric, Forge, or Vanilla
2. **Select Game Mode:** Survival, Creative, or Hardcore
3. **Configure RAM:** Default 2GB max, 1GB min

---

## ✨ Features

### 🟣 "Purple Kingdom" Aesthetic

Custom MOTD in the server list, configurable in `proxy/config.json`.

### 💰 Cost Optimization (Auto-Wake)

1. Stop the backend when not playing.
2. Proxy (t4g.nano) stays online for ~$3/month.
3. Player joins → Proxy auto-starts backend → Player waits 30-60s → Plays!

### 🛡 Security

- **Least Privilege IAM:** Proxy only has `Start`/`Stop`/`Describe` permissions.
- **Private Isolation:** Game server has no public IP.

---

## ⚙️ Configuration

### Proxy (`proxy/config.json`)

```json
{
  "region": "us-east-1",
  "proxy_port": 25599,
  "backend": {
    "fabric": {
      "instanceId": "i-xxxxx",
      "host": "10.0.2.xxx",
      "port": 25565
    }
  }
}
```

### Server Management (Systemd)

```bash
# Start server
sudo systemctl start 01-fabric-1.21.1-survival

# Stop server
sudo systemctl stop 01-fabric-1.21.1-survival

# View logs
journalctl -u 01-fabric-1.21.1-survival -f
```

---

## 📜 License

MIT License. Feel free to modify and adapt for your own server needs!
