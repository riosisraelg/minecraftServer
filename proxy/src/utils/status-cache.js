/**
 * AWS Status Cache Service
 *
 * Centralized caching for EC2 instance status to avoid redundant API calls.
 * Polls AWS at configurable intervals and provides cached status.
 */

const { getServerStatus } = require("../aws");

class StatusCache {
  constructor(instanceId, pollIntervalMs = 30000) {
    this.instanceId = instanceId;
    this.normalPollIntervalMs = pollIntervalMs;
    this.currentPollIntervalMs = pollIntervalMs;
    this.fastPollIntervalMs = 2000; // 2 seconds
    
    this.status = "unknown";
    this.lastUpdated = null;
    this.pollTimer = null;
    this.fastModeTimer = null;
  }

  /**
   * Start polling for status updates.
   */
  start() {
    this.update();
    this.startPolling(this.normalPollIntervalMs);
  }

  startPolling(interval) {
    if (this.pollTimer) clearInterval(this.pollTimer);
    this.currentPollIntervalMs = interval;
    this.pollTimer = setInterval(() => this.update(), interval);
    console.log(`[StatusCache] Polling ${this.instanceId} every ${interval}ms`);
  }

  /**
   * Stop polling.
   */
  stop() {
    if (this.pollTimer) {
      clearInterval(this.pollTimer);
      this.pollTimer = null;
    }
    if (this.fastModeTimer) {
      clearTimeout(this.fastModeTimer);
      this.fastModeTimer = null;
    }
    console.log("[StatusCache] Stopped polling");
  }

  /**
   * Enable fast polling for a duration (e.g. while server is starting)
   * @param {number} durationMs - How long to stay in fast mode
   */
  setFastPolling(durationMs = 60000) {
      if (this.currentPollIntervalMs === this.fastPollIntervalMs) {
          // Already in fast mode, extend it if needed? 
          // For simplicity, just let the current fast mode run out or reset it
          if (this.fastModeTimer) clearTimeout(this.fastModeTimer);
      } else {
          console.log(`[StatusCache] 🚀 Switching to FAST polling for ${durationMs/1000}s`);
          this.startPolling(this.fastPollIntervalMs);
      }

      this.fastModeTimer = setTimeout(() => {
          console.log(`[StatusCache] 🐢 Reverting to normal polling`);
          this.startPolling(this.normalPollIntervalMs);
          this.fastModeTimer = null;
      }, durationMs);
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
function createStatusCache(instanceId, pollIntervalMs = 30000) {
  const instance = new StatusCache(instanceId, pollIntervalMs);
  instance.start();
  return instance;
}

module.exports = {
  StatusCache,
  createStatusCache,
};
