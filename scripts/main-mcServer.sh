#!/usr/bin/env bash

# ============================================================================
# 🎮 Unified Minecraft Server Setup Script
# ============================================================================
# This script consolidates Fabric, Forge, and Vanilla server installations
# into a single parametrized script, eliminating code duplication.
# ============================================================================

# ===== GLOBAL CONFIG =====
MC_USER="minecraft"
MC_DIR="/opt/minecraft"

# Server type configurations (populated by select_server_type)
MC_TYPE=""
MC_VERSION=""
INSTALLER_URL=""
INSTALLER_JAR=""
START_CMD=""

# JVM Settings
JVM_ARGS="-Xmx2048M -Xms1024M"
JVM_MX="2048M"
JVM_MS="1024M"

# Runtime variables
MC_SERVICE_NAME=""
SERVER_DIR=""
GAMEMODE=""
SERVER_ID=""

# ===== SERVER TYPE DEFINITIONS =====
declare -A FABRIC_CONFIG=(
    [type]="fabric"
    [version]="1.21.1"
    [loader_version]="0.16.9"
    [installer_version]="1.0.1"
)

declare -A FORGE_CONFIG=(
    [type]="forge"
    [version]="1.20.1-47.4.10"
)

declare -A VANILLA_CONFIG=(
    [type]="vanilla"
    [version]="1.21.11"
    [url]="https://piston-data.mojang.com/v1/objects/64bb6d763bed0a9f1d632ec347938594144943ed/server.jar"
)

# ===== UTILITY FUNCTIONS =====

print_header() {
    echo "========================================="
    echo "   $1"
    echo "========================================="
}

print_success() {
    echo "✅ $1"
}

print_warning() {
    echo "⚠️  $1"
}

print_error() {
    echo "❌ $1"
}

# ===== CORE FUNCTIONS =====

intro_message() {
    print_header "🚀 Minecraft Server Setup 🚀"
    sleep 1
    echo " This script automates the installation of Minecraft servers."
    echo " Supported types: Fabric, Forge, Vanilla"
    print_header ""
    sleep 1
}

select_server_type() {
    print_header "📦 Select Server Type"
    echo "   1) Fabric (Recommended for mods + performance)"
    echo "   2) Forge (Classic modding platform)"
    echo "   3) Vanilla (Pure Minecraft experience)"
    read -p "   Enter choice [1-3]: " type_choice
    
    case "$type_choice" in
        1)
            MC_TYPE="fabric"
            MC_VERSION="${FABRIC_CONFIG[version]}"
            local loader="${FABRIC_CONFIG[loader_version]}"
            local installer="${FABRIC_CONFIG[installer_version]}"
            INSTALLER_URL="https://maven.fabricmc.net/net/fabricmc/fabric-installer/${installer}/fabric-installer-${installer}.jar"
            INSTALLER_JAR="fabric-installer.jar"
            START_CMD="java @user_jvm_args.txt -jar fabric-server-launch.jar nogui"
            ;;
        2)
            MC_TYPE="forge"
            MC_VERSION="${FORGE_CONFIG[version]}"
            INSTALLER_URL="https://maven.minecraftforge.net/net/minecraftforge/forge/${MC_VERSION}/forge-${MC_VERSION}-installer.jar"
            INSTALLER_JAR="forge-installer.jar"
            START_CMD="java @user_jvm_args.txt @libraries/net/minecraftforge/forge/${MC_VERSION}/unix_args.txt \"\$@\""
            ;;
        3)
            MC_TYPE="vanilla"
            MC_VERSION="${VANILLA_CONFIG[version]}"
            INSTALLER_URL="${VANILLA_CONFIG[url]}"
            INSTALLER_JAR="server.jar"
            START_CMD="java @user_jvm_args.txt -jar server.jar nogui"
            ;;
        *)
            print_error "Invalid choice. Defaulting to Fabric."
            select_server_type
            return
            ;;
    esac
    
    print_success "Selected: ${MC_TYPE} ${MC_VERSION}"
}

