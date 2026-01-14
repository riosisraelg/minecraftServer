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

echo -e "${BLUE}Step 1/6: Installing Node.js dependencies...${NC}"
npm install
echo -e "${GREEN}✓ Dependencies installed${NC}\n"

# Step 2: Install PM2 globally
echo -e "${BLUE}Step 2/6: Installing PM2 process manager...${NC}"
if ! command -v pm2 &> /dev/null; then
    sudo npm install -g pm2
    echo -e "${GREEN}✓ PM2 installed${NC}\n"
else
    echo -e "${GREEN}✓ PM2 already installed${NC}\n"
fi

# Step 3: Create logs directory
echo -e "${BLUE}Step 3/6: Creating logs directory...${NC}"
mkdir -p logs
echo -e "${GREEN}✓ Logs directory created${NC}\n"

# Step 4: Stop any existing proxy processes
echo -e "${BLUE}Step 4/6: Cleaning up existing processes...${NC}"
pm2 stop minecraft-proxy 2>/dev/null || true
pm2 delete minecraft-proxy 2>/dev/null || true
pm2 stop proxy 2>/dev/null || true
pm2 delete proxy 2>/dev/null || true

# Kill any process using port 25599
PIDS=$(sudo lsof -t -i:25599 2>/dev/null || true)
if [ -n "$PIDS" ]; then
    echo -e "${YELLOW}Killing processes on port 25599...${NC}"
    sudo kill -9 $PIDS
    sleep 1
fi
echo -e "${GREEN}✓ Cleanup complete${NC}\n"

# Step 5: Start the proxy
echo -e "${BLUE}Step 5/6: Starting Minecraft Proxy...${NC}"
pm2 start ecosystem.config.js
pm2 save
echo -e "${GREEN}✓ Proxy started successfully${NC}\n"

# Step 6: Setup PM2 to start on boot
echo -e "${BLUE}Step 6/6: Configuring auto-start on boot...${NC}"
echo -e "${YELLOW}Note: You may need to run the following command manually:${NC}"
pm2 startup
echo -e "${GREEN}✓ Setup complete${NC}\n"

# Show status
echo -e "${PURPLE}╔══════════════════════════════════════════════╗${NC}"
echo -e "${PURPLE}║  ✅ Deployment Complete!                    ║${NC}"
echo -e "${PURPLE}╚══════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${BLUE}Proxy Status:${NC}"
pm2 list

echo ""
echo -e "${BLUE}Useful Commands:${NC}"
echo "  • View logs:       pm2 logs minecraft-proxy"
echo "  • Restart proxy:   ./manage-proxy.sh restart"
echo "  • Stop proxy:      ./manage-proxy.sh stop"
echo "  • Check status:    ./manage-proxy.sh status"
echo ""
echo -e "${GREEN}🎮 Your Minecraft proxy is now running!${NC}"
echo -e "${YELLOW}Connect to your server at: ${PURPLE}<EC2-PUBLIC-IP>:25599${NC}"
echo ""
