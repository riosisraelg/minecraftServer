#!/usr/bin/env bash

# Minecraft Server Setup Selector
# This script asks the user which version they want and runs the corresponding setup script.

server_install_packages() {
    if command -v java &> /dev/null; then
        echo "✅ Dependencies already installed. Skipping package update."
        sleep 1
        return
    fi

    echo "📦 Installing system packages..."
    sleep 1
    sudo yum update -y
    sudo yum install -y java-17-amazon-corretto-devel
    sudo yum install -y java-21-amazon-corretto-devel
    sudo yum install -y screen
    sudo yum install -y git
    echo "✅ Packages installed!"
    sleep 1
}
server_install_packages 

echo "========================================="
echo "   🚀 Minecraft Server Setup Wizard 🚀   "
echo "========================================="
echo "Select Server Type:"
echo "1) Vanilla (Performance & Latest Features)"
echo "2) Forge (Modding Support)"
echo ""
read -p "Enter choice [1-2]: " choice

# Get the directory where this script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

if [ "$choice" -eq 1 ]; then
    echo "➡️  Launching Vanilla Setup..."
    sleep 1
    TARGET_SCRIPT="${SCRIPT_DIR}/main-mcServer-vanilla.sh"
    
    if [ -f "$TARGET_SCRIPT" ]; then
        chmod +x "$TARGET_SCRIPT"
        "$TARGET_SCRIPT"
    else
        echo "❌ Error: main-mcServer-vanilla.sh not found at: $TARGET_SCRIPT"
        exit 1
    fi

elif [ "$choice" -eq 2 ]; then
    echo "➡️  Launching Forge Setup..."
    sleep 1
    TARGET_SCRIPT="${SCRIPT_DIR}/main-mcServer-forge.sh"

    if [ -f "$TARGET_SCRIPT" ]; then
        chmod +x "$TARGET_SCRIPT"
        "$TARGET_SCRIPT"
    else
        echo "❌ Error: main-mcServer-forge.sh not found at: $TARGET_SCRIPT"
        exit 1
    fi

else
    echo "❌ Invalid choice. Exiting."
    exit 1
fi



