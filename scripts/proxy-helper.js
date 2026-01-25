const fs = require('fs');
const path = require('path');
const { EC2Client, DescribeInstancesCommand, AuthorizeSecurityGroupIngressCommand, RevokeSecurityGroupIngressCommand } = require("@aws-sdk/client-ec2");

const CONFIG_PATH = path.join(__dirname, '../proxy/config.json');
const SETUP_CONFIG_PATH = path.join(__dirname, 'server-setup.json');

function loadConfig() {
    if (!fs.existsSync(CONFIG_PATH)) {
        console.error(`Config file not found at ${CONFIG_PATH}`);
        process.exit(1);
    }
    try {
        const data = fs.readFileSync(CONFIG_PATH, 'utf8');
        return JSON.parse(data);
    } catch (err) {
        console.error('Error reading config:', err);
        process.exit(1);
    }
}

function saveConfig(config) {
    try {
        fs.writeFileSync(CONFIG_PATH, JSON.stringify(config, null, 2));
        console.log('Config updated successfully.');
    } catch (err) {
        console.error('Error writing config:', err);
        process.exit(1);
    }
}

function getNextPort() {
    const config = loadConfig();
    const servers = config.servers || [];
    
    if (servers.length === 0) {
        return 25565;
    }

    const usedPorts = servers.map(s => s.port).map(p => parseInt(p, 10));
    const maxPort = Math.max(...usedPorts);
    
    // Simple logic: max + 1. 25565 is default base.
    return maxPort >= 25565 ? maxPort + 1 : 25565;
}

function addServer(args) {
    // args: [name, port, type, version, gamemode, geyser?]
    const [name, portStr, type, version, gamemode, geyser] = args;
    const port = parseInt(portStr, 10);
    
    if (!name || isNaN(port)) {
        console.error('Usage: add-server <name> <port> <type> <version> <gamemode> [geyser]');
        process.exit(1);
    }

    const config = loadConfig();
    
    // Template from existing server or default
    let template = {
        instanceId: "i-00000000000000000",
        host: "127.0.0.1",
        proxy_port: 25599,
        motd: {
            line1: "Minecraft Server",
            line2: `${type} ${version}`
        }
    };

    if (config.servers && config.servers.length > 0) {
        const first = config.servers[0];
        template.instanceId = first.instanceId;
        template.host = first.host;
        template.proxy_port = first.proxy_port;
    }

    // Determine domain base
    // Assume a default domain base if not inferable?
    // Looking at config: fabric-1.21.1-survival.mcserver01.xyz
    // Let's try to extract the base domain from the first server
    let baseDomain = "mcserver01.xyz";
    if (config.servers && config.servers.length > 0) {
        const parts = config.servers[0].domain.split('.');
        if (parts.length >= 2) {
             baseDomain = parts.slice(-2).join('.');
        }
    }

    const newServer = {
        name: name,
        domain: `${name}.${baseDomain}`,
        proxy_port: template.proxy_port,
        instanceId: template.instanceId,
        host: template.host,
        port: port,
        motd: {
            line1: `§d${type.toUpperCase()} §b${version}`,
            line2: `§7Gamemode: §f${gamemode}`
        }
    };

    if (geyser === 'true') {
        newServer.bedrock_port = port; // Reuse same port for UDP
    }

    config.servers.push(newServer);
    saveConfig(config);
    console.log(`Added server ${name} on port ${port}`);
}

function removeServer(name) {
    if (!name) {
        console.error('Usage: remove-server <name>');
        process.exit(1);
    }
    
    const config = loadConfig();
    const originalLength = config.servers ? config.servers.length : 0;
    
    // Filter out by Service Name (or Name)
    // The mc-manager uses SERVICE_NAME which corresponds to our server entry's "name"
    if (config.servers) {
        config.servers = config.servers.filter(s => s.name !== name);
    }
    
    if (config.servers.length < originalLength) {
        saveConfig(config);
        console.log(`Removed server '${name}' from proxy config.`);
    } else {
        console.log(`Server '${name}' not found in proxy config.`);
    }
}

