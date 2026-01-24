/**
 * AWS Status Cache Service
 *
 * Centralized caching for EC2 instance status to avoid redundant API calls.
 * Polls AWS at configurable intervals and provides cached status.
 */

const { getServerStatus } = require("../aws");

class StatusCache {
  constructor(instanceId, pollIntervalMs = 10000) {
    this.instanceId = instanceId;
    this.pollIntervalMs = pollIntervalMs;
    this.status = "unknown";
    this.lastUpdated = null;
    this.pollTimer = null;
  }

  /**
   * Start polling for status updates.
   */
  start() {
    // Initial fetch
    this.update();

    // Set up polling interval
    this.pollTimer = setInterval(() => this.update(), this.pollIntervalMs);

    console.log(
      `[StatusCache] Started polling for ${this.instanceId} every ${this.pollIntervalMs}ms`,
    );
  }

  /**
   * Stop polling.
   */
  stop() {
    if (this.pollTimer) {
      clearInterval(this.pollTimer);
      this.pollTimer = null;
      console.log("[StatusCache] Stopped polling");
    }
  }

  /**
   * Force an immediate status update.
   */
  async update() {
    try {
      this.status = await getServerStatus(this.instanceId);
      this.lastUpdated = new Date();
    } catch (err) {
      console.error("[StatusCache] Update error:", err.message);
      // Keep previous status on error
    }
  }

  /**
   * Get the current cached status.
   * @returns {string} - Current status (running, stopped, pending, etc.)
   */
  getStatus() {
    return this.status;
  }

  /**
   * Check if the server is running.
   * @returns {boolean}
   */
  isRunning() {
    return this.status === "running";
  }

  /**
   * Check if the server is stopped.
   * @returns {boolean}
   */
  isStopped() {
    return this.status === "stopped";
  }

  /**
   * Get time since last update.
   * @returns {number|null} - Milliseconds since last update, or null
   */
  getAge() {
    if (!this.lastUpdated) return null;
    return Date.now() - this.lastUpdated.getTime();
  }
}

/**
 * Create a new status cache instance.
 * @param {string} instanceId - EC2 instance ID
 * @param {number} pollIntervalMs - Polling interval in milliseconds
 * @returns {StatusCache}
 */
function createStatusCache(instanceId, pollIntervalMs = 10000) {
  const instance = new StatusCache(instanceId, pollIntervalMs);
  instance.start();
  return instance;
}

module.exports = {
  StatusCache,
  createStatusCache,
};
