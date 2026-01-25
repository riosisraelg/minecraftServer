#!/bin/bash

# Quick Reference Guide for Minecraft Proxy Management

cat << 'EOF'
╔══════════════════════════════════════════════════════════════╗
║        🎮 MINECRAFT PROXY - QUICK REFERENCE GUIDE           ║
╚══════════════════════════════════════════════════════════════╝

📍 LOCATION: /home/ec2-user/minecraftServer/proxy

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🚀 INITIAL DEPLOYMENT (First Time Setup)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

# Clone repository
git clone https://github.com/riosisraelg/minecraftServer.git
cd minecraftServer/proxy

# Run automated deployment
./deploy.sh

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🛠️  DAILY MANAGEMENT COMMANDS
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

./manage-proxy.sh start       # Start the proxy
./manage-proxy.sh stop        # Stop the proxy
./manage-proxy.sh restart     # Restart the proxy
./manage-proxy.sh status      # Check status and port usage
./manage-proxy.sh logs        # View live logs
./manage-proxy.sh cleanup     # Fix port conflicts (EADDRINUSE)
./manage-proxy.sh startup     # Configure auto-start on boot

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📊 MONITORING & DEBUGGING
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pm2 list                          # List all PM2 processes
pm2 logs minecraft-proxy          # Live logs
pm2 logs minecraft-proxy --err    # Error logs only
pm2 logs minecraft-proxy --lines 50  # Last 50 lines
sudo lsof -i :25599               # Check what's using port 25599 (default)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🐛 TROUBLESHOOTING
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

❌ ERROR: EADDRINUSE (Port already in use)
   FIX: ./manage-proxy.sh cleanup && ./manage-proxy.sh start

❌ ERROR: Proxy keeps restarting
   FIX: pm2 logs minecraft-proxy  # Check logs for errors
        Edit config.json to fix configuration
        ./manage-proxy.sh restart

❌ ERROR: Can't start backend server
   FIX: Check config.json has correct instanceId
        Verify AWS credentials: aws ec2 describe-instances
        Check IAM role permissions

❌ ERROR: Players can't connect
   FIX: Check Security Group allows port 25599
        Verify proxy is running: pm2 list
        Check logs: pm2 logs minecraft-proxy

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🔄 UPDATE PROCEDURE
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

cd /home/ec2-user/minecraftServer
git pull origin main
cd proxy
npm install
./manage-proxy.sh restart

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
⚙️  CONFIGURATION
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

File: config.json

{
  "region": "mx-central-1",
  "proxy_port": 25599,
  "backend": {
    "fabric": {
      "instanceId": "i-xxxxxxxxxxxxx",  ← Update this!
      "host": "10.0.2.161",
      "port": 25565
    }
  }
}

After editing: ./manage-proxy.sh restart

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📚 DOCUMENTATION
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

proxy/README.md          - Complete proxy documentation
docs/DEPLOYMENT.md       - EC2 deployment guide
CHANGELOG.md             - Version history and changes
README.MD                - Main project overview

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🎯 QUICK STATUS CHECK
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

./manage-proxy.sh status

Expected output:
  ✓ minecraft-proxy - online
  ✓ Port 25599 - listening

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

For detailed help: ./manage-proxy.sh help

EOF
