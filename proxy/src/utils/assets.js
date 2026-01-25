const fs = require("fs");
const path = require("path");

function loadServerIcon() {
    const iconPath = path.join(__dirname, "../../../assets/branding/server-icon.png");
    try {
        if (fs.existsSync(iconPath)) {
            const iconBuffer = fs.readFileSync(iconPath);
            return `data:image/png;base64,${iconBuffer.toString("base64")}`;
        }
    } catch (err) {
        console.error("⚠ Error loading server icon:", err.message);
    }
    return null;
}

module.exports = { loadServerIcon };
