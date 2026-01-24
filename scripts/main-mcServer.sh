#!/usr/bin/env bash

# ============================================================================
# 🎮 Minecraft Server Manager v2.0
# ============================================================================
# Unified script for creating and managing Minecraft servers
# Supports: Fabric, Forge, Vanilla
# ============================================================================

set -e

# ===== GLOBAL CONFIG =====
MC_USER="minecraft"
MC_DIR="/opt/minecraft"
SERVICE_PATTERN="*-fabric-*\|*-forge-*\|*-vanilla-*"

# Server configuration (set during create flow)
MC_TYPE=""
MC_VERSION=""
INSTALLER_URL=""
INSTALLER_JAR=""
START_CMD=""
GAMEMODE=""
SERVER_ID=""
MC_SERVICE_NAME=""
SERVER_DIR=""
LEVEL_SEED=""
IMPORT_FROM=""
DO_IMPORT="false"

# JVM Settings
JVM_MX="2048M"
JVM_MS="1024M"
JVM_ARGS=""

# ===== SERVER TYPE DEFINITIONS =====
declare -A FABRIC_CONFIG=(
    [type]="fabric"
    [version]="1.21.1"
    [loader_version]="0.18.4"
    [installer_version]="1.1.1"
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

# ===== DISPLAY FUNCTIONS =====

clear_screen() {
    clear 2>/dev/null || echo ""
}

print_header() {
    echo ""
    echo "═══════════════════════════════════════════"
    echo "   $1"
    echo "═══════════════════════════════════════════"
}

print_subheader() {
    echo ""
    echo "───────────────────────────────────────────"
    echo "   $1"
    echo "───────────────────────────────────────────"
}

print_success() { echo "✅ $1"; }
print_warning() { echo "⚠️  $1"; }
print_error()   { echo "❌ $1"; }
print_info()    { echo "ℹ️  $1"; }

press_enter() {
    echo ""
    read -p "   Press ENTER to continue..." _
}

# ===== MAIN MENU =====

main_menu() {
    while true; do
        clear_screen
        print_header "🎮 Minecraft Server Manager"
        echo ""
        echo "   1) 🆕 Create new server"
        echo "   2) 📋 Manage existing servers"
        echo "   3) ❌ Exit"
        echo ""
        read -p "   Select an option [1-3]: " choice
        
        case "$choice" in
            1) create_server_flow ;;
            2) manage_servers_flow ;;
            3) echo ""; print_info "See you later!"; exit 0 ;;
            *) print_error "Invalid option"; sleep 1 ;;
        esac
    done
}

# ===== CREATE SERVER FLOW =====

create_server_flow() {
    clear_screen
    print_header "🆕 Create New Server"
    
    # Step 1: Select type
    select_server_type || return
    
    # Step 2: Select gamemode
    select_gamemode || return
    
    # Step 3: Configure RAM
    configure_ram
    
    # Step 4: Configure Seed
    configure_seed
    
    # Step 5: Configure Import
    configure_import
    
    # Step 6: Show summary and confirm
    print_subheader "📋 Configuration Summary"
    echo ""
    echo "   Type:      ${MC_TYPE^} ${MC_VERSION}"
    echo "   Mode:      ${GAMEMODE^}"
    echo "   Memory:    ${JVM_MX} max / ${JVM_MS} min"
    echo "   Seed:      ${LEVEL_SEED:-Random}"
    if [ "$DO_IMPORT" == "true" ]; then
        echo "   Import:    $IMPORT_FROM"
    fi
    echo ""
    read -p "   Proceed with installation? [Y/n]: " confirm
    
    if [[ "$confirm" =~ ^[Nn]$ ]]; then
        print_warning "Installation canceled."
        press_enter
        return
    fi
    

    
    # Step 7: Find ID and install
    find_next_available_id
    configure_server_paths
    install_server
    press_enter
}

select_server_type() {
    print_subheader "📦 Server Type"
    echo ""
    echo "   1) Fabric  - Recommended for mods + performance"
    echo "   2) Forge   - Classic modding platform"
    echo "   3) Vanilla - Pure Minecraft"
    echo "   0) Back"
    echo ""
    read -p "   Select [0-3]: " type_choice
    
    case "$type_choice" in
        0) return 1 ;;
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
            print_error "Invalid option"
            sleep 1
            select_server_type
            return $?
            ;;
    esac
    
    print_success "Selected: ${MC_TYPE^} ${MC_VERSION}"
    return 0
}

