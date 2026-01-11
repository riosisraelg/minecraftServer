const mc = require('minecraft-protocol');

const config = require('./config.json');
const PORT = config.proxy_port;

console.log(`Pinging localhost:${PORT}...`);

mc.ping({
    host: 'localhost',
    port: PORT,
    version: '1.20.1' // Match the proxy version
}, (err, response) => {
    if (err) {
        console.error("Ping failed:", err);
        process.exit(1);
    }
    console.log("Ping successful!");
    console.log("Version:", response.version.name);
    console.log("MOTD:", response.description);
    process.exit(0);
});