ask_jvm_args() {
    echo ""
    echo "Configure RAM allocation (Examples: 1024M, 2048M, 4G)"
    read -p "Enter JVM max memory (default 2048M): " user_mx
    JVM_MX=${user_mx:-"2048M"}
    read -p "Enter JVM min memory (default 1024M): " user_ms
    JVM_MS=${user_ms:-"1024M"}
    
    # Validation: Extract numbers to compare
    mx_int=$(echo "$JVM_MX" | tr -cd '0-9')
    ms_int=$(echo "$JVM_MS" | tr -cd '0-9')
    
    # Handle G suffix (multiply by 1024 for comparison)
    if [[ "$JVM_MX" == *"G"* ]] || [[ "$JVM_MX" == *"g"* ]]; then mx_int=$((mx_int * 1024)); fi
    if [[ "$JVM_MS" == *"G"* ]] || [[ "$JVM_MS" == *"g"* ]]; then ms_int=$((ms_int * 1024)); fi
    
    if [ "$ms_int" -gt "$mx_int" ]; then
        print_warning "Min memory ($JVM_MS) is larger than Max memory ($JVM_MX)."
        echo "   Auto-correcting: Setting Min memory to match Max memory."
        JVM_MS="$JVM_MX"
    fi
    
    JVM_ARGS="-Xmx${JVM_MX} -Xms${JVM_MS}"
    print_success "Memory settings: $JVM_ARGS"
}

ask_gamemode() {
    print_header "🏷️  Server Configuration"
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
    print_success "Game mode: $GAMEMODE"
}

scan_existing_servers() {
    echo ""
    echo "🔍 Scanning for existing '${MC_TYPE} ${MC_VERSION} (${GAMEMODE})' servers..."
    
    local pattern="[0-9][0-9]-${MC_TYPE}-${MC_VERSION}-${GAMEMODE}.service"
    existing_services=($(ls /etc/systemd/system/${pattern} 2>/dev/null))
    local count=${#existing_services[@]}
    
    if [ $count -eq 0 ]; then
        echo "   No existing servers found."
        read -p "   Create a new server? [Y/n]: " create_confirm
        if [[ "$create_confirm" =~ ^[Nn]$ ]]; then
            print_error "Operation cancelled."
            exit 0
        fi
        return 0  # CREATE
    else
        echo "   Found $count existing server(s):"
        for svc in "${existing_services[@]}"; do
            echo "   - $(basename "$svc" .service)"
        done
        echo ""
        echo "   Choose Action:"
        echo "   [C] Create New"
        echo "   [R] Reinstall Existing (Clean Wipe)"
        echo "   [D] Delete Existing"
        read -p "   Enter choice [C/R/D]: " action_choice
        
        case "$action_choice" in
            [Cc]*) return 0 ;;  # CREATE
            [Rr]*) return 1 ;;  # REINSTALL
            [Dd]*) return 2 ;;  # DELETE
            *) print_error "Invalid choice. Exiting."; exit 1 ;;
        esac
    fi
}

handle_delete() {
    read -p "⚠️  ENTER FULL SERVICE NAME to DELETE: " target_name
    
    if [[ ! -f "/etc/systemd/system/${target_name}.service" ]]; then
        print_error "Service '$target_name' not found."
        exit 1
    fi
    
    if [[ "$target_name" != *"-${MC_TYPE}-${MC_VERSION}-${GAMEMODE}" ]]; then
        print_error "Safety Check Failed: Name mismatch."
        exit 1
    fi

    echo "🛑 Stopping service..."
    sudo systemctl stop "$target_name"
    sudo systemctl disable "$target_name"
    
    local target_dir=$(systemctl show -p WorkingDirectory --value "$target_name")
    
    echo "🗑️  Deleting service file..."
    sudo rm "/etc/systemd/system/${target_name}.service"
    sudo systemctl daemon-reload
    
    if [ -d "$target_dir" ]; then
        echo "🗑️  Deleting server directory: $target_dir"
        sudo rm -rf "$target_dir"
    fi
    
    print_success "Server '$target_name' deleted successfully."
    exit 0
}

