# 🚀 Deployment Guide - EC2 Instance

This guide walks you through deploying the Minecraft server and proxy on AWS EC2.

## 📋 Prerequisites

1. AWS account with EC2 access
2. Infrastructure already provisioned (VPC, Security Groups, EC2 instances)
3. SSH access to both Proxy and Main server instances

## 🔧 Step-by-Step Deployment

### 1️⃣ Deploy the Proxy Server

SSH into your **Proxy EC2 instance** (the one in the public subnet):

```bash
# SSH into proxy instance
ssh -i mcServer-kp.pem ec2-user@<PROXY-PUBLIC-IP>

# Clone the repository
cd /home/ec2-user
git clone https://github.com/riosisraelg/minecraftServer.git
cd minecraftServer/proxy

# Run the automated deployment script
./deploy.sh
```

The deployment script will:
- Install Node.js dependencies
- Install PM2 globally
- Clean up any existing processes
- Start the proxy with PM2
- Configure auto-start on boot

**Verify deployment:**
```bash
pm2 list
# Should show "minecraft-proxy" as "online"

# Check logs
pm2 logs minecraft-proxy
```

### 2️⃣ Configure the Backend Server ID

Make sure `config.json` has the correct backend instance ID:

```bash
# Edit config.json
nano config.json
```

Update the `instanceId` field:
```json
{
  "backend": {
    "fabric": {
      "instanceId": "i-xxxxxxxxxxxxx",  // ← Your actual instance ID
      "host": "10.0.2.161",
      "port": 25565
    }
  }
}
```

Restart the proxy after changes:
```bash
./manage-proxy.sh restart
```

### 3️⃣ Deploy the Main Minecraft Server

SSH into your **Main Minecraft EC2 instance** (via the proxy as a bastion):

```bash
# From your local machine, SSH through the proxy
ssh -i mcServer-kp.pem -J ec2-user@<PROXY-PUBLIC-IP> ec2-user@<MAIN-PRIVATE-IP>

# Or if already on the proxy instance
ssh ec2-user@10.0.2.161

# Clone the repository (if not already done)
cd /home/ec2-user
git clone https://github.com/riosisraelg/minecraftServer.git
cd minecraftServer

# Run the setup wizard
./scripts/setupMain-mcServer.sh
```

Follow the interactive wizard to:
1. Select server type (Vanilla/Forge/Fabric)
2. Select game mode (Survival/Creative/Hardcore)
3. Create the server instance

### 4️⃣ Start the Minecraft Server

After setup completes, start your server:

```bash
# The wizard will tell you the exact command, but it will look like:
sudo systemctl start 01-fabric-1.20.1-survival

# Check status
sudo systemctl status 01-fabric-1.20.1-survival

# View logs
journalctl -u 01-fabric-1.20.1-survival -f
```

## ✅ Testing the Setup

### Test the Proxy

From your local machine:

```bash
# Test if port is open
nc -zv <PROXY-PUBLIC-IP> 25599

# If you have the Minecraft client:
# Add server: <PROXY-PUBLIC-IP>:25599
```

### Test Auto-Start Feature

1. Stop the backend server:
```bash
ssh ec2-user@<PROXY-PUBLIC-IP>
# Check instance ID from config.json
aws ec2 stop-instances --instance-ids i-xxxxxxxxxxxxx --region mx-central-1
```

2. Try to connect from Minecraft client
3. You should see "Server is waking up! Please wait 30-60 seconds..."
4. The proxy will automatically start the backend instance
5. Wait ~60 seconds and try connecting again

## 🔄 Updates and Maintenance

### Update Proxy Code

```bash
ssh ec2-user@<PROXY-PUBLIC-IP>
cd /home/ec2-user/minecraftServer
git pull origin main
cd proxy
npm install
./manage-proxy.sh restart
```

### Update Minecraft Server

```bash
ssh -J ec2-user@<PROXY-PUBLIC-IP> ec2-user@<MAIN-PRIVATE-IP>
cd /home/ec2-user/minecraftServer
git pull origin main

# Re-run setup wizard if needed
./scripts/setupMain-mcServer.sh
```

## 🐛 Troubleshooting

### Issue: Port 25599 already in use

**Solution:**
```bash
cd /home/ec2-user/minecraftServer/proxy
./manage-proxy.sh cleanup
./manage-proxy.sh start
```

### Issue: Proxy can't start backend server

**Possible causes:**
1. **Wrong instance ID**: Check `config.json`
2. **AWS permissions**: Ensure the proxy EC2 instance has the correct IAM role
3. **Wrong region**: Verify `region` in `config.json` matches your EC2 region

**Debug:**
```bash
# Check proxy logs
pm2 logs minecraft-proxy

# Manually test AWS permissions
aws ec2 describe-instances --instance-ids i-xxxxxxxxxxxxx --region mx-central-1
aws ec2 start-instances --instance-ids i-xxxxxxxxxxxxx --region mx-central-1
```

### Issue: Can't connect to backend from proxy

**Solution:**
1. Verify backend is running: `sudo systemctl status <service-name>`
2. Check Security Group allows traffic from proxy private IP
3. Verify private IP in `config.json` matches backend instance
4. Check firewall rules on backend server

```bash
# On backend server
sudo firewall-cmd --list-all
# Should show port 25565 open
```

### Issue: Minecraft shows "Can't connect to server"

**Check:**
1. Proxy is running: `pm2 list`
2. Port 25599 is listening: `sudo lsof -i :25599`
3. Security Group allows inbound on 25599 from your IP
4. Check proxy logs: `pm2 logs minecraft-proxy`

## 📊 Monitoring

### View Proxy Status
```bash
./manage-proxy.sh status
```

### View Proxy Logs
```bash
# Live logs
pm2 logs minecraft-proxy

# Last 100 lines
pm2 logs minecraft-proxy --lines 100

# Error logs only
pm2 logs minecraft-proxy --err
```

### View Minecraft Server Logs
```bash
# Live logs
journalctl -u <service-name> -f

# Last 50 lines
journalctl -u <service-name> -n 50

# Errors only
journalctl -u <service-name> -p err
```

## 🎯 Production Checklist

Before going live:

- [ ] Proxy is running and managed by PM2
- [ ] PM2 configured to start on boot (`pm2 startup`)
- [ ] Backend instance ID is correct in `config.json`
- [ ] Tested auto-start functionality
- [ ] Minecraft server starts automatically with systemd
- [ ] Backups configured (see main README)
- [ ] Security Groups properly configured
- [ ] Logs are being captured
- [ ] Tested from external network (not just locally)

## 🆘 Getting Help

If you encounter issues:

1. Check the logs first: `pm2 logs minecraft-proxy`
2. Review proxy README: `proxy/README.md`
3. Test AWS permissions manually
4. Verify all configurations match your infrastructure

## 📚 Additional Resources

- [Main README](../README.MD) - Overview and architecture
- [Proxy README](../proxy/README.md) - Detailed proxy documentation
- [Architecture Diagram](../docs/diagramArchitecture.md) - System design

---

**Happy Mining! ⛏️🎮**
