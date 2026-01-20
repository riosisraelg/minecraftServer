/**
 * Minecraft Proxy Server
 *
 * Smart proxy that:
 * - Shows custom MOTD in server list
 * - Shows custom server icon (favicon)
 * - Auto-starts backend EC2 when player joins
 * - Proxies traffic transparently when backend is running
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
const { initStatusCache } = require("./utils/status-cache");

// Configuration
const PROXY_PORT = config.proxy_port || 25599;
const BACKEND = config.backend.fabric;
const PROTOCOL_VERSION = 767; // 1.21.1

// Load server icon (must be 64x64 PNG)
let serverIconBase64 = null;
const iconPath = path.join(__dirname, "../../assets/branding/server-icon.png");
try {
  if (fs.existsSync(iconPath)) {
    const iconBuffer = fs.readFileSync(iconPath);
    serverIconBase64 = `data:image/png;base64,${iconBuffer.toString("base64")}`;
    console.log("✓ Server icon loaded successfully");
  } else {
    console.log("⚠ No server-icon.png found at:", iconPath);
  }
} catch (err) {
  console.error("⚠ Error loading server icon:", err.message);
}

// Initialize status cache
const statusCache = initStatusCache(BACKEND.instanceId);

console.log("=".repeat(50));
console.log("🌸 CherryFrost MC Proxy Server Starting...");
console.log("=".repeat(50));
console.log("Config:", JSON.stringify(config, null, 2));
console.log(`Proxy Port: ${PROXY_PORT}`);
console.log(`Backend: ${BACKEND.host}:${BACKEND.port}`);
console.log(`Instance ID: ${BACKEND.instanceId}`);
console.log(`Server Icon: ${serverIconBase64 ? "Loaded" : "Not found"}`);
console.log("=".repeat(50));

// Connection states
const STATE = {
  HANDSHAKE: 0,
  WAIT_STATUS_REQUEST: 2,
  WAIT_PING: 4,
  WAIT_LOGIN: 3,
};

/**
 * Build server status response for server list.
 */
function buildStatusResponse() {
  const isOnline = statusCache.isRunning();
  const statusText = isOnline ? "§aOnline" : "§cOffline";
  const motd = isOnline
    ? `${config.motd.line1}\n${config.motd.line2}`
    : "§7🌸 §cSleeping... §7Join to Wake up!";

  const response = {
    version: { name: statusText, protocol: PROTOCOL_VERSION },
    players: { max: 100, online: 0 },
    description: { text: motd },
  };

  // Add favicon if available
  if (serverIconBase64) {
    response.favicon = serverIconBase64;
  }

  return response;
}

/**
 * Build disconnect reason for login phase.
 * This must be a JSON Chat component.
 */
function buildDisconnectReason(message) {
  return JSON.stringify({ text: message });
}

/**
 * Send a disconnect packet during login phase.
 * Packet ID 0x00 = Login Disconnect
 */
function sendLoginDisconnect(client, message) {
  const reason = buildDisconnectReason(message);
  const packet = createPacket(0x00, writeString(reason));
  client.write(packet);
  client.end();
}

/**
 * Handle a client connection.
 */
