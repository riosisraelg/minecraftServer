#!/bin/bash

# Minecraft Proxy Management Script
# This script helps manage the proxy server on EC2

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

print_header() {
    echo -e "${PURPLE}╔════════════════════════════════════════╗${NC}"
    echo -e "${PURPLE}║  🎮 Minecraft Proxy Manager          ║${NC}"
    echo -e "${PURPLE}╚════════════════════════════════════════╝${NC}"
    echo ""
}

check_pm2() {
    if ! command -v pm2 &> /dev/null; then
        echo -e "${YELLOW}PM2 is not installed. Installing...${NC}"
        sudo npm install -g pm2
    fi
}

kill_port_25599() {
    echo -e "${YELLOW}Checking for processes on port 25599...${NC}"
    
    # Find processes using port 25599
    PIDS=$(sudo lsof -t -i:25599 2>/dev/null || true)
    
    if [ -n "$PIDS" ]; then
        echo -e "${RED}Found processes using port 25599: $PIDS${NC}"
        echo -e "${YELLOW}Killing processes...${NC}"
        sudo kill -9 $PIDS
        sleep 1
        echo -e "${GREEN}✓ Processes killed${NC}"
    else
        echo -e "${GREEN}✓ Port 25599 is free${NC}"
    fi
}

start_proxy() {
    print_header
    echo -e "${BLUE}Starting Minecraft Proxy...${NC}"
    
    check_pm2
    kill_port_25599
    
    # Stop any existing proxy processes
    pm2 stop minecraft-proxy 2>/dev/null || true
    pm2 delete minecraft-proxy 2>/dev/null || true
    pm2 stop proxy 2>/dev/null || true
    pm2 delete proxy 2>/dev/null || true
    
    # Create logs directory
    mkdir -p logs
    
    # Start the proxy with PM2 using ecosystem config
    pm2 start ecosystem.config.js
    
    # Save PM2 process list
    pm2 save
    
    echo ""
    echo -e "${GREEN}✓ Proxy started successfully!${NC}"
    echo -e "${BLUE}Run '${YELLOW}pm2 logs minecraft-proxy${BLUE}' to view logs${NC}"
    echo ""
    
    # Show status
    pm2 list
}

stop_proxy() {
    print_header
    echo -e "${YELLOW}Stopping Minecraft Proxy...${NC}"
    
    pm2 stop minecraft-proxy 2>/dev/null || true
    echo -e "${GREEN}✓ Proxy stopped${NC}"
    pm2 list
}

restart_proxy() {
    print_header
    echo -e "${BLUE}Restarting Minecraft Proxy...${NC}"
    
    kill_port_25599
    pm2 restart minecraft-proxy 2>/dev/null || start_proxy
    
    echo -e "${GREEN}✓ Proxy restarted${NC}"
    pm2 list
}

status_proxy() {
    print_header
    check_pm2
    pm2 list
    echo ""
    echo -e "${BLUE}Port 25599 status:${NC}"
    sudo lsof -i :25599 || echo -e "${GREEN}Port 25599 is free${NC}"
}

logs_proxy() {
    print_header
    echo -e "${BLUE}Showing logs (Ctrl+C to exit)...${NC}"
    pm2 logs minecraft-proxy
}

cleanup_all() {
    print_header
    echo -e "${RED}Cleaning up ALL proxy processes...${NC}"
    
    # Kill all processes on port 25599
    kill_port_25599
    
    # Remove all PM2 processes
    pm2 stop all 2>/dev/null || true
    pm2 delete all 2>/dev/null || true
    
    echo -e "${GREEN}✓ All processes cleaned up${NC}"
}

setup_startup() {
    print_header
    echo -e "${BLUE}Setting up PM2 to start on system boot...${NC}"
    
    check_pm2
    pm2 startup
    pm2 save
    
    echo -e "${GREEN}✓ PM2 startup configuration saved${NC}"
    echo -e "${YELLOW}Note: You may need to run the command shown above with sudo${NC}"
}

show_usage() {
    print_header
    echo -e "${BLUE}Usage:${NC}"
    echo "  ./manage-proxy.sh [command]"
    echo ""
    echo -e "${BLUE}Commands:${NC}"
    echo "  start      - Start the proxy server"
    echo "  stop       - Stop the proxy server"
    echo "  restart    - Restart the proxy server"
    echo "  status     - Show proxy status and port usage"
    echo "  logs       - Show proxy logs (live)"
    echo "  cleanup    - Remove all proxy processes and free port 25599"
    echo "  startup    - Configure PM2 to start on system boot"
    echo "  help       - Show this help message"
    echo ""
}

# Main script logic
case "$1" in
    start)
        start_proxy
        ;;
    stop)
        stop_proxy
        ;;
    restart)
        restart_proxy
        ;;
    status)
        status_proxy
        ;;
    logs)
        logs_proxy
        ;;
    cleanup)
        cleanup_all
        ;;
    startup)
        setup_startup
        ;;
    help|--help|-h|"")
        show_usage
        ;;
    *)
        echo -e "${RED}Unknown command: $1${NC}"
        echo ""
        show_usage
        exit 1
        ;;
esac
