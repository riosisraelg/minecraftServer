#!/bin/bash

# EC2 Deployment Script for Minecraft Proxy
# Run this script on your EC2 instance after cloning the repository

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m'

print_header() {
    echo -e "${PURPLE}╔══════════════════════════════════════════════╗${NC}"
    echo -e "${PURPLE}║  🚀 Minecraft Proxy Deployment Script      ║${NC}"
    echo -e "${PURPLE}╚══════════════════════════════════════════════╝${NC}"
    echo ""
}

print_header

# Step 1: Check if we're in the right directory
if [ ! -f "package.json" ]; then
    echo -e "${RED}Error: package.json not found!${NC}"
    echo -e "${YELLOW}Please run this script from the proxy directory${NC}"
    exit 1
fi

# Step 2: Install Node.js dependencies
echo -e "${BLUE}Step 1/3: Installing Node.js dependencies...${NC}"
npm install
echo -e "${GREEN}✓ Dependencies installed${NC}\n"

# Step 3: Ensure scripts are executable
chmod +x manage-proxy.sh
chmod +x QUICKSTART.sh

# Step 4: Use manage-proxy to start the service
echo -e "${BLUE}Step 2/3: Starting Proxy via manage-proxy.sh...${NC}"
./manage-proxy.sh start

# Step 5: Setup startup
echo -e "${BLUE}Step 3/3: Configuring auto-start...${NC}"
./manage-proxy.sh startup

# Show Final Status
echo ""
echo -e "${PURPLE}╔══════════════════════════════════════════════╗${NC}"
echo -e "${PURPLE}║  ✅ Deployment Complete!                    ║${NC}"
echo -e "${PURPLE}╚══════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${GREEN}🎮 Your Minecraft proxy is now running!${NC}"
echo ""
echo -e "${BLUE}Useful Commands:${NC}"
echo "  • View logs:       ./manage-proxy.sh logs"
echo "  • Restart proxy:   ./manage-proxy.sh restart"
echo "  • Check status:    ./manage-proxy.sh status"
echo ""
