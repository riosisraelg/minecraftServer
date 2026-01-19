#!/usr/bin/env bash

# ============================================================================
# Minecraft Server Setup Wizard
# Entry point that installs dependencies and launches the unified setup script
# ============================================================================

install_dependencies() {
    if command -v java &> /dev/null; then
        echo "✅ Java already installed. Skipping package update."
        return
    fi

    echo "📦 Installing system packages..."
    sudo yum update -y
    sudo yum install -y java-17-amazon-corretto-devel java-21-amazon-corretto-devel screen git
    echo "✅ Packages installed!"
}

main() {
    install_dependencies
    
    # Get the directory where this script is located
    SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
    TARGET_SCRIPT="${SCRIPT_DIR}/main-mcServer.sh"
    
    if [ -f "$TARGET_SCRIPT" ]; then
        chmod +x "$TARGET_SCRIPT"
        "$TARGET_SCRIPT"
    else
        echo "❌ Error: main-mcServer.sh not found at: $TARGET_SCRIPT"
        echo "   Please ensure all scripts are in the same directory."
        exit 1
    fi
}

main "$@"