function handleConnection(client) {
  const clientAddr = client.remoteAddress || "unknown";
  console.log(
    `[${new Date().toISOString()}] New connection from ${clientAddr}`,
  );

  let handshakeData = null;
  let state = STATE.HANDSHAKE;
  let buffer = Buffer.alloc(0);

  client.on("error", (err) => {
    console.log(`[${clientAddr}] Connection error: ${err.message}`);
  });

  const onData = (chunk) => {
    buffer = Buffer.concat([buffer, chunk]);

    // Process packets in buffer
    while (true) {
      const varInt = readVarInt(buffer);
      if (!varInt) break; // Need more data for length

      const packetLen = varInt.value;
      const prefixLen = varInt.length;
      const fullLen = prefixLen + packetLen;

      if (buffer.length < fullLen) break; // Need more data for body

      // Extract packet data
      const packet = buffer.subarray(0, fullLen);
      const packetBody = buffer.subarray(prefixLen, fullLen); // Fixed: body is within packet bounds

      const idVar = readVarInt(packetBody);
      if (!idVar) {
        console.log(`[${clientAddr}] Invalid packet ID`);
        buffer = buffer.subarray(fullLen);
        continue;
      }

      const packetID = idVar.value;
      const payload = packetBody.subarray(idVar.length);

      // State machine
      if (state === STATE.HANDSHAKE && packetID === 0x00) {
        // Handshake packet
        const handshake = parseHandshake(payload);
        if (handshake) {
          console.log(
            `[${clientAddr}] Handshake: protocol=${handshake.protocolVersion}, nextState=${handshake.nextState}`,
          );
          handshakeData = packet;
          state =
            handshake.nextState === 1
              ? STATE.WAIT_STATUS_REQUEST
              : STATE.WAIT_LOGIN;
        } else {
          console.log(`[${clientAddr}] Failed to parse handshake`);
        }
        buffer = buffer.subarray(fullLen);
      } else if (state === STATE.WAIT_STATUS_REQUEST && packetID === 0x00) {
        // Status Request -> Send response
        console.log(
          `[${clientAddr}] Status request, server status: ${statusCache.getStatus()}`,
        );
        const response = buildStatusResponse();
        client.write(createPacket(0x00, writeString(JSON.stringify(response))));
        state = STATE.WAIT_PING;
        buffer = buffer.subarray(fullLen);
      } else if (state === STATE.WAIT_PING && packetID === 0x01) {
        // Ping -> Pong
        console.log(`[${clientAddr}] Ping/Pong`);
        client.write(createPacket(0x01, payload));
        client.end();
        return;
      } else if (state === STATE.WAIT_LOGIN && packetID === 0x00) {
        // Login Start -> Check status and proxy or wake
        const currentStatus = statusCache.getStatus();
        console.log(
          `[${clientAddr}] Login attempt, backend status: ${currentStatus}`,
        );

        if (!statusCache.isRunning()) {
          if (statusCache.isStopped()) {
            console.log(`[${clientAddr}] Backend stopped, starting...`);
            startServer(BACKEND.instanceId);
            sendLoginDisconnect(
              client,
              "§5§lPurple Kingdom\n\n§eServer is waking up! 😴\n\n§7Please wait §f30-60 seconds§7...\n§7Then join again!",
            );
          } else {
            console.log(
              `[${clientAddr}] Backend in transitional state: ${currentStatus}`,
            );
            sendLoginDisconnect(
              client,
              `§5§lPurple Kingdom\n\n§eServer status: §f${currentStatus}\n\n§7Please wait a moment and try again.`,
            );
          }
          return;
        }

        // Server running -> Pipe to backend
        console.log(
          `[${clientAddr}] Backend running, connecting to ${BACKEND.host}:${BACKEND.port}...`,
        );
        client.removeListener("data", onData);

        const backend = net.createConnection({
          host: BACKEND.host,
          port: BACKEND.port,
          timeout: 10000,
        });

        backend.on("connect", () => {
          console.log(
            `[${clientAddr}] Connected to backend, piping traffic...`,
          );

          // Send saved handshake
          backend.write(handshakeData);

          // Send login start packet
          backend.write(packet);

          // Send any leftover data
          const leftover = buffer.subarray(fullLen);
          if (leftover.length > 0) {
            console.log(
              `[${clientAddr}] Sending ${leftover.length} leftover bytes`,
            );
            backend.write(leftover);
          }

          // Pipe bidirectionally
          client.pipe(backend);
          backend.pipe(client);
        });

        backend.on("timeout", () => {
          console.log(`[${clientAddr}] Backend connection timeout`);
          sendLoginDisconnect(
            client,
            "§cConnection to server timed out.\n§7Please try again.",
          );
          backend.destroy();
        });

        backend.on("error", (err) => {
          console.error(`[${clientAddr}] Backend error: ${err.message}`);
          // Don't try to send disconnect if client already disconnected
          if (!client.destroyed) {
            sendLoginDisconnect(
              client,
              `§cCannot connect to server.\n§7Error: ${err.message}`,
            );
          }
        });

        backend.on("close", () => {
          console.log(`[${clientAddr}] Backend connection closed`);
          if (!client.destroyed) client.end();
        });

        client.on("close", () => {
          console.log(`[${clientAddr}] Client connection closed`);
          if (!backend.destroyed) backend.end();
        });

        return;
      } else {
        // Unknown packet for current state
        console.log(
          `[${clientAddr}] Unexpected packet ID ${packetID} in state ${state}`,
        );
        buffer = buffer.subarray(fullLen);
      }
    }
  };

  client.on("data", onData);

  client.on("close", () => {
    console.log(`[${clientAddr}] Connection ended`);
  });
}

// Create server
const server = net.createServer(handleConnection);

server.listen(PROXY_PORT, "0.0.0.0", () => {
  console.log(`\n✓ Proxy successfully started on port ${PROXY_PORT}`);
  console.log(`  Connect using: your-server-ip:${PROXY_PORT}\n`);
});

server.on("error", (err) => {
  if (err.code === "EADDRINUSE") {
    console.error(`\n❌ ERROR: Port ${PROXY_PORT} is already in use!`);
    console.error("To fix this, run: ./manage-proxy.sh cleanup");
    process.exit(1);
  } else {
    console.error("Server error:", err);
    process.exit(1);
  }
});

// Graceful shutdown
const shutdown = (signal) => {
  console.log(`\n${signal} received. Shutting down gracefully...`);
  if (statusCache && typeof statusCache.stop === "function") {
    statusCache.stop();
  }
  server.close(() => {
    console.log("✓ Server closed");
    process.exit(0);
  });
  setTimeout(() => {
    console.error("Forced shutdown after timeout");
    process.exit(1);
  }, 5000);
};

process.on("SIGTERM", () => shutdown("SIGTERM"));
process.on("SIGINT", () => shutdown("SIGINT"));
process.on("uncaughtException", (err) => {
  console.error("Uncaught Exception:", err);
  shutdown("UNCAUGHT_EXCEPTION");
});
process.on("unhandledRejection", (reason, promise) => {
  console.error("Unhandled Rejection at:", promise, "reason:", reason);
});
