# 🎮 Minecraft Proxy

Smart Node.js proxy server for Minecraft that provides auto-start functionality, cost optimization, and a premium server list aesthetic.

## 🌟 Features

- **Auto-Start Backend**: Automatically starts the Minecraft server EC2 instance when players connect
- **Auto-Stop Backend**: Automatically stops the EC2 instance when no players are connected for X minutes (configurable)
- **Cost Optimization**: Keep the proxy running 24/7 on a cheap instance while the game server only runs when needed
- **CherryFrost MC Branding**: Custom cherry blossom themed MOTD and server icon
- **Protocol Support**: Minecraft 1.21.1 (Protocol 767)
- **AWS Integration**: Direct integration with AWS EC2 for instance management

## 📋 Prerequisites

- Node.js 18+ and npm
- PM2 process manager
- AWS credentials configured (for EC2 instance management)
- Port 25599 available

## 🚀 Quick Start

### On your EC2 Proxy Instance:

```bash
# Clone the repository
git clone https://github.com/riosisraelg/minecraftServer.git
cd minecraftServer/proxy

# Run the deployment script
./deploy.sh
```

That's it! The proxy will be running and managed by PM2.

## 🛠️ Management Commands

Use the `manage-proxy.sh` script for all operations:

```bash
# Start the proxy
./manage-proxy.sh start

# Stop the proxy
./manage-proxy.sh stop

# Restart the proxy
./manage-proxy.sh restart

# Check status
./manage-proxy.sh status

# View live logs
./manage-proxy.sh logs

# Clean up all processes (fixes port conflicts)
./manage-proxy.sh cleanup

# Setup auto-start on boot
./manage-proxy.sh startup
```

### Direct PM2 Commands

```bash
# View status
pm2 list

# View logs
pm2 logs minecraft-proxy

# Restart
pm2 restart minecraft-proxy

# Stop
pm2 stop minecraft-proxy
```

## ⚙️ Configuration

Edit `config.json` to customize:

```json
{
  "project": "mc-server",
  "region": "mx-central-1",
  "proxy_port": 25599,
  "backend": {
    "fabric": {
      "instanceId": "i-xxxxxxxxxxxxx",
      "host": "10.0.2.161",
      "port": 25565
    }
  },
  "motd": {
    "line1": "§dCherry§bFrost §5MC §f- §e§lMODDED SURVIVAL",
    "line2": "§6§nModpack en Modrinth§r §7- §fVersión §a1.21.1 §fFabric"
  },
  "autoShutdown": {
    "enabled": true,
    "idleTimeoutMinutes": 10
  }
}
```

### Configuration Options:

- **project**: Project name identifier
- **region**: AWS region for EC2 operations
- **proxy_port**: Port the proxy listens on (default: 25599)
- **backend.fabric.instanceId**: AWS EC2 instance ID of the Minecraft server
- **backend.fabric.host**: Private IP of the backend server
- **backend.fabric.port**: Port the Minecraft server runs on
- **motd**: Message of the Day shown in the server list
- **autoShutdown.enabled**: Enable/disable auto-shutdown feature (default: true)
- **autoShutdown.idleTimeoutMinutes**: Minutes to wait after last player disconnects before stopping EC2 (default: 10)

## 🔧 Troubleshooting

### Error: EADDRINUSE (Port already in use)

This happens when multiple proxy instances are running. Fix it with:

```bash
# Option 1: Use the cleanup command
./manage-proxy.sh cleanup

# Option 2: Manually kill the process
sudo kill -9 $(sudo lsof -t -i:25599)

# Then restart
./manage-proxy.sh start
```

### Proxy won't start

```bash
# Check PM2 status
pm2 list

# View error logs
pm2 logs minecraft-proxy --err

# Verify config.json is valid
cat config.json | jq .

# Check if port is available
sudo lsof -i :25599
```

### Backend server not starting

1. Check AWS credentials are configured
2. Verify the instance ID in `config.json` is correct
3. Ensure the EC2 instance has the proper IAM role
4. Check proxy logs: `pm2 logs minecraft-proxy`

## 📁 Project Structure

```
proxy/
├── src/
│   ├── index.js              # Main proxy server
│   ├── aws.js                # AWS EC2 integration
│   └── utils/                # Protocol utilities
│       ├── minecraft-protocol.js  # MC packet parsing
│       ├── status-cache.js        # Server status polling (10s interval)
│       └── connection-manager.js  # Player tracking & auto-shutdown
├── config.json               # Configuration file
├── package.json              # Dependencies
├── ecosystem.config.js       # PM2 configuration
├── manage-proxy.sh           # Management script
├── deploy.sh                 # Deployment script
├── .env.example              # Environment template
└── logs/                     # Log files (created automatically)
```

## 🔐 Security

The proxy requires AWS credentials to start/stop EC2 instances. Ensure the EC2 instance running the proxy has an IAM role with these permissions:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ec2:StartInstances",
        "ec2:StopInstances",
        "ec2:DescribeInstances"
      ],
      "Resource": "*"
    }
  ]
}
```

## 📊 How It Works

1. **Server List Ping**: Proxy responds with custom CherryFrost MC MOTD and server status
2. **Player Joins**: 
   - If backend is stopped → Start the instance and show "waking up" message
   - If backend is starting → Show "please wait 30-60 seconds" message
   - If backend is running → Pipe connection transparently to backend
3. **Gameplay**: All packets are forwarded bidirectionally between client and backend
4. **Player Disconnects**:
   - Connection tracked by `ConnectionManager`
   - When last player disconnects, idle timer starts
   - After `idleTimeoutMinutes`, EC2 instance is auto-stopped

## 🔄 Updates & Maintenance

```bash
# Pull latest changes
git pull origin main

# Update dependencies
npm install

# Restart with new code
./manage-proxy.sh restart
```

## 📝 Logs

Logs are stored in the `logs/` directory:

- `error.log` - Error messages only
- `out.log` - Standard output
- `combined.log` - Both error and output

View logs in real-time:
```bash
pm2 logs minecraft-proxy
```

## 🌐 Connecting to the Server

Players connect to: `<EC2-PUBLIC-IP>:25599`

The proxy will:
1. Check if the backend server is running
2. Auto-start it if stopped
3. Show appropriate messages to the player
4. Connect them once the server is ready

## 📦 Dependencies

- `@aws-sdk/client-ec2` - AWS SDK for EC2 operations
- `dotenv` - Environment variable management
- `minecraft-protocol` - Minecraft protocol utilities (optional)

## 🤝 Contributing

Feel free to submit issues and enhancement requests!

## 📄 License

MIT License - See main repository for details
