# CherryFrost MC - Official Manual

This manual contains detailed configuration and usage instructions for the CherryFrost Minecraft Server infrastructure.

## 🏗 Architecture Detail

The system is built on a tiered architecture for maximum security and cost-efficiency:

1.  **Virtual Private Cloud (VPC)**: Custom isolated network.
    *   **Public Subnet**: Hosts the Proxy server (accessible from internet).
    *   **Private Subnet**: Hosts the Game server (no direct internet access).
2.  **Smart Proxy**: A Node.js application acting as the gatekeeper.
    *   Handles the "Cherry Blossom" MOTD.
    *   Wakes up the backend server on demand.
    *   Shuts down the backend server when idle.
3.  **NAT Gateway**: Allows the private game server to download updates without exposing it to incoming connections.

For a visual diagram, see [docs/diagramArchitecture.md](diagramArchitecture.md).

## ⚙️ Configuration Guide

### Infrastructure (`infra/awsConfig.json`)

Controls the AWS resources created.

| Key | Description | Default |
| :--- | :--- | :--- |
| `region` | AWS Region to deploy in. | `mx-central-1` |
| `instance_type_proxy` | EC2 size for the Proxy (needs very little). | `t4g.nano` |
| `instance_type_mc` | EC2 size for the Game Server. | `t4g.small` |
| `autoShutdown.idleTimeoutMinutes` | Minutes to wait before stopping empty server. | `10` |

### Proxy Settings (`proxy/config.json`)

Controls the proxy behavior and MOTD.

```json
{
  "project": "mc-server",
  "proxy_port": 25599,
  "motd": {
    "line1": "§dCherry§bFrost §5MC",
    "line2": "§fSurvival Mode"
  }
}
```

## 🛠 Advanced Usage

### Manual Server Management through Proxy

You can manage the backend server without logging into AWS Console by SSHing into the Proxy instance first.

```bash
# SSH into Proxy
ssh -i key.pem ec2-user@<PROXY-IP>

# SSH from Proxy to Backend (Private IP)
ssh -i key.pem ec2-user@<BACKEND-PRIVATE-IP>
```

### Deploying a Custom Icon

1.  Place a 64x64 PNG file at `assets/branding/server-icon.png`.
2.  The proxy automatically loads this file on startup.
3.  Restart the proxy to apply changes:
    ```bash
    pm2 restart minecraft-proxy
    ```