select_gamemode() {
    print_subheader "🎯 Game Mode"
    echo ""
    echo "   1) Survival  - Classic experience"
    echo "   2) Creative  - Free building"
    echo "3) Hardcore  - One life only"
    echo "   0) Back"
    echo ""
    read -p "   Select [0-3]: " mode_choice
    
    case "$mode_choice" in
        0) return 1 ;;
        1) GAMEMODE="survival" ;;
        2) GAMEMODE="creative" ;;
        3) GAMEMODE="hardcore" ;;
        *)
            print_error "Invalid option"
            sleep 1
            select_gamemode
            return $?
            ;;
    esac
    
    print_success "Mode: ${GAMEMODE^}"
    return 0
}

configure_ram() {
    print_subheader "💾 Memory Configuration"
    echo ""
    echo "   Examples: 1024M, 2048M, 4G"
    echo ""
    read -p "   Max Memory (default 2048M): " user_mx
    JVM_MX=${user_mx:-"2048M"}
    
    read -p "   Min Memory (default 1024M): " user_ms
    JVM_MS=${user_ms:-"1024M"}
    
    # Validate
    local mx_int=$(echo "$JVM_MX" | tr -cd '0-9')
    local ms_int=$(echo "$JVM_MS" | tr -cd '0-9')
    [[ "$JVM_MX" == *[Gg]* ]] && mx_int=$((mx_int * 1024))
    [[ "$JVM_MS" == *[Gg]* ]] && ms_int=$((ms_int * 1024))
    
    if [ "$ms_int" -gt "$mx_int" ]; then
        print_warning "Min > Max. Adjusting min = max."
        JVM_MS="$JVM_MX"
    fi
    
    JVM_ARGS="-Xmx${JVM_MX} -Xms${JVM_MS}"
    print_success "Memory: $JVM_ARGS"
}

configure_seed() {
    print_subheader "🌱 Seed Configuration"
    echo ""
    echo "   Leave blank for a random seed."
    echo ""
    read -p "   World Seed: " user_seed
    LEVEL_SEED="$user_seed"
    
    if [ -z "$LEVEL_SEED" ]; then
        print_success "Seed: Random"
    else
        print_success "Seed: $LEVEL_SEED"
    fi
}

configure_import() {
    print_subheader "📦 Import Configuration"
    echo ""
    echo "   Do you want to import mods, configs and worlds"
    echo "   from another local instance?"
    echo ""
    read -p "   Import? [y/N]: " want_import
    
    if [[ ! "$want_import" =~ ^[Yy]$ ]]; then
        DO_IMPORT="false"
        return
    fi
    
    while true; do
        read -p "   Source folder path: " src_path
        # Expand ~ if used
        src_path="${src_path/#\~/$HOME}"
        
        if [ -d "$src_path" ]; then
            IMPORT_FROM="$src_path"
            DO_IMPORT="true"
            print_success "Valid source: $IMPORT_FROM"
            break
        else
            print_error "Path does not exist or is not a directory."
        fi
    done
}

find_next_available_id() {
    for i in {1..99}; do
        local id_str=$(printf "%02d" $i)
        local candidate="${id_str}-${MC_TYPE}-${MC_VERSION}-${GAMEMODE}"
        if [[ ! -f "/etc/systemd/system/${candidate}.service" ]]; then
            SERVER_ID=$id_str
            return 0
        fi
    done
    print_error "No IDs available (01-99)."
    exit 1
}

configure_server_paths() {
    local timestamp=$(date +%Y%m%d_%H%M%S)
    MC_SERVICE_NAME="${SERVER_ID}-${MC_TYPE}-${MC_VERSION}-${GAMEMODE}"
    SERVER_DIR="${MC_DIR}/${MC_SERVICE_NAME}-${timestamp}"
}