handle_reinstall() {
    read -p "⚠️  ENTER FULL SERVICE NAME to REINSTALL: " target_name
    
    if [[ ! -f "/etc/systemd/system/${target_name}.service" ]]; then
        print_error "Service '$target_name' not found."
        exit 1
    fi

    SERVER_ID=${target_name:0:2}
    
    echo "🛑 Preparing reinstall for ID: $SERVER_ID..."
    sudo systemctl stop "$target_name"
    sudo systemctl disable "$target_name"
    
    local target_dir=$(systemctl show -p WorkingDirectory --value "$target_name")
    echo "🗑️  Cleaning up old configuration..."
    sudo rm "/etc/systemd/system/${target_name}.service"
    sudo systemctl daemon-reload
    
    if [ -d "$target_dir" ]; then
        echo "🗑️  Wiping old directory: $target_dir"
        sudo rm -rf "$target_dir"
    fi
}

find_next_available_id() {
    for i in {1..99}; do
        local id_str=$(printf "%02d" $i)
        local candidate_name="${id_str}-${MC_TYPE}-${MC_VERSION}-${GAMEMODE}"
        if [[ ! -f "/etc/systemd/system/${candidate_name}.service" ]]; then
            SERVER_ID=$id_str
            return 0
        fi
    done
    print_error "No free IDs available (01-99). Cleanup some servers first."
    exit 1
}

configure_server_paths() {
    local timestamp=$(date +%Y%m%d_%H%M%S)
    MC_SERVICE_NAME="${SERVER_ID}-${MC_TYPE}-${MC_VERSION}-${GAMEMODE}"
    SERVER_DIR="${MC_DIR}/${MC_SERVICE_NAME}-${timestamp}"
    
    print_success "Configuration Set:"
    echo "   ID: $SERVER_ID"
    echo "   Service: $MC_SERVICE_NAME"
    echo "   Directory: $SERVER_DIR"
}

setup_environment() {
    echo ""
    echo "👤 Setting up user and directories..."
    
    if [ ! -d "${MC_DIR}" ]; then
        sudo mkdir -p "${MC_DIR}"
        id -u "${MC_USER}" &>/dev/null || sudo useradd -m "${MC_USER}"
        sudo chown -R "${MC_USER}:${MC_USER}" "${MC_DIR}"
    fi

    sudo mkdir -p "${SERVER_DIR}"
    sudo chown -R "${MC_USER}:${MC_USER}" "${SERVER_DIR}"
    cd "${SERVER_DIR}"
}

download_and_install() {
    if [ ! -f "${SERVER_DIR}/${INSTALLER_JAR}" ]; then
        echo "⬇️  Downloading ${MC_TYPE} server..."
        sudo -u "${MC_USER}" wget "${INSTALLER_URL}" -O "${SERVER_DIR}/${INSTALLER_JAR}"
    fi
    
    echo "🔨 Installing ${MC_TYPE} server..."
    
    case "$MC_TYPE" in
        fabric)
            local loader="${FABRIC_CONFIG[loader_version]}"
            sudo -u "${MC_USER}" java -jar "${INSTALLER_JAR}" server \
                -mcversion "${MC_VERSION}" \
                -loader "${loader}" \
                -downloadMinecraft
            ;;
        forge)
            sudo -u "${MC_USER}" java ${JVM_ARGS} -jar "${INSTALLER_JAR}" nogui --installServer
            ;;
        vanilla)
            # Vanilla just needs the jar, run once to generate files
            sudo -u "${MC_USER}" java ${JVM_ARGS} -jar "${INSTALLER_JAR}" nogui &
            local pid=$!
            sleep 10
            kill $pid 2>/dev/null || true
            ;;
    esac
    
    sleep 2
}

