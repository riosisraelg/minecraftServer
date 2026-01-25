#!/bin/bash

# ============================================================================
# 🛠️ Server Environment Setup
# Installs all necessary system dependencies for both:
# 1. Minecraft Servers (Java, Screen)
# 2. Proxy Server (Node.js, PM2)
# ============================================================================

set -e

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${BLUE}🔧 Starting Environment Setup...${NC}"

# Detect OS
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$NAME
fi

install_yum() {
    echo -e "${YELLOW}Detected YUM package manager. Installing packages...${NC}"
    sudo yum update -y
    
    # Minecraft Deps
    echo "Installing Java & Tools..."
    sudo yum install -y java-17-amazon-corretto-devel java-21-amazon-corretto-devel screen git
    
    # Proxy Deps (Node.js)
    if ! command -v node &> /dev/null; then
        echo "Installing Node.js..."
        sudo yum install -y nodejs npm
    else
        echo "Node.js is already installed."
    fi
}

install_apt() {
    echo -e "${YELLOW}Detected APT package manager. Installing packages...${NC}"
    sudo apt-get update
    
    # Minecraft Deps
    echo "Installing Java & Tools..."
    sudo apt-get install -y openjdk-17-jdk screen git curl
    
    # Proxy Deps (Node.js)
    if ! command -v node &> /dev/null; then
        echo "Installing Node.js..."
        # NodeSource setup for newer node versions if needed, but default might suffice
        sudo apt-get install -y nodejs npm
    else
        echo "Node.js is already installed."
    fi
}

# Run Installation
if command -v yum &> /dev/null; then
    install_yum
elif command -v apt-get &> /dev/null; then
    install_apt
else
    echo -e "${RED}Error: Unsupported package manager. Please install Java 17, Node.js 18+, screen, and git manually.${NC}"
    exit 1
fi

# Global NPM Tools
echo -e "${BLUE}Installing Global NPM Tools...${NC}"
sudo npm install -g pm2

echo -e "${GREEN}✅ Environment Setup Complete!${NC}"
echo ""
echo -e "Next Steps:"
echo -e "1. Run ${YELLOW}./mc-manager.sh${NC} to create/manage servers."
echo -e "2. Go to ${YELLOW}../proxy${NC} and run ${YELLOW}./deploy.sh${NC} to start the proxy."
