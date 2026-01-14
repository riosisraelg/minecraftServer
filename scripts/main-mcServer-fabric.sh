#!/usr/bin/env bash

# ===== CONFIG =====
MC_USER="minecraft"
MC_DIR="/opt/minecraft"
MC_TYPE="fabric"
FABRIC_MC_VERSION="1.21.1" # Matching proxy config
FABRIC_LOADER_VERSION="0.16.9"
FABRIC_INSTALLER_VERSION="1.0.1"
FABRIC_INSTALLER_URL="https://maven.fabricmc.net/net/fabricmc/fabric-installer/${FABRIC_INSTALLER_VERSION}/fabric-installer-${FABRIC_INSTALLER_VERSION}.jar"
FABRIC_INSTALLER_JAR="fabric-installer.jar"

JVM_ARGS="-Xmx2048M -Xms1024M"
JVM_MX="2048M"
JVM_MS="1024M"

# Global variables to be set by ask_naming_details
MC_SERVICE_NAME=""
FABRIC_MC_DIR=""

# ===== FUNCTIONS =====
intro_message() {
    echo "========================================="
    echo "      🚀 Fabric Minecraft Setup 🚀       "
    echo "========================================="
    sleep 1
    echo " This script automates the installation of a Fabric Minecraft server."
    echo "========================================="
    sleep 1
}

ask_jvm_args() {
    echo "Configure RAM allocation (Examples: 1024M, 2048M, 4096M)"
    read -p "Enter JVM max memory (default 2048M): " user_mx
    JVM_MX=${user_mx:-"2048M"}
    read -p "Enter JVM min memory (default 1024M): " user_ms
    JVM_MS=${user_ms:-"1024M"}
    
    # Validation: Extract numbers to compare
    mx_int=$(echo "$JVM_MX" | tr -cd '0-9')
    ms_int=$(echo "$JVM_MS" | tr -cd '0-9')
    
    if [[ "$JVM_MX" == *"G"* ]]; then mx_int=$((mx_int * 1024)); fi
    if [[ "$JVM_MS" == *"G"* ]]; then ms_int=$((ms_int * 1024)); fi
    
    if [ "$ms_int" -gt "$mx_int" ]; then
        echo "⚠️  WARNING: Min memory ($JVM_MS) is larger than Max memory ($JVM_MX)."
        echo "   Auto-correcting: Setting Min memory to match Max memory ($JVM_MX)."
        JVM_MS="$JVM_MX"
    fi
    
    JVM_ARGS="-Xmx${JVM_MX} -Xms${JVM_MS}"
    echo "✅ Memory settings: $JVM_ARGS"
}

