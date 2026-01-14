const net = require('net');
const config = require('../config.json');
const { getServerStatus, startServer } = require('./aws');

const PROXY_PORT = config.proxy_port || 25599;
const BACKEND = config.backend.fabric;

console.log("Loaded Config:", JSON.stringify(config, null, 2));
console.log(`Using Proxy Port: ${PROXY_PORT}`);

// --- Helper: Simple VarInt Reader for sniffing ---
function readVarInt(buffer, offset = 0) {
    let num = 0;
    let bytes = 0;
    while (true) {
        if (offset + bytes >= buffer.length) return null; // Incomplete
        const byte = buffer[offset + bytes];
        num |= (byte & 0x7F) << (7 * bytes);
        bytes++;
        if ((byte & 0x80) === 0) break;
        if (bytes > 5) return null; // Too big/invalid
    }
    return { value: num, length: bytes };
}

function writeVarInt(value) {
    const buffer = [];
    while (true) {
        if ((value & ~0x7F) === 0) {
            buffer.push(value);
            break;
        } else {
            buffer.push((value & 0x7F) | 0x80);
            value >>>= 7;
        }
    }
    return Buffer.from(buffer);
}

function writeString(str) {
    const len = writeVarInt(Buffer.byteLength(str));
    return Buffer.concat([len, Buffer.from(str, 'utf8')]);
}

function createPacket(packetId, dataBuffer) {
    const id = writeVarInt(packetId);
    const length = writeVarInt(id.length + dataBuffer.length);
    return Buffer.concat([length, id, dataBuffer]);
}

// --- Status Cache ---
let cachedStatus = 'unknown';

async function updateStatus() {
    try {
        cachedStatus = await getServerStatus(BACKEND.instanceId);
    } catch(e) { } // Ignore poll errors
}
setInterval(updateStatus, 10000);
updateStatus();

console.log(`TCP Proxy listening on 0.0.0.0:${PROXY_PORT}`);

const server = net.createServer((client) => {
    let handshakeData = null;
    let step = 0; // 0=Wait Handshake, 1=Wait Request
    
    // We only need to inspect the first few packets.
    // We will buffer data until we decide what to do.
    let buffer = Buffer.alloc(0);
    
    client.on('error', (err) => {}); // Ignore connection errors

    const onData = (chunk) => {
        buffer = Buffer.concat([buffer, chunk]);
        
        // Loop to process packets in buffer
        while (true) {
            const varInt = readVarInt(buffer);
            if (!varInt) break; // Need more data for length
            
            const packetLen = varInt.value;
            const prefixLen = varInt.length;
            const fullLen = prefixLen + packetLen;
            
            if (buffer.length < fullLen) break; // Need more data for body
            
            // Extract Packet
            const packet = buffer.subarray(0, fullLen);
            const body = buffer.subarray(prefixLen); // ID + Data
            const idVar = readVarInt(body);
            if (!idVar) { break; } // Should not happen if packetLen correct
            
            const packetID = idVar.value;
            const payload = body.subarray(idVar.length);
            
            // Logic
            if (step === 0 && packetID === 0x00) {
                // Handshake
                // ID | Proto | Addr | Port | NextState
                let ptr = 0;
                const proto = readVarInt(payload, ptr); ptr += proto.length;
                const addrLen = readVarInt(payload, ptr); ptr += addrLen.length;
                ptr += addrLen.value; // Skip Address
                ptr += 2; // Skip Port
                const nextState = readVarInt(payload, ptr);
                
                if (nextState) {
                    handshakeData = packet; // Save handshake to fwd later
                    if (nextState.value === 1) {
                        // STATUS
                        step = 2; // Expect Status Request (0x00) next
                    } else if (nextState.value === 2) {
                        // LOGIN
                        step = 3; // Expect Login Start (0x00) next
                    }
                }
                // Convert buffer data to processed
                buffer = buffer.subarray(fullLen);
                
            } else if (step === 2 && packetID === 0x00) {
                // Status Request -> Send JSON Response
                const statusStr = (cachedStatus === 'running') ? "§aOnline" : "§cOffline";
                const motd = (cachedStatus === 'running') 
                    ? config.motd.line1 + "\n" + config.motd.line2 
                    : "§cSleeping... Join to Wake up!";

                const respObj = {
                    version: { name: statusStr, protocol: 767 }, // 1.21.1
                    players: { max: 100, online: 0 },
                    description: { text: motd }
                };
                client.write(createPacket(0x00, writeString(JSON.stringify(respObj))));
                
                step = 4; // Expect Ping
                buffer = buffer.subarray(fullLen);

            } else if (step === 4 && packetID === 0x01) {
                // Ping -> Pong
                client.write(createPacket(0x01, payload)); // Echo payload
                client.end();
                return;

            } else if (step === 3 && packetID === 0x00) {
                // Login Start -> DECISION TIME
                // Check Status
                if (cachedStatus !== 'running') {
                    if (cachedStatus === 'stopped') startServer(BACKEND.instanceId);
                    
                    const msg = { text: "§5§lPurple Kingdom\n\n§eServer is waking up! 😴\n\n§7Please wait §f30-60 seconds... \n§7Then join again!" };
                    client.write(createPacket(0x00, writeString(JSON.stringify(msg))));
                    client.end();
                    return;
                }
                
                // Server Running -> PIPE
                console.log("Backing running. Piping...");
                
                // We stop sniffing.
                client.removeListener('data', onData);
                
                const backend = net.createConnection({ host: BACKEND.host, port: BACKEND.port });
                
                backend.on('connect', () => {
                   // 1. Send Handshake
                   backend.write(handshakeData);
                   // 2. Send Login Start (current packet)
                   backend.write(packet);
                   // 3. Send any leftover buffer
                   const leftover = buffer.subarray(fullLen);
                   if (leftover.length > 0) backend.write(leftover);
                   
                   // 4. Pipe rest
                   client.pipe(backend).pipe(client);
                });
                
                backend.on('error', err => {
                    console.error("Backend connect error:", err.message);
                    client.end();
                });
                backend.on('close', () => client.end());
                client.on('close', () => backend.end());
                
                return; // Stop processing loop
            } else {
                // Unknown packet or state, ignore/buffer
                buffer = buffer.subarray(fullLen);
            }
        }
    };

    client.on('data', onData);
});

server.listen(PROXY_PORT);