install_server() {
    print_subheader "🚀 Installing Server"
    
    # Setup user and directories
    echo "👤 Configuring user and directories..."
    if [ ! -d "${MC_DIR}" ]; then
        sudo mkdir -p "${MC_DIR}"
        id -u "${MC_USER}" &>/dev/null || sudo useradd -m "${MC_USER}"
        sudo chown -R "${MC_USER}:${MC_USER}" "${MC_DIR}"
    fi
    
    sudo mkdir -p "${SERVER_DIR}"
    sudo chown -R "${MC_USER}:${MC_USER}" "${SERVER_DIR}"
    cd "${SERVER_DIR}"
    
    # Download
    echo "⬇️  Downloading ${MC_TYPE}..."
    sudo -u "${MC_USER}" wget -q "${INSTALLER_URL}" -O "${SERVER_DIR}/${INSTALLER_JAR}"
    
    # Install based on type
    echo "🔨 Installing..."
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
            sudo -u "${MC_USER}" java ${JVM_ARGS} -jar "${INSTALLER_JAR}" nogui &
            local pid=$!
            sleep 10
            kill $pid 2>/dev/null || true
            ;;
    esac
    
    # Configure
    echo "📜 Configuring..."
    if [ -f "eula.txt" ]; then
        sudo -u "${MC_USER}" sed -i 's/eula=false/eula=true/' eula.txt
    else
        sudo -u "${MC_USER}" bash -c "echo 'eula=true' > ${SERVER_DIR}/eula.txt"
    fi
    
    if [ -f "server.properties" ]; then
        sudo -u "${MC_USER}" sed -i 's/online-mode=true/online-mode=false/' server.properties
        sudo -u "${MC_USER}" sed -i 's/enforce-secure-profile=true/enforce-secure-profile=false/' server.properties
        
        if [ -n "$LEVEL_SEED" ]; then
             sudo -u "${MC_USER}" sed -i "s/level-seed=/level-seed=${LEVEL_SEED}/" server.properties
             # If level-seed doesn't exist just in case (though it usually does), append it? 
             # Standard server.properties has it. Detailed logic: grep check or just append if missing.
             # For simplicity, assuming it exists or we append if strict compliance needed.
             # Let's just append if not replaced to be safe or leave as is.
             # Actually simplest is just to make sure it's set.
             if ! grep -q "level-seed=" server.properties; then
                 echo "level-seed=${LEVEL_SEED}" | sudo -u "${MC_USER}" tee -a server.properties > /dev/null
             fi
        fi
    fi
    
    # Import Logic
    if [ "$DO_IMPORT" == "true" ]; then
        echo "📦 Importing files from $IMPORT_FROM..."
        
        # Helper to copy if exists
        copy_if_exists() {
            local src="$1"
            local dest="$2"
            if [ -e "$src" ]; then
                echo "   -> Copying $(basename "$src")..."
                sudo cp -r "$src" "$dest"
                sudo chown -R "${MC_USER}:${MC_USER}" "$dest"
            fi
        }
        
        copy_if_exists "${IMPORT_FROM}/mods" "${SERVER_DIR}/"
        copy_if_exists "${IMPORT_FROM}/config" "${SERVER_DIR}/"
        
        # For world/saves
        # Common names: "world", "saves"
        if [ -d "${IMPORT_FROM}/saves" ]; then
             # If strictly one world intended, copies content of saves to 'world' folder or copies saves folder itself?
             # Server uses 'world' by default. 
             # Taking first world from saves if exists, or copying 'world' folder directly.
             if [ -d "${IMPORT_FROM}/world" ]; then
                 copy_if_exists "${IMPORT_FROM}/world" "${SERVER_DIR}/"
             else
                 # Try to find a world inside saves
                 local first_save=$(ls -d "${IMPORT_FROM}/saves/"* 2>/dev/null | head -n 1)
                 if [ -n "$first_save" ]; then
                      echo "   -> Copying world from saves: $(basename "$first_save") -> world"
                      sudo cp -r "$first_save" "${SERVER_DIR}/world"
                      sudo chown -R "${MC_USER}:${MC_USER}" "${SERVER_DIR}/world"
                 fi
             fi
        elif [ -d "${IMPORT_FROM}/world" ]; then
             copy_if_exists "${IMPORT_FROM}/world" "${SERVER_DIR}/"
        fi
        
        print_success "Import complete."
    fi
    
    sudo -u "${MC_USER}" bash -c "echo '${JVM_ARGS}' > ${SERVER_DIR}/user_jvm_args.txt"
    
    # Create start script
    cat <<EOF | sudo -u "${MC_USER}" tee start > /dev/null
#!/bin/bash
cd ${SERVER_DIR}
${START_CMD}
EOF
    sudo chmod +x start
    
    # Create systemd service
    echo "⚙️  Creating systemd service..."
    sudo bash -c "cat > /etc/systemd/system/${MC_SERVICE_NAME}.service <<EOF
[Unit]
Description=${MC_TYPE^} Minecraft Server
Wants=network-online.target
After=network-online.target

[Service]
User=${MC_USER}
WorkingDirectory=${SERVER_DIR}
ExecStart=/usr/bin/screen -DmS ${MC_SERVICE_NAME} ${SERVER_DIR}/start
ExecStop=/usr/bin/screen -p 0 -S ${MC_SERVICE_NAME} -X eval 'stuff "stop"\\015'
ExecStop=/bin/sleep 5
StandardInput=null

[Install]
WantedBy=multi-user.target
EOF"
    
    sudo systemctl daemon-reload
    sudo systemctl enable "${MC_SERVICE_NAME}.service"
    
    # Final summary
    print_header "✅ INSTALLATION COMPLETED"
    echo ""
    echo "   Service:    ${MC_SERVICE_NAME}"
    echo "   Directory:  ${SERVER_DIR}"
    echo "   Port:       25565"
    echo ""
    echo "   Useful commands:"
    echo "   • Start:   sudo systemctl start ${MC_SERVICE_NAME}"
    echo "   • Stop:    sudo systemctl stop ${MC_SERVICE_NAME}"
    echo "   • Status:  sudo systemctl status ${MC_SERVICE_NAME}"
    echo "   • Logs:    journalctl -u ${MC_SERVICE_NAME} -f"
}

