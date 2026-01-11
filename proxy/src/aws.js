const { EC2Client, StartInstancesCommand, StopInstancesCommand, DescribeInstancesCommand } = require("@aws-sdk/client-ec2");
const config = require("../config.json");

const client = new EC2Client({ region: config.region });

async function getServerStatus(instanceId) {
    try {
        const command = new DescribeInstancesCommand({ InstanceIds: [instanceId] });
        const data = await client.send(command);
        const state = data.Reservations[0].Instances[0].State.Name;
        return state;
    } catch (err) {
        console.error("Error fetching instance status:", err);
        return "unknown";
    }
}

async function startServer(instanceId) {
    try {
        const command = new StartInstancesCommand({ InstanceIds: [instanceId] });
        await client.send(command);
        console.log(`Starting instance ${instanceId}...`);
        return true;
    } catch (err) {
        console.error("Error starting instance:", err);
        return false;
    }
}

async function stopServer(instanceId) {
    try {
        const command = new StopInstancesCommand({ InstanceIds: [instanceId] });
        await client.send(command);
        console.log(`Stopping instance ${instanceId}...`);
        return true;
    } catch (err) {
        console.error("Error stopping instance:", err);
        return false;
    }
}

module.exports = { getServerStatus, startServer, stopServer };