ask_naming_details() {
    echo "========================================="
    echo "   🏷️  Server Identification"
    echo "========================================="
    echo "   Choose Game Mode:"
    echo "   1) Survival (Default)"
    echo "   2) Creative"
    echo "   3) Hardcore"
    read -p "   Enter choice [1-3]: " mode_choice
    case "$mode_choice" in
        2) GAMEMODE="creative" ;;
        3) GAMEMODE="hardcore" ;;
        *) GAMEMODE="survival" ;;
    esac

    echo "🔍 Scanning for existing '${MC_TYPE} ${FABRIC_MC_VERSION} (${GAMEMODE})' servers..."
    existing_services=($(ls /etc/systemd/system/[0-9][0-9]-${MC_TYPE}-${FABRIC_MC_VERSION}-${GAMEMODE}.service 2>/dev/null))
    count=${#existing_services[@]}

    SELECTED_ACTION=""
    
    if [ $count -eq 0 ]; then
        echo "   No existing servers found."
        read -p "   Create a new server? [Y/n]: " create_confirm
        if [[ "$create_confirm" =~ ^[Nn]$ ]]; then
            echo "❌ Operation cancelled."
            exit 0
        fi
        SELECTED_ACTION="CREATE"
    else
        echo "   Found $count existing server(s):"
        for svc in "${existing_services[@]}"; do
            basename "$svc" .service
        done
        echo ""
        echo "   Choose Action:"
        echo "   [C] Create New"
        echo "   [R] Reinstall Existing (Clean Wipe)"
        echo "   [D] Delete Existing"
        read -p "   Enter choice [C/R/D]: " action_choice
        
        case "$action_choice" in
            [Cc]*) SELECTED_ACTION="CREATE" ;;
            [Rr]*) SELECTED_ACTION="REINSTALL" ;;
            [Dd]*) SELECTED_ACTION="DELETE" ;;
            *) echo "❌ Invalid choice. Exiting."; exit 1 ;;
        esac
    fi

    # === LOGIC HANDLERS ===
    
    if [ "$SELECTED_ACTION" == "DELETE" ]; then
        read -p "⚠️  ENTER FULL SERVICE NAME to DELETE: " target_name
        if [[ ! -f "/etc/systemd/system/${target_name}.service" ]]; then
             echo "❌ Service '$target_name' not found."
             exit 1
        fi
        
        if [[ "$target_name" != *"-${MC_TYPE}-${FABRIC_MC_VERSION}-${GAMEMODE}" ]]; then
             echo "❌ Safety Check Failed: Name mismatch."
             exit 1
        fi

        echo "🛑 Stopping service..."
        sudo systemctl stop "$target_name"
        sudo systemctl disable "$target_name"
        
        target_dir=$(systemctl show -p WorkingDirectory --value "$target_name")
        
        echo "🗑️  Deleting service file..."
        sudo rm "/etc/systemd/system/${target_name}.service"
        sudo systemctl daemon-reload
        
        if [ -d "$target_dir" ]; then
            echo "🗑️  Deleting server directory: $target_dir"
            sudo rm -rf "$target_dir"
        fi
        
        echo "✅ Server '$target_name' deleted successfully."
        exit 0
    fi

    if [ "$SELECTED_ACTION" == "REINSTALL" ]; then
        read -p "⚠️  ENTER FULL SERVICE NAME to REINSTALL: " target_name
        if [[ ! -f "/etc/systemd/system/${target_name}.service" ]]; then
             echo "❌ Service '$target_name' not found."
             exit 1
        fi

        SERVER_ID=${target_name:0:2}
        
        echo "🛑 preparing reinstall for ID: $SERVER_ID ..."
        sudo systemctl stop "$target_name"
        sudo systemctl disable "$target_name"
        
        target_dir=$(systemctl show -p WorkingDirectory --value "$target_name")
        echo "🗑️  Cleaning up old configuration..."
        sudo rm "/etc/systemd/system/${target_name}.service"
        sudo systemctl daemon-reload
        if [ -d "$target_dir" ]; then
             echo "🗑️  Wiping old directory: $target_dir"
             sudo rm -rf "$target_dir"
        fi
    fi

    if [ "$SELECTED_ACTION" == "CREATE" ]; then
        for i in {1..99}; do
            id_str=$(printf "%02d" $i)
            candidate_name="${id_str}-${MC_TYPE}-${FABRIC_MC_VERSION}-${GAMEMODE}"
            if [[ ! -f "/etc/systemd/system/${candidate_name}.service" ]]; then
                SERVER_ID=$id_str
                break
            fi
        done
        if [ -z "$SERVER_ID" ]; then
            echo "❌ No free IDs available."
            exit 1
        fi
    fi

    TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    MC_SERVICE_NAME="${SERVER_ID}-${MC_TYPE}-${FABRIC_MC_VERSION}-${GAMEMODE}"
    FABRIC_MC_DIR="${MC_DIR}/${SERVER_ID}-${MC_TYPE}-${FABRIC_MC_VERSION}-${GAMEMODE}-${TIMESTAMP}"
    
    echo "✅ Configuration Set:"
    echo "   ID: $SERVER_ID"
    echo "   Service: $MC_SERVICE_NAME"
    echo "   Dir: $FABRIC_MC_DIR"
    echo "========================================="
}

