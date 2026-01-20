# 📋 Changelog

All notable changes to the Minecraft AWS Infrastructure project.

---

## [2.3.1] - 2026-01-20

### 🐛 Bug Fixes
- **Branding**: Fixed inconsistency where "Purple Kingdom" was still shown in disconnect messages. Now correctly displays "CherryFrost" to match server assets.

## [2.3.0] - 2026-01-20

### 🔌 Auto-Shutdown Feature

#### New Components
- Added `proxy/src/utils/connection-manager.js` - Singleton class that tracks active player connections
- Implements idle timer that auto-stops EC2 instance when no players are connected

#### Features
- **Connection Tracking**: Monitors active backend connections in real-time
- **Idle Timer**: Configurable timeout (default 10 minutes) before shutting down
- **Smart Shutdown**: Only shuts down servers that were started by the proxy
- **Graceful Handling**: Timer cancels immediately when a new player connects

#### Configuration
New `autoShutdown` section in `config.json`:
```json
{
  "autoShutdown": {
    "enabled": true,
    "idleTimeoutMinutes": 10
  }
}
```

#### Documentation Updates
- Updated `README.MD` with Auto-Wake & Auto-Sleep lifecycle
- Updated `proxy/README.md` with ConnectionManager documentation
- Updated `docs/PROXY-MONITORING.md` with:
  - New architecture diagram showing ConnectionManager
  - Auto-shutdown sequence diagram
  - ConnectionManager API reference
  - Updated configuration options table

---

## [2.2.0] - 2026-01-19

### 🌸 CherryFrost MC Branding

#### New Assets
- Added `assets/branding/` directory with server branding materials
- `server-icon.png` - 64x64 server icon for Minecraft server list
- `cherryfrost-banner-night.png` - Night theme banner
- `cherryfrost-banner-sunset.png` - Sunset theme banner

#### Proxy Updates
- **Server Icon Support**: Proxy now sends favicon in status response
- Updated MOTD with CherryFrost MC color scheme
- Added `fs` and `path` imports for icon loading

#### Documentation
- Added `docs/PROXY-MONITORING.md` - Complete monitoring system documentation with Mermaid diagrams
- Updated `README.MD` with CherryFrost MC branding
- Updated `docs/diagramArchitecture.md` with new service names

#### Scripts
- Updated Fabric loader to v0.18.4 and installer to v1.1.1

---

## [2.1.0] - 2026-01-19

### 🔧 Consolidation & Cleanup

#### Scripts
- **Unified Installer**: Consolidated three separate scripts (`main-mcServer-fabric.sh`, `main-mcServer-forge.sh`, `main-mcServer-vanilla.sh`) into a single `main-mcServer.sh`
- Added `infra/lib/aws-common.sh` for shared AWS infrastructure functions
- Improved `setupMain-mcServer.sh` wizard with better server type selection

#### Proxy Improvements
- Added `proxy/src/utils/minecraft-protocol.js` for protocol handling
- Added `proxy/src/utils/status-cache.js` for server status caching

#### Removed
- `HelloWorld.java` / `HelloWorld.class` (test files)
- `package-lock.json` from root
- `proxy/src/index_packet_proxy.js` (deprecated)
- Individual server type scripts (merged into unified installer)

---

## [2.0.0] - 2026-01-14

### 🎉 Major Updates - Proxy v2.0

#### New Files
- `proxy/ecosystem.config.js` - PM2 process management
- `proxy/manage-proxy.sh` - Comprehensive management script
- `proxy/deploy.sh` - Automated EC2 deployment
- `proxy/.env.example` - Environment configuration template
- `proxy/README.md` - Complete proxy documentation
- `docs/DEPLOYMENT.md` - Step-by-step EC2 deployment guide

#### Improvements
- **Error Handling**: Proper detection of `EADDRINUSE` errors with helpful messages
- **Graceful Shutdown**: SIGTERM/SIGINT handlers with 5-second timeout
- **Process Management**: PM2 with auto-restart (max 10 retries)
- **Logging**: Separate error, output, and combined logs

### � Bug Fixes
1. **Port Conflicts**: Auto-detection and cleanup scripts
2. **Multiple Instances**: PM2 ensures single process
3. **Zombie Processes**: Proper signal handling

### ⚙️ PM2 Configuration
- Max 10 restarts to prevent infinite loops
- 200MB memory limit
- 10-second minimum uptime before restart

---

## [1.0.0] - Initial Release

### Features
- AWS VPC infrastructure setup
- Smart proxy with auto-start backend
- Support for Fabric, Forge, and Vanilla servers
- Purple Kingdom aesthetic MOTD
- Cost optimization (proxy on t4g.nano ~$3/month)
- Security: Backend in private subnet, least-privilege IAM

---

**Migration Guide**: See [docs/DEPLOYMENT.md](docs/DEPLOYMENT.md)