# ===== MANAGE SERVERS FLOW =====

manage_servers_flow() {
    while true; do
        clear_screen
        print_header "📋 Manage Servers"
        
        # Find all services
        local services=($(ls /etc/systemd/system/*.service 2>/dev/null | xargs -I{} basename {} .service | grep -E "^[0-9]{2}-(fabric|forge|vanilla)-"))
        local count=${#services[@]}
        
        if [ $count -eq 0 ]; then
            echo ""
            print_warning "No servers installed."
            press_enter
            return
        fi
        
        echo ""
        echo "   #   SERVICE                            STATUS"
        echo "   ─── ────────────────────────────────── ──────────"
        
        local i=1
        for svc in "${services[@]}"; do
            local status=$(systemctl is-active "$svc" 2>/dev/null || echo "unknown")
            local status_icon="⚫"
            [[ "$status" == "active" ]] && status_icon="🟢"
            [[ "$status" == "inactive" ]] && status_icon="⭕"
            [[ "$status" == "failed" ]] && status_icon="🔴"
            
            printf "   %-3s %-38s %s %s\n" "$i)" "$svc" "$status_icon" "$status"
            ((i++))
        done
        
        echo ""
        echo "   0) Back to main menu"
        echo ""
        read -p "   Select server [0-$count]: " selection
        
        [[ "$selection" == "0" ]] && return
        
        if [[ "$selection" =~ ^[0-9]+$ ]] && [ "$selection" -ge 1 ] && [ "$selection" -le $count ]; then
            local selected_service="${services[$((selection-1))]}"
            server_actions_menu "$selected_service"
        else
            print_error "Invalid selection"
            sleep 1
        fi
    done
}

server_actions_menu() {
    local service_name="$1"
    
    while true; do
        clear_screen
        print_header "⚙️  $service_name"
        
        local status=$(systemctl is-active "$service_name" 2>/dev/null || echo "unknown")
        local status_icon="⚫"
        [[ "$status" == "active" ]] && status_icon="🟢"
        [[ "$status" == "inactive" ]] && status_icon="⭕"
        [[ "$status" == "failed" ]] && status_icon="🔴"
        
        echo ""
        echo "   Current status: $status_icon $status"
        echo ""
        
        if [[ "$status" == "active" ]]; then
            echo "   1) 🛑 Stop server"
        else
            echo "   1) ▶️  Start server"
        fi
        echo "   2) 🔄 Restart server"
        echo "   3) 📋 View logs (last 50 lines)"
        echo "   4) 📋 View live logs"
        echo "   5) 🔄 Reinstall (full wipe)"
        echo "   6) 🗑️  Delete server"
        echo "   0) ← Back"
        echo ""
        read -p "   Select action [0-6]: " action
        
        case "$action" in
            0) return ;;
            1)
                if [[ "$status" == "active" ]]; then
                    echo "🛑 Stopping..."
                    sudo systemctl stop "$service_name"
                    print_success "Server stopped"
                else
                    echo "▶️  Starting..."
                    sudo systemctl start "$service_name"
                    print_success "Server started"
                fi
                sleep 2
                ;;
            2)
                echo "🔄 Restarting..."
                sudo systemctl restart "$service_name"
                print_success "Server restarted"
                sleep 2
                ;;
            3)
                clear_screen
                print_header "📋 Logs: $service_name"
                journalctl -u "$service_name" -n 50 --no-pager
                press_enter
                ;;
            4)
                clear_screen
                print_info "Press Ctrl+C to exit logs"
                sleep 2
                journalctl -u "$service_name" -f
                ;;
            5)
                reinstall_server "$service_name"
                return
                ;;
            6)
                delete_server "$service_name"
                return
                ;;
            *)
                print_error "Invalid option"
                sleep 1
                ;;
        esac
    done
}

reinstall_server() {
    local service_name="$1"
    
    print_subheader "🔄 Reinstall: $service_name"
    echo ""
    print_warning "This will delete ALL data and reinstall the server."
    read -p "   Are you sure? Type 'REINSTALL' to confirm: " confirm
    
    if [[ "$confirm" != "REINSTALL" ]]; then
        print_warning "Reinstall canceled."
        press_enter
        return
    fi
    
    # Extract info from service name (format: XX-type-version-mode)
    SERVER_ID="${service_name:0:2}"
    MC_TYPE=$(echo "$service_name" | cut -d'-' -f2)
    MC_VERSION=$(echo "$service_name" | cut -d'-' -f3)
    GAMEMODE=$(echo "$service_name" | cut -d'-' -f4)
    
    # Get working directory before deletion
    local old_dir=$(systemctl show -p WorkingDirectory --value "$service_name")
    
    echo "🛑 Stopping service..."
    sudo systemctl stop "$service_name" 2>/dev/null || true
    sudo systemctl disable "$service_name" 2>/dev/null || true
    
    echo "🗑️  Deleting service and data..."
    sudo rm -f "/etc/systemd/system/${service_name}.service"
    sudo systemctl daemon-reload
    
    if [ -d "$old_dir" ]; then
        sudo rm -rf "$old_dir"
    fi
    
    # Reconfigure based on type
    case "$MC_TYPE" in
        fabric)
            local loader="${FABRIC_CONFIG[loader_version]}"
            local installer="${FABRIC_CONFIG[installer_version]}"
            INSTALLER_URL="https://maven.fabricmc.net/net/fabricmc/fabric-installer/${installer}/fabric-installer-${installer}.jar"
            INSTALLER_JAR="fabric-installer.jar"
            START_CMD="java @user_jvm_args.txt -jar fabric-server-launch.jar nogui"
            ;;
        forge)
            INSTALLER_URL="https://maven.minecraftforge.net/net/minecraftforge/forge/${MC_VERSION}/forge-${MC_VERSION}-installer.jar"
            INSTALLER_JAR="forge-installer.jar"
            START_CMD="java @user_jvm_args.txt @libraries/net/minecraftforge/forge/${MC_VERSION}/unix_args.txt \"\$@\""
            ;;
        vanilla)
            INSTALLER_URL="${VANILLA_CONFIG[url]}"
            INSTALLER_JAR="server.jar"
            START_CMD="java @user_jvm_args.txt -jar server.jar nogui"
            ;;
    esac
    
    # Ask for RAM config
    configure_ram
    configure_server_paths
    install_server
    press_enter
}

delete_server() {
    local service_name="$1"
    
    print_subheader "🗑️  Delete: $service_name"
    echo ""
    print_warning "This will PERMANENTLY delete the server and all data."
    read -p "   Are you sure? Type 'DELETE' to confirm: " confirm
    
    if [[ "$confirm" != "DELETE" ]]; then
        print_warning "Deletion canceled."
        press_enter
        return
    fi
    
    local server_dir=$(systemctl show -p WorkingDirectory --value "$service_name")
    
    echo "🛑 Stopping service..."
    sudo systemctl stop "$service_name" 2>/dev/null || true
    sudo systemctl disable "$service_name" 2>/dev/null || true
    
    echo "🗑️  Deleting service..."
    sudo rm -f "/etc/systemd/system/${service_name}.service"
    sudo systemctl daemon-reload
    
    if [ -d "$server_dir" ]; then
        echo "🗑️  Deleting directory: $server_dir"
        sudo rm -rf "$server_dir"
    fi
    
    print_success "Server '$service_name' deleted."
    press_enter
}

# ===== ENTRY POINT =====

main() {
    # Check if running as root
    if [ "$EUID" -eq 0 ]; then
        print_error "Do not run this script as root. Use a normal user."
        exit 1
    fi
    
    main_menu
}

main "$@"