function parseSetupConfig() {
    if (!fs.existsSync(SETUP_CONFIG_PATH)) {
        return; 
    }
    try {
        const data = fs.readFileSync(SETUP_CONFIG_PATH, 'utf8');
        const config = JSON.parse(data);
        
        // 1. Export Global Defaults
        const g = config.global || {};
        if (g.gamemode) console.log(`export CONFIG_GAMEMODE="${g.gamemode}"`);
        if (g.online_mode !== undefined) console.log(`export CONFIG_ONLINE_MODE="${g.online_mode}"`);
        if (g.seed) console.log(`export CONFIG_SEED="${g.seed}"`);
        if (g.memory_max) console.log(`export CONFIG_MEMORY_MAX="${g.memory_max}"`);
        if (g.memory_min) console.log(`export CONFIG_MEMORY_MIN="${g.memory_min}"`);
        if (g.enable_geyser !== undefined) console.log(`export CONFIG_ENABLE_GEYSER="${g.enable_geyser}"`);
        
        if (config.default_type) console.log(`export CONFIG_DEFAULT_TYPE="${config.default_type}"`);

        // 2. Export Profiles
        const p = config.profiles || {};
        
        // Fabric
        if (p.fabric) {
            console.log(`export CONFIG_FABRIC_VERSION="${p.fabric.version}"`);
            console.log(`export CONFIG_FABRIC_LOADER="${p.fabric.loader}"`);
            console.log(`export CONFIG_FABRIC_INSTALLER="${p.fabric.installer}"`);
        }
        
        // Forge
        if (p.forge) {
             console.log(`export CONFIG_FORGE_VERSION="${p.forge.version}"`);
        }
        
        // Vanilla
        if (p.vanilla) {
             console.log(`export CONFIG_VANILLA_VERSION="${p.vanilla.version}"`);
             console.log(`export CONFIG_VANILLA_URL="${p.vanilla.url}"`);
        }
        
        // Paper
        if (p.paper) {
             console.log(`export CONFIG_PAPER_VERSION="${p.paper.version}"`);
        }

    } catch (err) {
        console.error('Error parsing setup config:', err);
    }
}

async function openPort(args) {
    const [portStr, instanceId, protocolArg] = args;
    const port = parseInt(portStr, 10);
    const protocol = protocolArg || 'tcp'; // tcp, udp, both

    if (!port || !instanceId) {
        console.error('Usage: open-port <port> <instance-id> [tcp|udp|both]');
        process.exit(1);
    }

    const config = loadConfig();
    const region = config.region || 'us-east-1';

    const client = new EC2Client({ region });

    const openPortOnInstance = async (targetInstanceId) => {
        console.log(`🔍 Finding Security Group for instance ${targetInstanceId}...`);
        const descCmd = new DescribeInstancesCommand({ InstanceIds: [targetInstanceId] });
        const descData = await client.send(descCmd);
        
        const instance = descData.Reservations[0].Instances[0];
        if (!instance) {
            console.error(`❌ Instance ${targetInstanceId} not found`);
            return;
        }

        const sgId = instance.SecurityGroups[0].GroupId;
        console.log(`✅ Found Security Group: ${sgId} for ${targetInstanceId}`);

        const protocolsToOpen = protocol === 'both' ? ['tcp', 'udp'] : [protocol];

        for (const proto of protocolsToOpen) {
            console.log(`🔓 Opening ${proto.toUpperCase()} port ${port} on ${targetInstanceId}...`);
            try {
                await client.send(new AuthorizeSecurityGroupIngressCommand({
                    GroupId: sgId,
                    IpPermissions: [{
                        IpProtocol: proto,
                        FromPort: port,
                        ToPort: port,
                        IpRanges: [{ CidrIp: "0.0.0.0/0" }]
                    }]
                }));
                console.log(`✅ ${proto.toUpperCase()} Port ${port} opened successfully on ${targetInstanceId}.`);
            } catch (err) {
                if (err.name === 'InvalidPermission.Duplicate') {
                    console.log(`⚠️  ${proto.toUpperCase()} Port ${port} is already open on ${targetInstanceId}.`);
                } else {
                    console.error(`❌ Error opening ${proto} on ${targetInstanceId}:`, err.message);
                }
            }
        }
    };

    try {
        // 1. Open on Backend Instance
        await openPortOnInstance(instanceId);

        // 2. Open on Proxy Instance (if defined and different)
        if (config.proxy_instance_id && config.proxy_instance_id !== instanceId) {
            console.log(`🔄 Also opening port on Proxy Instance (${config.proxy_instance_id})...`);
            await openPortOnInstance(config.proxy_instance_id);
        }
        
    } catch (err) {
        console.error('❌ Error updating Security Group:', err.message);
        process.exit(1);
    }
}

