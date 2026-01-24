/**
 * Smart Multi-Server Minecraft Proxy (Domain-Aware)
 */

const net = require("net");
const fs = require("fs");
const path = require("path");
const config = require("../config.json");
const { startServer } = require("./aws");
const {
  readVarInt,
  writeString,
  createPacket,
  parseHandshake,
} = require("./utils/minecraft-protocol");
const { createStatusCache } = require("./utils/status-cache");
const { createConnectionManager } = require("./utils/connection-manager");

const PROTOCOL_VERSION = 767;

// Load server icon
let serverIconBase64 = null;
const iconPath = path.join(__dirname, "../../assets/branding/server-icon.png");
try {
  if (fs.existsSync(iconPath)) {
    const iconBuffer = fs.readFileSync(iconPath);
    serverIconBase64 = `data:image/png;base64,${iconBuffer.toString("base64")}`;
  }
} catch (err) {
  console.error("⚠ Error loading server icon:", err.message);
}

const STATE = {
  HANDSHAKE: 0,
  WAIT_STATUS_REQUEST: 2,
  WAIT_PING: 4,
  WAIT_LOGIN: 3,
};

/**
 * Main function to start all proxy listeners
 */
function startProxy() {
  console.log("=".repeat(50));
  console.log("🌸 CherryFrost Smart Proxy Starting...");
  console.log("=".repeat(50));

  if (!config.servers || !Array.isArray(config.servers)) {
    console.error("❌ No servers defined in config.json!");
    process.exit(1);
  }

  // Group servers by port
  const portsMap = {};
  config.servers.forEach(serverCfg => {
    const port = serverCfg.proxy_port;
    if (!portsMap[port]) portsMap[port] = [];
    
    // Initialize services for this specific server
    serverCfg.services = {
      statusCache: createStatusCache(serverCfg.instanceId),
      connectionManager: createConnectionManager(serverCfg.instanceId, config.autoShutdown)
    };
    
    portsMap[port].push(serverCfg);
  });

  const activeListeners = [];

  // Create one listener per unique port
  Object.keys(portsMap).forEach(port => {
    const serversOnPort = portsMap[port];
    const server = net.createServer((client) => {
      handleConnection(client, serversOnPort);
    });

    server.listen(port, "0.0.0.0", () => {
      console.log(`✓ Port ${port} is active (Supporting: ${serversOnPort.map(s => s.name).join(", ")})`);
    });

    activeListeners.push({ server, serversOnPort });
  });

  // Graceful shutdown
  const shutdown = (signal) => {
    console.log(`\n${signal} received. Shutting down...`);
    activeListeners.forEach(ln => {
      ln.serversOnPort.forEach(s => {
        s.services.statusCache.stop();
        s.services.connectionManager.stop();
      });
      ln.server.close();
    });
    setTimeout(() => process.exit(0), 1000);
  };

  process.on("SIGTERM", () => shutdown("SIGTERM"));
  process.on("SIGINT", () => shutdown("SIGINT"));
}

/**
 * Handle connection and route based on domain
 */
function handleConnection(client, serversOnPort) {
  let handshakeData = null;
  let state = STATE.HANDSHAKE;
  let buffer = Buffer.alloc(0);
  let targetServer = null;

  const onData = (chunk) => {
    buffer = Buffer.concat([buffer, chunk]);
    
    while (true) {
      const varInt = readVarInt(buffer);
      if (!varInt) break;
      const packetLen = varInt.value;
      const prefixLen = varInt.length;
      const fullLen = prefixLen + packetLen;
      if (buffer.length < fullLen) break;

      const packet = buffer.subarray(0, fullLen);
      const packetBody = buffer.subarray(prefixLen, fullLen);
      const idVar = readVarInt(packetBody);
      if (!idVar) { buffer = buffer.subarray(fullLen); continue; }

      const packetID = idVar.value;
      const payload = packetBody.subarray(idVar.length);

      if (state === STATE.HANDSHAKE && packetID === 0x00) {
        const handshake = parseHandshake(payload);
        if (handshake) {
          handshakeData = packet;
          // ROUTING LOGIC: Find server by domain
          // Remove the port if it comes in the serverAddress (e.g. domain.com:25565 -> domain.com)
          const cleanAddress = handshake.serverAddress.split('\0')[0].split(':')[0].toLowerCase();
          
          targetServer = serversOnPort.find(s => s.domain.toLowerCase() === cleanAddress) || serversOnPort[0];
          
          state = handshake.nextState === 1 ? STATE.WAIT_STATUS_REQUEST : STATE.WAIT_LOGIN;
        }
        buffer = buffer.subarray(fullLen);
      } else if (state === STATE.WAIT_STATUS_REQUEST && packetID === 0x00) {
        // Status Request
        const { statusCache } = targetServer.services;
        const isOnline = statusCache.isRunning();
        const motd = isOnline 
          ? `${targetServer.motd.line1}\n${targetServer.motd.line2}`
          : `§7🌸 §c${targetServer.name} is Sleeping... §7Join to Wake up!`;
        
        const response = {
          version: { name: isOnline ? "§aOnline" : "§cOffline", protocol: PROTOCOL_VERSION },
          players: { max: 100, online: 0 },
          description: { text: motd },
          favicon: serverIconBase64 || undefined
        };
        client.write(createPacket(0x00, writeString(JSON.stringify(response))));
        state = STATE.WAIT_PING;
        buffer = buffer.subarray(fullLen);
      } else if (state === STATE.WAIT_PING && packetID === 0x01) {
        client.write(createPacket(0x01, payload));
        client.end();
        return;
      } else if (state === STATE.WAIT_LOGIN && packetID === 0x00) {
        const { statusCache, connectionManager } = targetServer.services;
        
        if (!statusCache.isRunning()) {
          if (statusCache.isStopped()) {
            console.log(`[${targetServer.name}] Wake up request from ${handshakeData ? parseHandshake(handshakeData.subarray(readVarInt(handshakeData).length + 1)).serverAddress : 'unknown'}`);
            startServer(targetServer.instanceId);
            connectionManager.markServerStarted();
            sendLoginDisconnect(client, `§dCherry§bFrost\n\n§e${targetServer.name} is waking up! 😴\n\n§7Wait 60s and try again.`);
          } else {
            sendLoginDisconnect(client, `§dCherry§bFrost\n\n§eStatus: §f${statusCache.getStatus()}\n\n§7Try again soon.`);
          }
          return;
        }

        // Pipe to backend
        client.removeListener("data", onData);
        const backend = net.createConnection({ host: targetServer.host, port: targetServer.port, timeout: 10000 });

        backend.on("connect", () => {
          connectionManager.addConnection();
          backend.write(handshakeData);
          backend.write(packet);
          const leftover = buffer.subarray(fullLen);
          if (leftover.length > 0) backend.write(leftover);
          client.pipe(backend);
          backend.pipe(client);
        });

        backend.on("error", (err) => {
          if (!client.destroyed) sendLoginDisconnect(client, `§cTarget Server Error: ${err.message}`);
        });

        backend.on("close", () => {
          connectionManager.removeConnection();
          if (!client.destroyed) client.end();
        });

        client.on("close", () => { if (!backend.destroyed) backend.end(); });
        return;
      } else {
        buffer = buffer.subarray(fullLen);
      }
    }
  };

  client.on("data", onData);
}

function sendLoginDisconnect(client, message) {
  const reason = JSON.stringify({ text: message });
  const packet = createPacket(0x00, writeString(reason));
  client.write(packet);
  client.end();
}

startProxy();
