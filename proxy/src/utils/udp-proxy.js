/**
 * Simple UDP Proxy for Bedrock/Geyser
 * 
 * Forwards UDP packets between public clients and private backend.
 * Handles auto-start triggers for the backend.
 */

const dgram = require('dgram');
const { startServer } = require('../aws');

class UdpProxy {
    constructor(port, backendHost, backendPort, statusCache, connectionManager, serverName, instanceId) {
        this.port = port;
        this.backendHost = backendHost;
        this.backendPort = backendPort; // Usually 19132 for Geyser too
        this.statusCache = statusCache;
        this.connectionManager = connectionManager;
        this.serverName = serverName;
        this.instanceId = instanceId;
        
        this.server = dgram.createSocket('udp4');
        this.clientMap = new Map(); // Map<ClientKey, BackendSocket>
        
        this.setup();
    }

    setup() {
        this.server.on('error', (err) => {
            console.error(`[UDP-${this.serverName}] Server error:\n${err.stack}`);
            this.server.close();
        });

        this.server.on('message', (msg, rinfo) => {
            // Logic for every packet coming from a Bedrock Client
            this.handleClientMessage(msg, rinfo);
        });

        this.server.on('listening', () => {
            const address = this.server.address();
            console.log(`✓ [${this.serverName}] UDP (Bedrock) listening on port ${address.port} -> ${this.backendHost}:${this.backendPort}`);
        });

        // Cleanup stale sessions every minute
        setInterval(() => this.cleanupSessions(), 60000);
    }

    start() {
        this.server.bind(this.port);
    }

    stop() {
        this.server.close();
        this.clientMap.forEach(socket => socket.close());
        this.clientMap.clear();
    }

    handleClientMessage(msg, rinfo) {
        const clientKey = `${rinfo.address}:${rinfo.port}`;
        
        // 1. Check if backend is running
        if (!this.statusCache.isRunning()) {
            if (this.statusCache.isStopped()) {
                // Throttle Wake-up logs
                if (Math.random() > 0.95) { 
                    console.log(`[UDP-${this.serverName}] Wake up request from Bedrock client ${clientKey}`);
                }
                
                startServer(this.instanceId);
                this.statusCache.setFastPolling(120000); // Poll fast for 2 minutes
                this.connectionManager.markServerStarted();
                
                // Optional: We could send a fake RakNet "Pong" here with "Server Starting..."
                // But usually Bedrock client just keeps retrying ping.
            }
            return;
        }

        // 2. Forward to Backend
        // We get or create the session here.
        // If it's a NEW session, getBackendSocket (or wrapper) should handle addConnection logic
        try {
            let backendSocket = this.getBackendSocket(clientKey, rinfo);
            
            backendSocket.send(msg, this.backendPort, this.backendHost, (err) => {
               if(err) console.error(`[UDP-${this.serverName}] Send error:`, err);
            });
            
        } catch (err) {
            // Socket might be closed
            this.clientMap.delete(clientKey);
        }
    }

    getBackendSocket(clientKey, clientRinfo) {
        if (this.clientMap.has(clientKey)) {
            const session = this.clientMap.get(clientKey);
            session.lastActivity = Date.now();
            return session.socket;
        }

        // Create new tunnel socket for this client
        const socket = dgram.createSocket('udp4');
        
        socket.on('message', (msg) => {
            // When backend replies, forward back to client
            this.server.send(msg, clientRinfo.port, clientRinfo.address);
            
            // Keep alive
            if (this.clientMap.has(clientKey)) {
                this.clientMap.get(clientKey).lastActivity = Date.now();
            }
        });

        socket.on('error', (err) => {
            console.error(`[UDP-Tunnel] Error for ${clientKey}:`, err.message);
            this.clientMap.delete(clientKey);
        });

        const session = {
            socket: socket,
            lastActivity: Date.now()
        };

        this.clientMap.set(clientKey, session);
        
        // Correct place to track connection: New Session Created
        this.connectionManager.addConnection();
        
        return socket;
    }

    cleanupSessions() {
        const now = Date.now();
        // Bedrock timeout is usually 10s, we keep sessions for 60s
        const TIMEOUT = 60000; 
        
        for (const [key, session] of this.clientMap) {
            if (now - session.lastActivity > TIMEOUT) {
                session.socket.close();
                this.clientMap.delete(key);
                // We should also tell connectionManager this player is gone
                // But UDP makes "player gone" hard to detect accurately without parsing packets.
                // We'll rely on the Java side ConnectionManager logic mostly, or accept 
                // that Bedrock players keep the counter alive as long as they send packets.
                this.connectionManager.removeConnection(); 
            }
        }
    }
}

function createUdpProxy(serverCfg, statusCache, connectionManager) {
    // Assuming backend Geyser port is same as config port (usually 19132)
    // Or we defaults to 19132
    const backendPort = serverCfg.bedrock_port || 19132;
    
    const proxy = new UdpProxy(
        serverCfg.bedrock_port, 
        serverCfg.host, 
        backendPort, 
        statusCache, 
        connectionManager, 
        serverCfg.name,
        serverCfg.instanceId
    );
    proxy.start();
    return proxy;
}

module.exports = { createUdpProxy };
