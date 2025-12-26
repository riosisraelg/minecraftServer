#!/usr/bin/env bash

# ===== CONFIG =====
MC_USER="minecraft"
MC_DIR="/opt/minecraft"
MC_SERVICE_NAME="minecraft"

SERVER_TYPE=0

VANILLA_MC_VERSION="1.21.11"
VANILLA_MC_DIR="${MC_DIR}/vanilla"
VANILLA_MC_INSTALLER_URL="https://piston-data.mojang.com/v1/objects/64bb6d763bed0a9f1d632ec347938594144943ed/server.jar"
VANILLA_MC_INSTALLER_JAR="vanilla-mcServer-${VANILLA_MC_VERSION}-installer.jar"

FORGE_MC_VERSION="1.20.1-47.4.10"
FORGE_MC_DIR="${MC_DIR}/forge"
FORGE_MC_INSTALLER_URL="https://maven.minecraftforge.net/net/minecraftforge/forge/1.20.1-47.4.10/forge-1.20.1-47.4.10-installer.jar"
FORGE_MC_INSTALLER_JAR="forge-mcServer-${FORGE_MC_VERSION}-installer.jar"

SCREEN_NAME="minecraft"

# ===== FUNCTIONS =====
server_install_packages() {
    sudo yum update -y
    sudo yum install -y java-17-amazon-corretto-devel
    sudo yum install -y java-21-amazon-corretto-devel
    sudo yum install -y screen
    sudo yum install -y git
}

select_server_type() {
    echo "Select Server Type:"
    echo "1) Vanilla"
    echo "2) Forge"
    read -p "Enter choice [1-2]: " choice
    case $choice in
        1) SERVER_TYPE=1 ;;
        2) SERVER_TYPE=2 ;;
        *) echo "Invalid choice"; exit 1 ;;
    esac
}

mc_server_environment() {
    if [ ! -d "${MC_DIR}" ]; then
        sudo mkdir -p "${MC_DIR}"
        id -u "${MC_USER}" &>/dev/null || sudo useradd -m "${MC_USER}"
        sudo chown -R "${MC_USER}:${MC_USER}" "${MC_DIR}"
    fi

    sudo mkdir -p "${VANILLA_MC_DIR}" "${FORGE_MC_DIR}"
    sudo chown -R "${MC_USER}:${MC_USER}" "${VANILLA_MC_DIR}" "${FORGE_MC_DIR}"

    if [ "$SERVER_TYPE" -eq 1 ]; then
        cd ${VANILLA_MC_DIR}    
        if [ ! -f "${VANILLA_MC_DIR}/${VANILLA_MC_INSTALLER_JAR}" ]; then
            # Download installer
            sudo -u "${MC_USER}" wget "${VANILLA_MC_INSTALLER_URL}" -O "${VANILLA_MC_DIR}/${VANILLA_MC_INSTALLER_JAR}"
            
            # Install server (Initial run to generate files)
            sudo -u "${MC_USER}" java -Xmx1024M -Xms1024M -jar "${VANILLA_MC_DIR}/${VANILLA_MC_INSTALLER_JAR}" nogui
            sleep 2
            sudo -u "${MC_USER}" sed -i 's/eula=false/eula=true/' eula.txt


            # Create start and stop scripts
            sudo -u "${MC_USER}" bash -c "echo '-Xmx1024M -Xms1024M' > user_jvm_args.txt"
            
            # Start script
            cat <<EOF | sudo -u "${MC_USER}" tee start > /dev/null
#!/bin/bash
java @user_jvm_args.txt -jar ${VANILLA_MC_DIR}/${VANILLA_MC_INSTALLER_JAR} nogui
EOF
            sudo chmod +x start

            # Stop script
            cat <<EOF | sudo -u "${MC_USER}" tee stop > /dev/null
#!/bin/bash
kill -9 \$(ps -ef | pgrep -f "java")
EOF
            sudo chmod +x stop
            sleep 1
            
            # Create service with proper sudo permissions
            sudo bash -c "cat > /etc/systemd/system/vanilla-minecraft.service <<EOF
[Unit]
Description=Vanilla Minecraft Server
Wants=network-online.target
[Service]
User=minecraft
WorkingDirectory=/opt/minecraft/vanilla
ExecStart=/opt/minecraft/vanilla/start
StandardInput=null
[Install]
WantedBy=multi-user.target
EOF"
            sudo systemctl daemon-reload
            sudo systemctl enable vanilla-minecraft.service
            sudo systemctl start vanilla-minecraft.service
        fi

    elif [ "$SERVER_TYPE" -eq 2 ]; then
        cd ${FORGE_MC_DIR}
        if [ ! -f "${FORGE_MC_DIR}/${FORGE_MC_INSTALLER_JAR}" ]; then
            # Download installer
            sudo -u "${MC_USER}" wget "${FORGE_MC_INSTALLER_URL}" -O "${FORGE_MC_DIR}/${FORGE_MC_INSTALLER_JAR}"

            # Install server
            sudo -u "${MC_USER}" java -Xmx1024M -Xms1024M -jar "${FORGE_MC_DIR}/${FORGE_MC_INSTALLER_JAR}" nogui --installServer
            sleep 2
            sudo -u "${MC_USER}" sed -i 's/eula=false/eula=true/' eula.txt  
            
            # Create start and stop scripts
            sudo -u "${MC_USER}" bash -c "echo '-Xmx1024M -Xms1024M' > user_jvm_args.txt"
            
            # Start script
            cat <<EOF | sudo -u "${MC_USER}" tee start > /dev/null
#!/bin/bash
java @user_jvm_args.txt @libraries/net/minecraftforge/forge/1.20.1-47.4.10/unix_args.txt "\$@"
EOF
            sudo chmod +x start

            # Stop script
            cat <<EOF | sudo -u "${MC_USER}" tee stop > /dev/null
#!/bin/bash
kill -9 \$(ps -ef | pgrep -f "java")
EOF
            sudo chmod +x stop
            sleep 1
            
            # Create service with proper sudo permissions
            sudo bash -c "cat > /etc/systemd/system/forge-minecraft.service <<EOF
[Unit]
Description=Forge Minecraft Server
Wants=network-online.target
[Service]
User=minecraft
WorkingDirectory=/opt/minecraft/forge
ExecStart=/opt/minecraft/forge/start
StandardInput=null
[Install]
WantedBy=multi-user.target
EOF"
            sudo systemctl daemon-reload
            sudo systemctl enable forge-minecraft.service
            sudo systemctl start forge-minecraft.service
        fi
    fi
}


main() {
    server_install_packages
    select_server_type
    mc_server_environment
}
main



