const { SSMClient, SendCommandCommand, GetCommandInvocationCommand } = require("@aws-sdk/client-ssm");
const config = require("../config.json");

const client = new SSMClient({ region: config.region });

/**
 * Sends a command to the EC2 instance to gracefully stop the Minecraft service.
 * This ensures data is saved before the instance is stopped.
 * 
 * @param {string} instanceId - The EC2 instance ID
 * @returns {Promise<boolean>} - True if successful, false otherwise
 */
async function stopMinecraftService(instanceId) {
    console.log(`[SSM] Attempting to stop Minecraft service on ${instanceId}...`);
    
    // Command to find and stop the service
    // We look for services matching the pattern *-fabric-*, *-forge-*, or *-vanilla-*
    // and stop the first active one found.
    const shellScript = [
        "#!/bin/bash",
        "SERVICE=$(systemctl list-units --full --all --state=active --no-legend | grep -o -E '^[0-9]+-(fabric|forge|vanilla)-.*\\.service' | head -n 1)",
        "if [ -n \"$SERVICE\" ]; then",
        "   echo \"Found active service: $SERVICE\"",
        "   echo \"Stopping service...\"",
        "   sudo systemctl stop \"$SERVICE\"",
        "   # Wait a few seconds to ensure process has time to cleanup/save if systemctl returns early",
        "   sleep 5",
        "   echo \"Service stopped successfully.\"",
        "else",
        "   echo \"No active Minecraft service found.\"",
        "fi",
        "sync" // Ensure filesystem changes are written to disk
    ];

    try {
        const command = new SendCommandCommand({
            InstanceIds: [instanceId],
            DocumentName: "AWS-RunShellScript",
            Parameters: {
                commands: shellScript
            }
        });

        const sendResponse = await client.send(command);
        const commandId = sendResponse.Command.CommandId;
        
        console.log(`[SSM] Command sent (ID: ${commandId}). Waiting for completion...`);

        // Wait for command to complete
        return await waitForCommand(instanceId, commandId);

    } catch (err) {
        console.error("[SSM] Failed to send stop command:", err);
        return false;
    }
}

async function waitForCommand(instanceId, commandId, maxAttempts = 20) {
    for (let i = 0; i < maxAttempts; i++) {
        try {
            const command = new GetCommandInvocationCommand({
                CommandId: commandId,
                InstanceId: instanceId
            });
            
            const response = await client.send(command);
            const status = response.Status; // Pending, InProgress, Success, Cancelled, Failed, TimedOut, Cancelling
            
            if (status === 'Success') {
                console.log("[SSM] remote command output:\n", response.StandardOutputContent);
                console.log("[SSM] Graceful shutdown command completed successfully.");
                return true;
            } else if (['Failed', 'Cancelled', 'TimedOut'].includes(status)) {
                console.error(`[SSM] Command failed with status: ${status}`);
                console.error("[SSM] Stderr:", response.StandardErrorContent);
                return false;
            }

            // Wait 2 seconds before polling again
            await new Promise(resolve => setTimeout(resolve, 2000));
            
        } catch (err) {
            console.error(`[SSM] Error checking command status (attempt ${i+1}):`, err.message);
            // Verify if error is throttling, wait a bit longer
            await new Promise(resolve => setTimeout(resolve, 2000));
        }
    }
    
    console.error("[SSM] Timeout waiting for command completion");
    return false;
}

module.exports = { stopMinecraftService };
