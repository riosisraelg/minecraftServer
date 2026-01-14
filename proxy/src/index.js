const mc = require('minecraft-protocol');
const net = require('net');
const config = require('../config.json');
const { getServerStatus, startServer } = require('./aws');

const PROXY_PORT = config.proxy_port || 25565;
const BACKEND = config.backend.fabric;




const proxy = mc.createServer({
    'online-mode': false, // We don't authenticate here, we pass-through (or backend does it)
    host: '0.0.0.0',
    port: PROXY_PORT,
    version: '1.20.1', // Target version? Or flexible? false means auto-detect for ping
    motd: config.motd.line1 + "\n" + config.motd.line2,
    maxPlayers: 100,
    beforePing: (response, client, callback) => {
        console.log(`[Ping] Request from ${client.socket.remoteAddress}`);
        // Custom Purple MOTD Logic
        response.version = {
            name: '§5Fabric 1.20.1',
            protocol: 763
        };
        response.description = {
            text: config.motd.line1 + "\n" + config.motd.line2
        };

        // Async check AWS status?
        // 'beforePing' must be fast. We should cache AWS status periodically.
        // For now, let's just return the static fancy MOTD.
        // We can append status if we found it recently.
        if (cachedStatus === 'stopped') {
            response.version.name = '§c🔴 Offline';
            response.description.text += "\n§cServer is currently sleeping. Join to wake it up!";
        } else if (cachedStatus === 'running') {
            response.version.name = '§a🟢 Online';
        } else {
            response.version.name = '§6🟡 ' + cachedStatus;
        }

        callback(null, response);
    }
});

let cachedStatus = 'unknown';

// Polling AWS status
setInterval(async () => {
    try {
        cachedStatus = await getServerStatus(BACKEND.instanceId);
    } catch(e) { console.error("Polling error:", e); }
}, 10000); // Check every 10s

// Initial check
getServerStatus(BACKEND.instanceId).then(s => cachedStatus = s);

proxy.on('login', async (client) => {
    console.log(`User ${client.username} connecting...`);

    if (cachedStatus !== 'running') {
        const status = await getServerStatus(BACKEND.instanceId);
        if (status === 'stopped') {
            console.log(`Triggering start for ${BACKEND.instanceId}`);
            startServer(BACKEND.instanceId);
            client.end("§5§lPurple Kingdom\n\n§eServer was sleeping! 😴\n\n§7I have sent the signal to wake it up.\n§7Please wait §f30-60 seconds§7 and join again!\n\n§dStatus: §fStarting...");
        } else {
            client.end(`§5§lPurple Kingdom\n\n§eServer status: §f${status}\n§7Please wait a moment...`);
        }
        return;
    }

    // Server is running. Forward the connection.
    // This is the tricky part with 'minecraft-protocol' acting as a server.
    // We already completed a handshake with the client.
    // We need to now handshake with the backend, acting as the user?

    // Simple Forwarding (Node-Client-Proxy style):
    console.log("Forwarding to backend...");
    const backendClient = mc.createClient({
        host: BACKEND.host,
        port: BACKEND.port,
        username: client.username,
        version: '1.20.1', // Must match
        keepAlive: false,
        auth: 'offline' // Backend must be offline mode for this simple proxy
    });

    backendClient.on('connect', () => {
        console.log("Connected to backend!");

        // Pipe packets
        // Client -> Backend
        client.on('packet', (data, meta) => {
            if (meta.state === 'play' && backendClient.state === 'play') {
                backendClient.write(meta.name, data);
            }
        });

        // Backend -> Client
        backendClient.on('packet', (data, meta) => {
            if (meta.state === 'play' && client.state === 'play') {
                client.write(meta.name, data);
            }
        });
    });

    backendClient.on('end', (reason) => {
        client.end(reason);
        console.log("Backend ended connection");
    });

    client.on('end', () => {
        backendClient.end();
        console.log("Client ended connection");
    });

    backendClient.on('error', (err) => {
        console.error("Backend error:", err);
        client.end("§cBackend connection error.");
    });

});

console.log(`Proxy listening on 0.0.0.0:${PROXY_PORT}`);
console.log(`To connect, use: localhost:${PROXY_PORT}`);
