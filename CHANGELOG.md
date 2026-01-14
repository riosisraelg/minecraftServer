# 🔄 Changelog - Proxy Improvements

## Version 2.0.0 - 2026-01-14

### 🎉 Major Updates

#### New Files Added:
- `ecosystem.config.js` - PM2 process management configuration
- `manage-proxy.sh` - Comprehensive proxy management script
- `deploy.sh` - Automated deployment script for EC2
- `.env.example` - Environment configuration template
- `.gitignore` - Git ignore rules for logs and sensitive files
- `README.md` - Complete proxy documentation
- `../docs/DEPLOYMENT.md` - Step-by-step EC2 deployment guide

#### Improvements to Existing Files:

**`src/index.js`:**
- ✅ Added proper error handling for `EADDRINUSE` errors
- ✅ Improved error messages with actionable solutions
- ✅ Added graceful shutdown handlers (SIGTERM, SIGINT)
- ✅ Added uncaught exception and unhandled rejection handlers
- ✅ Better logging on server start

**`README.MD` (main):**
- ✅ Updated proxy deployment instructions
- ✅ Added troubleshooting section for common errors
- ✅ Corrected port numbers (25599 instead of 25565)

### 🐛 Bug Fixes

1. **EADDRINUSE Error (Port 25599):**
   - Added detection and helpful error messages
   - Created cleanup scripts to kill conflicting processes
   - Implemented proper shutdown handlers

2. **Multiple Proxy Instances:**
   - PM2 ecosystem config ensures only one instance runs
   - Management script cleans up old processes before starting new ones
   - Added restart limits to prevent infinite restart loops

3. **Process Management:**
   - PM2 now handles all process lifecycle
   - Automatic restart on crashes with limits
   - Logs are properly captured and rotated

### 🛠️ New Features

1. **Management Script (`manage-proxy.sh`):**
   ```bash
   ./manage-proxy.sh start     # Start proxy
   ./manage-proxy.sh stop      # Stop proxy
   ./manage-proxy.sh restart   # Restart proxy
   ./manage-proxy.sh status    # Check status
   ./manage-proxy.sh logs      # View logs
   ./manage-proxy.sh cleanup   # Fix port conflicts
   ./manage-proxy.sh startup   # Auto-start on boot
   ```

2. **Automated Deployment (`deploy.sh`):**
   - One-command deployment on EC2
   - Automatic dependency installation
   - Process cleanup before starting
   - PM2 configuration

3. **Better Logging:**
   - Separate error, output, and combined logs
   - Timestamped entries
   - Easy to tail with PM2

### 📚 Documentation

- **`proxy/README.md`**: Complete proxy documentation
  - Features and architecture
  - Installation and setup
  - Configuration options
  - Troubleshooting guide
  - Management commands

- **`docs/DEPLOYMENT.md`**: EC2 deployment guide
  - Step-by-step instructions
  - Testing procedures
  - Update procedures
  - Production checklist

### 🔧 Configuration

PM2 configuration (`ecosystem.config.js`):
- Max 10 restarts to prevent infinite loops
- 200MB memory limit
- Automatic restart enabled
- Log rotation
- 10-second minimum uptime before restart

### ⚙️ Technical Details

**Error Handling:**
- Catches `EADDRINUSE` and provides fix instructions
- Graceful shutdown on SIGTERM/SIGINT (5-second timeout)
- Uncaught exception handler
- Unhandled promise rejection handler

**Process Management:**
- Single PM2 instance named `minecraft-proxy`
- Replaces old `proxy` process
- Auto-cleanup of conflicting processes
- Proper signal handling

### 📦 Dependencies

No new dependencies added. Still using:
- `@aws-sdk/client-ec2` - AWS EC2 integration
- `dotenv` - Environment variables
- `minecraft-protocol` - Minecraft utilities

### 🚀 Migration Guide

If you're already running the old proxy:

1. Pull the latest code:
   ```bash
   git pull origin main
   cd proxy
   ```

2. Run the cleanup and deploy:
   ```bash
   ./manage-proxy.sh cleanup
   ./deploy.sh
   ```

3. Verify it's working:
   ```bash
   pm2 list
   pm2 logs minecraft-proxy
   ```

### ✅ Testing

All changes have been tested for:
- Port conflict detection and resolution
- Multiple process cleanup
- Graceful shutdown
- Auto-restart functionality
- PM2 integration

### 🎯 Next Steps

Recommended actions:
1. Deploy to EC2 using `./deploy.sh`
2. Test auto-start functionality
3. Configure PM2 startup: `pm2 startup`
4. Monitor logs for any issues

---

**Breaking Changes:** None - Fully backward compatible

**Migration Required:** Yes - Use new management scripts instead of manual `node src/index.js`
