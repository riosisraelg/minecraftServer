# 🌸 CherryFrost MC - Minecraft Server on AWS

**Automated, Cost-Efficient, Cherry-Blossom Themed Minecraft Infrastructure.**

This project deploys a smart, auto-scaling Minecraft server network on AWS. It uses a lightweight Proxy to wake up the game server only when players join, saving up to 70% on cloud costs.

## 🚀 Key Features

*   **💸 Smart Cost Savings**: Game server sleeps when empty; Proxy wakes it up instantly.
*   **🌸 Beautiful Branding**: Custom MotD and Icon support built-in.
*   **🛡️ Secure Design**: Game server is isolated in a private subnet.
*   **⚡ Multiple Support**: Works with Vanilla, Fabric, Forge and PaperMC (Using Geycer for Bedrock comapbility).

## 🏁 Quick Start

### 1. Prerequisities
*   AWS CLI installed & configured.
*   `jq` installed.

### 2. Launch Infrastructure
```bash
./infra/setupAWSInfrastructure.sh
```
Follow the on-screen prompts. This will set up your VPC, Proxy, and Game Server.

### 3. Setup Game Server
SSH into your new instance (instructions provided at end of step 2) and run:
```bash
./scripts/setupMain-mcServer.sh
```

---

## 📚 Documentation

*   **[User Manual](docs/manual.md)**: Detailed configuration and usage guide.
*   **[Architecture](docs/diagramArchitecture.md)**: Deep dive into the network topology.

---
*License: MIT*