async function closePort(args) {
    const [portStr, instanceId, protocolArg] = args;
    const port = parseInt(portStr, 10);
    const protocol = protocolArg || 'tcp';

    if (!port || !instanceId) {
        console.error('Usage: close-port <port> <instance-id> [tcp|udp|both]');
        process.exit(1);
    }

    const config = loadConfig();
    const region = config.region || 'us-east-1';
    const client = new EC2Client({ region });

    const closePortOnInstance = async (targetInstanceId) => {
        console.log(`🔍 Finding Security Group for instance ${targetInstanceId}...`);
        const descCmd = new DescribeInstancesCommand({ InstanceIds: [targetInstanceId] });
        const descData = await client.send(descCmd);
        
        const instance = descData.Reservations[0].Instances[0];
        if (!instance) {
            console.error(`❌ Instance ${targetInstanceId} not found`);
            return;
        }

        const sgId = instance.SecurityGroups[0].GroupId;
        
        const protocolsToClose = protocol === 'both' ? ['tcp', 'udp'] : [protocol];

        for (const proto of protocolsToClose) {
            console.log(`🔒 Closing ${proto.toUpperCase()} port ${port} on ${targetInstanceId}...`);
            try {
                await client.send(new RevokeSecurityGroupIngressCommand({
                    GroupId: sgId,
                    IpPermissions: [{
                        IpProtocol: proto,
                        FromPort: port,
                        ToPort: port,
                        IpRanges: [{ CidrIp: "0.0.0.0/0" }]
                    }]
                }));
                console.log(`✅ ${proto.toUpperCase()} Port ${port} closed successfully on ${targetInstanceId}.`);
            } catch (err) {
                 if (err.name === 'InvalidPermission.NotFound') {
                     console.log(`ℹ️  ${proto.toUpperCase()} Port ${port} was not open on ${targetInstanceId}.`);
                 } else {
                     console.error(`❌ Error closing ${proto} on ${targetInstanceId}:`, err.message);
                 }
            }
        }
    };

    try {
        // 1. Close on Backend Instance
        await closePortOnInstance(instanceId);

        // 2. Close on Proxy Instance (if defined and different)
        if (config.proxy_instance_id && config.proxy_instance_id !== instanceId) {
            console.log(`🔄 Also closing port on Proxy Instance (${config.proxy_instance_id})...`);
            await closePortOnInstance(config.proxy_instance_id);
        }

    } catch (err) {
        console.error('❌ Error updating Security Group:', err.message);
        process.exit(1);
    }
}

function main() {
    const cmd = process.argv[2];
    const args = process.argv.slice(3);

    switch (cmd) {
        case 'get-next-port':
            console.log(getNextPort());
            break;
        case 'add-server':
            addServer(args);
            break;
        case 'parse-setup-config':
            parseSetupConfig();
            break;
        case 'open-port':
            openPort(args);
            break;
        case 'remove-server':
            removeServer(args[0]);
            break;
        case 'close-port':
            closePort(args);
            break;
        default:
            console.error('Unknown command. Use: get-next-port, add-server, remove-server, parse-setup-config, open-port, close-port');
            process.exit(1);
    }
}

main();
