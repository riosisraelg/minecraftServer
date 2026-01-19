/**
 * Minecraft Protocol Utilities
 * 
 * Common functions for reading/writing Minecraft protocol data types.
 * Extracted from index.js to enable reuse and better testing.
 */

/**
 * Read a VarInt from a buffer at the given offset.
 * @param {Buffer} buffer - The buffer to read from
 * @param {number} offset - Starting offset
 * @returns {Object|null} - { value, length } or null if incomplete
 */
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

/**
 * Write a VarInt to a buffer.
 * @param {number} value - The value to encode
 * @returns {Buffer} - Encoded VarInt buffer
 */
function writeVarInt(value) {
    const bytes = [];
    
    while (true) {
        if ((value & ~0x7F) === 0) {
            bytes.push(value);
            break;
        } else {
            bytes.push((value & 0x7F) | 0x80);
            value >>>= 7;
        }
    }
    
    return Buffer.from(bytes);
}

/**
 * Write a string with length prefix (VarInt + UTF-8 bytes).
 * @param {string} str - The string to encode
 * @returns {Buffer} - Length-prefixed string buffer
 */
function writeString(str) {
    const len = writeVarInt(Buffer.byteLength(str));
    return Buffer.concat([len, Buffer.from(str, 'utf8')]);
}

/**
 * Create a Minecraft packet with ID and data.
 * @param {number} packetId - Packet ID
 * @param {Buffer} dataBuffer - Packet data
 * @returns {Buffer} - Complete packet with length prefix
 */
function createPacket(packetId, dataBuffer) {
    const id = writeVarInt(packetId);
    const length = writeVarInt(id.length + dataBuffer.length);
    return Buffer.concat([length, id, dataBuffer]);
}

/**
 * Parse a handshake packet to extract next state.
 * @param {Buffer} payload - Packet payload (after ID)
 * @returns {Object|null} - { protocolVersion, serverAddress, port, nextState }
 */
function parseHandshake(payload) {
    let ptr = 0;
    
    const proto = readVarInt(payload, ptr);
    if (!proto) return null;
    ptr += proto.length;
    
    const addrLen = readVarInt(payload, ptr);
    if (!addrLen) return null;
    ptr += addrLen.length;
    
    const serverAddress = payload.subarray(ptr, ptr + addrLen.value).toString('utf8');
    ptr += addrLen.value;
    
    if (ptr + 2 > payload.length) return null;
    const port = payload.readUInt16BE(ptr);
    ptr += 2;
    
    const nextState = readVarInt(payload, ptr);
    if (!nextState) return null;
    
    return {
        protocolVersion: proto.value,
        serverAddress,
        port,
        nextState: nextState.value
    };
}

module.exports = {
    readVarInt,
    writeVarInt,
    writeString,
    createPacket,
    parseHandshake
};