configure_server() {
    echo "📜 Configuring server..."
    
    # Accept EULA
    if [ -f "eula.txt" ]; then
        sudo -u "${MC_USER}" sed -i 's/eula=false/eula=true/' eula.txt
    else
        sudo -u "${MC_USER}" bash -c "echo 'eula=true' > ${SERVER_DIR}/eula.txt"
    fi
    
    # Configure for proxy support
    if [ -f "server.properties" ]; then
        sudo -u "${MC_USER}" sed -i 's/online-mode=true/online-mode=false/' server.properties
        sudo -u "${MC_USER}" sed -i 's/enforce-secure-profile=true/enforce-secure-profile=false/' server.properties
    fi
    
    # Save JVM args
    sudo -u "${MC_USER}" bash -c "echo '${JVM_ARGS}' > ${SERVER_DIR}/user_jvm_args.txt"
    
    print_success "Server configured"
}

create_scripts() {
    echo "📝 Creating start/stop scripts..."
    
    # START SCRIPT
    cat <<EOF | sudo -u "${MC_USER}" tee start > /dev/null
#!/bin/bash
cd ${SERVER_DIR}
${START_CMD}
EOF
    sudo chmod +x start

    # STOP SCRIPT
    cat <<EOF | sudo -u "${MC_USER}" tee stop > /dev/null
#!/bin/bash
pkill -TERM -f "${SERVER_DIR}"
while pgrep -f "${SERVER_DIR}" > /dev/null; do
    echo "Saving world and stopping..."
    sleep 1
done
echo "Server stopped."
EOF
    sudo chmod +x stop
}

create_systemd_service() {
    echo "⚙️  Configuring systemd service..."
    
    sudo bash -c "cat > /etc/systemd/system/${MC_SERVICE_NAME}.service <<EOF
[Unit]
Description=${MC_TYPE^} Minecraft Server
Wants=network-online.target

[Service]
User=${MC_USER}
WorkingDirectory=${SERVER_DIR}
ExecStart=${SERVER_DIR}/start
StandardInput=null

[Install]
WantedBy=multi-user.target
EOF"
    
    sudo systemctl daemon-reload
    sudo systemctl enable "${MC_SERVICE_NAME}.service"
    sudo systemctl start "${MC_SERVICE_NAME}.service"
}

finalize() {
    echo "🔒 Enforcing permissions..."
    sudo chown -R ${MC_USER}:${MC_USER} ${MC_DIR}
    
    echo ""
    print_header "🚀 INSTALLATION SUCCESSFUL 🚀"
    echo "| Component  | Value                          |"
    echo "|------------|--------------------------------|"
    echo "| Type       | ${MC_TYPE^} ${MC_VERSION}      |"
    echo "| User       | ${MC_USER}                     |"
    echo "| Directory  | ${SERVER_DIR}                  |"
    echo "| Service    | ${MC_SERVICE_NAME}             |"
    echo "| Port       | 25565                          |"
    print_header ""
    
    echo ""
    echo "📝 Useful commands:"
    echo "   Start:   sudo systemctl start ${MC_SERVICE_NAME}"
    echo "   Stop:    sudo systemctl stop ${MC_SERVICE_NAME}"
    echo "   Status:  sudo systemctl status ${MC_SERVICE_NAME}"
    echo "   Logs:    journalctl -u ${MC_SERVICE_NAME} -f"
}

# ===== MAIN =====
main() {
    intro_message
    select_server_type
    ask_gamemode
    
    scan_existing_servers
    local action=$?
    
    case $action in
        0) find_next_available_id ;;  # CREATE
        1) handle_reinstall ;;        # REINSTALL
        2) handle_delete ;;           # DELETE
    esac
    
    ask_jvm_args
    configure_server_paths
    
    # Check if service already exists
    if [ -f "/etc/systemd/system/${MC_SERVICE_NAME}.service" ]; then
        print_warning "Service ${MC_SERVICE_NAME} already exists. Skipping installation."
        exit 0
    fi
    
    setup_environment
    download_and_install
    configure_server
    create_scripts
    create_systemd_service
    finalize
}

main "$@"
