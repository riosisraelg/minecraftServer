/**
 * Connection Manager
 * 
 * Tracks active backend connections and auto-shuts down the EC2 instance
 * when no players are connected for a configurable timeout period.
 */

const { stopServer } = require('../aws');
const { stopMinecraftService } = require('../ssm');

class ConnectionManager {
    constructor(instanceId, config = {}) {
        this.instanceId = instanceId;
        this.enabled = config.enabled !== false;
        this.idleTimeoutMs = (config.idleTimeoutMinutes || 10) * 60 * 1000;
        this.activeConnections = 0;
        this.idleTimer = null;
        this.serverStartedByProxy = false;

        console.log(`[ConnectionManager] Initialized:`);
        console.log(`  - Auto-shutdown: ${this.enabled ? 'ENABLED' : 'DISABLED'}`);
        console.log(`  - Idle timeout: ${config.idleTimeoutMinutes || 10} minutes`);
    }

    /**
     * Mark that the server was started by proxy (eligible for auto-shutdown).
     */
    markServerStarted() {
        this.serverStartedByProxy = true;
        console.log('[ConnectionManager] Server started by proxy - eligible for auto-shutdown');
    }

    /**
     * Called when a player successfully connects to the backend.
     */
    addConnection() {
        this.activeConnections++;
        // console.log(`[ConnectionManager] Connection added. Active: ${this.activeConnections}`);

        // Cancel any pending shutdown
        this.cancelIdleTimer();
    }

    /**
     * Called when a player disconnects from the backend.
     */
    removeConnection() {
        this.activeConnections = Math.max(0, this.activeConnections - 1);
        // console.log(`[ConnectionManager] Connection removed. Active: ${this.activeConnections}`);

        // Start idle timer if no more connections
        if (this.activeConnections === 0) {
            this.startIdleTimer();
        }
    }

    /**
     * Start the idle shutdown timer.
     */
    startIdleTimer() {
        if (!this.enabled) {
            console.log('[ConnectionManager] Auto-shutdown disabled, not starting timer');
            return;
        }

        if (!this.serverStartedByProxy) {
            console.log('[ConnectionManager] Server was not started by proxy, not auto-shutting down');
            return;
        }

        if (this.idleTimer) {
            console.log('[ConnectionManager] Idle timer already running');
            return;
        }

        const timeoutMinutes = this.idleTimeoutMs / 60000;
        console.log(`[ConnectionManager] ⏰ Starting idle timer: ${timeoutMinutes} minutes until shutdown`);

        this.idleTimer = setTimeout(async () => {
            console.log('[ConnectionManager] ⏰ Idle timeout reached!');
            
            if (this.activeConnections === 0) {
                console.log('[ConnectionManager] 🛑 No active connections - initiating server shutdown...');
                try {
                    // Attempt graceful shutdown first
                    console.log('[ConnectionManager] 💾 Attempting graceful service stop via SSM...');
                    await stopMinecraftService(this.instanceId);

                    console.log('[ConnectionManager] 🔌 Stopping EC2 instance...');
                    const result = await stopServer(this.instanceId);
                    if (result) {
                        console.log('[ConnectionManager] ✅ Server shutdown initiated successfully');
                        this.serverStartedByProxy = false;
                    } else {
                        console.error('[ConnectionManager] ❌ Failed to initiate server shutdown');
                    }
                } catch (err) {
                    console.error('[ConnectionManager] ❌ Error during shutdown:', err.message);
                }
            } else {
                console.log(`[ConnectionManager] Players connected (${this.activeConnections}), aborting shutdown`);
            }
            
            this.idleTimer = null;
        }, this.idleTimeoutMs);
    }

    /**
     * Cancel the idle shutdown timer.
     */
    cancelIdleTimer() {
        if (this.idleTimer) {
            clearTimeout(this.idleTimer);
            this.idleTimer = null;
            console.log('[ConnectionManager] ⏰ Idle timer cancelled - player connected');
        }
    }

    /**
     * Get current status.
     */
    getStatus() {
        return {
            enabled: this.enabled,
            activeConnections: this.activeConnections,
            idleTimerActive: this.idleTimer !== null,
            serverStartedByProxy: this.serverStartedByProxy,
        };
    }

    /**
     * Stop the connection manager (cleanup).
     */
    stop() {
        this.cancelIdleTimer();
        console.log('[ConnectionManager] Stopped');
    }
}

/**
 * Create a new connection manager instance.
 * @param {string} instanceId - EC2 instance ID
 * @param {object} config - Auto-shutdown configuration
 * @returns {ConnectionManager}
 */
function createConnectionManager(instanceId, config = {}) {
    return new ConnectionManager(instanceId, config);
}

module.exports = {
    ConnectionManager,
    createConnectionManager
};