mc_server_environment() {
    echo "👤 Setting up user and directories..."
    if [ ! -d "${MC_DIR}" ]; then
        sudo mkdir -p "${MC_DIR}"
        id -u "${MC_USER}" &>/dev/null || sudo useradd -m "${MC_USER}"
        sudo chown -R "${MC_USER}:${MC_USER}" "${MC_DIR}"
    fi

    sudo mkdir -p "${FABRIC_MC_DIR}"
    sudo chown -R "${MC_USER}:${MC_USER}" "${FABRIC_MC_DIR}"

    cd ${FABRIC_MC_DIR}    
    
    if [ ! -f "/etc/systemd/system/${MC_SERVICE_NAME}.service" ]; then
        
        if [ ! -f "${FABRIC_MC_DIR}/${FABRIC_INSTALLER_JAR}" ]; then
             echo "⬇️ Downloading Fabric Installer..."
             sudo -u "${MC_USER}" wget "${FABRIC_INSTALLER_URL}" -O "${FABRIC_MC_DIR}/${FABRIC_INSTALLER_JAR}"
        fi
        
        echo "🔨 Installing Fabric Server..."
        sudo -u "${MC_USER}" java -jar "${FABRIC_MC_DIR}/${FABRIC_INSTALLER_JAR}" server -mcversion "${FABRIC_MC_VERSION}" -loader "${FABRIC_LOADER_VERSION}" -downloadMinecraft
        sleep 2
        
        sudo -u "${MC_USER}" sed -i 's/eula=false/eula=true/' eula.txt
        # Configure properties for Proxy support
        sudo -u "${MC_USER}" sed -i 's/online-mode=true/online-mode=false/' server.properties
        sudo -u "${MC_USER}" sed -i 's/enforce-secure-profile=true/enforce-secure-profile=false/' server.properties
        if [[ $? -eq 0 ]] && grep -q "eula=true" eula.txt; then
            echo "📜 EULA accepted"
        else
            # Try running once to generate EULA if it doesn't exist
            echo "⚠️ Generating EULA..."
            sudo -u "${MC_USER}" java -jar fabric-server-launch.jar nogui &
            PID=$!
            sleep 10
            kill $PID
            sudo -u "${MC_USER}" sed -i 's/eula=false/eula=true/' eula.txt
        fi

        echo "📝 Creating start/stop scripts..."
        sudo -u "${MC_USER}" bash -c "echo '${JVM_ARGS}' > ${FABRIC_MC_DIR}/user_jvm_args.txt"
        
        # START SCRIPT
        cat <<EOF | sudo -u "${MC_USER}" tee start > /dev/null
#!/bin/bash
java @user_jvm_args.txt -jar fabric-server-launch.jar nogui
EOF
        sudo chmod +x start

        # STOP SCRIPT
        cat <<EOF | sudo -u "${MC_USER}" tee stop > /dev/null
#!/bin/bash
sudo -u "${MC_USER}" pkill -TERM -f "${FABRIC_MC_DIR}"
while pgrep -f "${FABRIC_MC_DIR}" > /dev/null; do
    echo "Saving world and stopping..."
    sleep 1
done
echo "Server stopped."
EOF
        sudo chmod +x stop
        
        echo "⚙️ Configuring systemd service..."
        sudo bash -c "cat > /etc/systemd/system/${MC_SERVICE_NAME}.service <<EOF
[Unit]
Description=Fabric Minecraft Server
Wants=network-online.target
[Service]
User=${MC_USER}
WorkingDirectory=${FABRIC_MC_DIR}
ExecStart=${FABRIC_MC_DIR}/start
StandardInput=null
[Install]
WantedBy=multi-user.target
EOF"
        sudo systemctl daemon-reload
        sudo systemctl enable ${MC_SERVICE_NAME}.service
        sudo systemctl start ${MC_SERVICE_NAME}.service
        
        echo "🔒 Enforcing permissions..."
        sudo chown -R ${MC_USER}:${MC_USER} ${MC_DIR}
        
        echo ""
        echo "========================================="
        echo "      🚀 INSTALLATION SUCCESSFUL 🚀      "
        echo "========================================="
        echo "| Version    | Fabric ${FABRIC_MC_VERSION} (Loader ${FABRIC_LOADER_VERSION}) |"
        echo "| Directory  | ${FABRIC_MC_DIR} |"
        echo "| Service    | ${MC_SERVICE_NAME} |"
        echo "========================================="
    else
        echo "⚠️ Service ${MC_SERVICE_NAME} already exists."
    fi
}

main() {
    intro_message
    ask_naming_details
    ask_jvm_args
    mc_server_environment
}
main
