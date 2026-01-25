#!/usr/bin/env bash

# ============================================================================
# 🎮 Minecraft Server Manager v2.0
# ============================================================================
# Unified script for creating and managing Minecraft servers
# Supports: Fabric, Forge, Vanilla
# ============================================================================

set -e

# ===== DEPENDENCY CHECK =====
install_dependencies() {
    # Check for Java 17/21 & Node.js
    if command -v java &> /dev/null && command -v node &> /dev/null; then
        :
    else
        echo "📦 Installing system dependencies..."
        if command -v yum &> /dev/null; then
             sudo yum update -y
             sudo yum install -y java-17-amazon-corretto-devel java-21-amazon-corretto-devel screen git nodejs npm
             echo "✅ Packages installed!"
        elif command -v apt-get &> /dev/null; then
             sudo apt-get update
             sudo apt-get install -y openjdk-17-jdk screen git nodejs npm
             echo "✅ Packages installed!"
        else
             echo "⚠️  Package manager not found. Please ensure Java, Node.js, Screen, and Git are installed."
        fi
    fi
}

install_dependencies

# ===== GLOBAL CONFIG =====
MC_USER="minecraft"
MC_DIR="/opt/minecraft"
SERVICE_PATTERN="*-fabric-*\|*-forge-*\|*-vanilla-*\|*-paper-*"
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROXY_HELPER="${SCRIPT_DIR}/proxy-helper.js"

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
DO_GEYSER="false"

# Load Config File (if exists)
if [ -f "$PROXY_HELPER" ]; then
    # Helper outputs 'export VAR="VAL"' lines
    eval $(node "$PROXY_HELPER" parse-setup-config)
fi

# JVM Settings
JVM_MX="2048M"
JVM_MS="1024M"
JVM_ARGS=""

# ===== SERVER TYPE DEFINITIONS =====
# NOTE: values are loaded from server-setup.json via proxy-helper if available

declare -A FABRIC_CONFIG=(
    [type]="fabric"
    [version]="${CONFIG_FABRIC_VERSION:-1.21.1}"
    [loader_version]="${CONFIG_FABRIC_LOADER:-0.18.4}"
    [installer_version]="${CONFIG_FABRIC_INSTALLER:-1.1.1}"
)

declare -A PAPER_CONFIG=(
    [type]="paper"
    [version]="${CONFIG_PAPER_VERSION:-1.21.1}"
)

declare -A FORGE_CONFIG=(
    [type]="forge"
    [version]="${CONFIG_FORGE_VERSION:-1.20.1-47.4.10}"
)

declare -A VANILLA_CONFIG=(
    [type]="vanilla"
    [version]="${CONFIG_VANILLA_VERSION:-1.21.11}"
    [url]="${CONFIG_VANILLA_URL:-https://piston-data.mojang.com/v1/objects/64bb6d763bed0a9f1d632ec347938594144943ed/server.jar}"
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

    # Step 5a: Configure Geyser (Bedrock)
    configure_geyser

    # Step 5b: Allocate Port
    SERVER_PORT=$(node "$PROXY_HELPER" get-next-port)
    if [ -z "$SERVER_PORT" ]; then SERVER_PORT="25565"; fi
    
    # Step 6: Show summary and confirm
    print_subheader "📋 Configuration Summary"
    echo ""
    echo "   Type:      ${MC_TYPE^} ${MC_VERSION}"
    echo "   Mode:      ${GAMEMODE^}"
    echo "   Port:      ${SERVER_PORT}"
    echo "   Memory:    ${JVM_MX} max / ${JVM_MS} min"
    echo "   Seed:      ${LEVEL_SEED:-Random}"
    if [ "$DO_IMPORT" == "true" ]; then
        echo "   Import:    $IMPORT_FROM"
    fi
    if [ "$DO_GEYSER" == "true" ]; then
        echo "   Geyser:    Enabled (Bedrock Support)"
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
    echo "   1) Fabric  - ${FABRIC_CONFIG[version]} (Modded)"
    echo "   2) Forge   - ${FORGE_CONFIG[version]} (Modded)"
    echo "   3) Vanilla - ${VANILLA_CONFIG[version]}"
    echo "   4) Paper   - ${PAPER_CONFIG[version]} (High Performance)"
    echo "   0) Back"
    echo ""
    
    # Pre-selection if defined
    if [ -n "$CONFIG_DEFAULT_TYPE" ]; then
        print_info "Default from config: $CONFIG_DEFAULT_TYPE"
    fi
    
    read -p "   Select [0-4]: " type_choice

    # Overwrite valid configs if Version is also set?
    # If config logic was full bypass, we'd set MC_TYPE directly.
    # But existing logic sets INSTALLER_URL etc.
    # So we simulate the selection.
    
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
        4)
            MC_TYPE="paper"
            MC_VERSION="${PAPER_CONFIG[version]}"
            # Dynamic URL fetch will happen in install_server to get latest build
            INSTALLER_JAR="paper.jar"
            START_CMD="java @user_jvm_args.txt -jar paper.jar nogui"
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
    local mode_choice=""
    if [ -n "$CONFIG_GAMEMODE" ]; then
        case "$CONFIG_GAMEMODE" in
            survival) mode_choice=1 ;;
            creative) mode_choice=2 ;;
            hardcore) mode_choice=3 ;;
        esac
    fi

    if [ -z "$mode_choice" ]; then
        print_subheader "🎯 Game Mode"
        echo ""
        echo "   1) Survival  - Classic experience"
        echo "   2) Creative  - Free building"
        echo "3) Hardcore  - One life only"
        echo "   0) Back"
        echo ""
        read -p "   Select [0-3]: " mode_choice
    fi
    
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
    
    if [ -n "$CONFIG_MEMORY_MAX" ]; then
        JVM_MX="$CONFIG_MEMORY_MAX"
        JVM_MS="${CONFIG_MEMORY_MIN:-1024M}"
        print_info "Using Config: Max=${JVM_MX}, Min=${JVM_MS}"
    else
        echo ""
        echo "   Examples: 1024M, 2048M, 4G"
        echo ""
        read -p "   Max Memory (default 2048M): " user_mx
        JVM_MX=${user_mx:-"2048M"}
        
        read -p "   Min Memory (default 1024M): " user_ms
        JVM_MS=${user_ms:-"1024M"}
    fi
    
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
    
    if [ -n "$CONFIG_SEED" ]; then
        LEVEL_SEED="$CONFIG_SEED"
        print_info "Using Config Seed: $LEVEL_SEED"
    else
        echo ""
        echo "   Leave blank for a random seed."
        echo ""
        read -p "   World Seed: " user_seed
        LEVEL_SEED="$user_seed"
    fi
    
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

configure_geyser() {
    print_subheader "📱 Geyser Configuration"
    
    if [ -n "$CONFIG_ENABLE_GEYSER" ]; then
        if [ "$CONFIG_ENABLE_GEYSER" == "true" ]; then
            DO_GEYSER="true"
            print_info "Config: Geyser Enabled"
        else
            DO_GEYSER="false"
            print_info "Config: Geyser Disabled"
        fi
        return
    fi

    echo ""
    echo "   Enable support for Bedrock Edition players?"
    echo "   (Mobile, Console, Windows 10)"
    echo ""
    read -p "   Enable Geyser? [y/N]: " want_geyser
    
    if [[ "$want_geyser" =~ ^[Yy]$ ]]; then
        DO_GEYSER="true"
        print_success "Geyser: Enabled"
    else
        DO_GEYSER="false"
        print_success "Geyser: Disabled"
    fi
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
        paper)
            # Fetch latest build for version
            echo "   -> Fetching latest Paper ${MC_VERSION} build..."
            # Minimalistic API parsing using grep/sed to avoid heavy deps (assumes well-formed JSON)
            # Actually simplest reliable way without jq is tricky. Let's try python if available or simple regex.
            # Fallback to hardcoded logic if complex? No, we need valid build.
            
            # Use python3 to get latest build number
            local build_num=$(curl -s "https://api.papermc.io/v2/projects/paper/versions/${MC_VERSION}" | \
                python3 -c "import sys, json; print(json.load(sys.stdin)['builds'][-1])" 2>/dev/null || echo "")
            
            if [ -z "$build_num" ]; then
                print_error "Failed to fetch Paper build. Check internet or version."
                exit 1
            fi
            
            local dl_url="https://api.papermc.io/v2/projects/paper/versions/${MC_VERSION}/builds/${build_num}/downloads/paper-${MC_VERSION}-${build_num}.jar"
            echo "   -> Downloading Paper build ${build_num}..."
            sudo -u "${MC_USER}" wget -q "${dl_url}" -O "${SERVER_DIR}/${INSTALLER_JAR}"
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
        # Online Mode Configuration (Default: false)
        local online_val="false"
        if [ "$CONFIG_ONLINE_MODE" == "true" ]; then
            online_val="true"
        fi
        
        sudo -u "${MC_USER}" sed -i "s/online-mode=true/online-mode=${online_val}/" server.properties
        # Enforce secure profile usually matches online-mode or false for max compat
        if [ "$online_val" == "false" ]; then
            sudo -u "${MC_USER}" sed -i 's/enforce-secure-profile=true/enforce-secure-profile=false/' server.properties
        fi
        
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

    # Update Server Port & Bind to Localhost (Security)
    if grep -q "server-port=" server.properties; then
        sudo -u "${MC_USER}" sed -i "s/^server-port=.*/server-port=${SERVER_PORT}/" server.properties
    else
        echo "server-port=${SERVER_PORT}" | sudo -u "${MC_USER}" tee -a server.properties > /dev/null
    fi
    
    # Enforce localhost binding so players MUST use proxy
    if grep -q "server-ip=" server.properties; then
        sudo -u "${MC_USER}" sed -i "s/^server-ip=.*/server-ip=127.0.0.1/" server.properties
    else
        echo "server-ip=127.0.0.1" | sudo -u "${MC_USER}" tee -a server.properties > /dev/null
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
        
        # Shaderpacks (Client-side usually, but requested)
        copy_if_exists "${IMPORT_FROM}/shaderpacks" "${SERVER_DIR}/"

        # Player Data & Lists
        copy_if_exists "${IMPORT_FROM}/whitelist.json" "${SERVER_DIR}/"
        copy_if_exists "${IMPORT_FROM}/ops.json" "${SERVER_DIR}/"
        copy_if_exists "${IMPORT_FROM}/banned-players.json" "${SERVER_DIR}/"
        copy_if_exists "${IMPORT_FROM}/banned-ips.json" "${SERVER_DIR}/"
        copy_if_exists "${IMPORT_FROM}/usercache.json" "${SERVER_DIR}/"
        
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

    # Geyser Installation
    if [ "$DO_GEYSER" == "true" ]; then
        echo "📱 Installing Geyser..."
        local geyser_url=""
        local dest_dir=""
        
        case "$MC_TYPE" in
            paper)
                geyser_url="https://download.geysermc.org/v2/projects/geyser/versions/latest/builds/latest/downloads/spigot"
                dest_dir="${SERVER_DIR}/plugins"
                ;;
            fabric)
                geyser_url="https://download.geysermc.org/v2/projects/geyser/versions/latest/builds/latest/downloads/fabric"
                dest_dir="${SERVER_DIR}/mods"
                ;;
            forge)
                # Geyser-NeoForge/Forge
                geyser_url="https://download.geysermc.org/v2/projects/geyser/versions/latest/builds/latest/downloads/forge"
                dest_dir="${SERVER_DIR}/mods"
                ;;
            *)
                print_warning "Geyser not directly supported for ${MC_TYPE} via this script yet."
                ;;
        esac
        
        if [ -n "$geyser_url" ]; then
             sudo -u "${MC_USER}" mkdir -p "$dest_dir"
             sudo -u "${MC_USER}" wget -q "$geyser_url" -O "${dest_dir}/Geyser-${MC_TYPE}.jar"
             print_success "Geyser installed."
             
             # Floodgate Installation (Required for auth-type: floodgate)
             if [ "$MC_TYPE" == "paper" ]; then
                 echo "   -> Downloading Floodgate..."
                 local floodgate_url="https://download.geysermc.org/v2/projects/floodgate/versions/latest/builds/latest/downloads/spigot"
                 sudo -u "${MC_USER}" wget -q "$floodgate_url" -O "${dest_dir}/floodgate-spigot.jar"
                 print_success "Floodgate installed."
             fi
             
             # Pre-configure Geyser Port
             # Plugin usually generates config folder named 'Geyser-Spigot' or 'Geyser-Fabric'
             local config_dir=""
             if [ "$MC_TYPE" == "paper" ]; then config_dir="${SERVER_DIR}/plugins/Geyser-Spigot"; fi
             if [ "$MC_TYPE" == "fabric" ]; then config_dir="${SERVER_DIR}/config/Geyser-Fabric"; fi
             
             if [ -n "$config_dir" ]; then
                 echo "   -> Configuring Geyser port: ${SERVER_PORT}"
                 sudo -u "${MC_USER}" mkdir -p "$config_dir"
                 # Create basic config file
                 cat <<EOF | sudo -u "${MC_USER}" tee "${config_dir}/config.yml" > /dev/null
bedrock:
  address: 0.0.0.0
  port: ${SERVER_PORT}
  clone-remote-port: false
remote:
  address: auto
  port: 25565
  auth-type: online
EOF
                 # Note: 'remote' port is usually the java server port. 
                 # Since we run on same host, 'auto' might pick it up, or we set 'address' to 127.0.0.1
                 # and port to ${SERVER_PORT}. Yes, remote port should be SERVER_PORT.
                 # Re-writing config properly:
                 cat <<EOF | sudo -u "${MC_USER}" tee "${config_dir}/config.yml" > /dev/null
bedrock:
  address: 0.0.0.0
  port: ${SERVER_PORT}
  clone-remote-port: false
remote:
  address: 127.0.0.1
  port: ${SERVER_PORT}
  auth-type: floodgate
  use-proxy-protocol: false
EOF
             fi
        fi
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
    
    # Register with Proxy
    echo "🔗 Registering with proxy..."
    node "$PROXY_HELPER" add-server "${MC_SERVICE_NAME}" "${SERVER_PORT}" "${MC_TYPE}" "${MC_VERSION}" "${GAMEMODE}" "${DO_GEYSER}"
    
    # Update Security Group (Auto-Open Port)
    echo "🔓 Updating Security Group..."
    # Try getting Instance ID (timeout 2s in case not on EC2)
    local instance_id=$(curl -s --connect-timeout 2 http://169.254.169.254/latest/meta-data/instance-id)
    
    if [ -n "$instance_id" ] && [[ ! "$instance_id" =~ ^\< ]]; then # check not HTML error
        
        if [ "$DO_GEYSER" == "true" ]; then
            # Open UDP only for Bedrock clients
            echo "   -> Geyser Enabled: Opening UDP port ${SERVER_PORT}..."
            node "$PROXY_HELPER" open-port "${SERVER_PORT}" "${instance_id}" "udp"
        else
            echo "   -> Geyser Disabled: No external ports opened (Traffic routed via Proxy/Localhost)."
        fi
        
    else
        echo "   ⚠️  Could not detect Instance ID. If running locally, this is expected."
    fi
    
    # Final summary
    print_header "✅ INSTALLATION COMPLETED"
    echo ""
    echo "   Service:    ${MC_SERVICE_NAME}"
    echo "   Directory:  ${SERVER_DIR}"
    echo "   Port:       ${SERVER_PORT}"
    echo ""
    echo "   Useful commands:"
    echo "   • Start:   sudo systemctl start ${MC_SERVICE_NAME}"
    echo "   • Stop:    sudo systemctl stop ${MC_SERVICE_NAME}"
    echo "   • Status:  sudo systemctl status ${MC_SERVICE_NAME}"
    echo "   • Logs:    journalctl -u ${MC_SERVICE_NAME} -f"
    echo ""
    echo "   ⚠️  IMPORTANT: Restart the proxy server to apply configuration changes."
}

# ===== MANAGE SERVERS FLOW =====

manage_servers_flow() {
    while true; do
        clear_screen
        print_header "📋 Manage Servers"
        
        # Find all services
        local services=($(ls /etc/systemd/system/*.service 2>/dev/null | xargs -I{} basename {} .service | grep -E "^[0-9]{2}-(fabric|forge|vanilla|paper)-"))
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
    
    # Remove specific Port Rule from SG
    # We need the port to know what to close. 
    # Attempt to read port from server.properties in the dir before deleting?
    # Or just try to close the port if we can find it.
    # The SERVICE_NAME doesn't contain the port. 
    # We can try to grep it from server.properties if the dir exists.
    local port_to_close=""
    if [ -f "${server_dir}/server.properties" ]; then
        port_to_close=$(grep "^server-port=" "${server_dir}/server.properties" | cut -d'=' -f2)
    fi
    
    if [ -n "$port_to_close" ]; then
        echo "🔒 Closing security group port: ${port_to_close}..."
        # Try getting Instance ID 
        local instance_id=$(curl -s --connect-timeout 2 http://169.254.169.254/latest/meta-data/instance-id)
        if [ -n "$instance_id" ] && [[ ! "$instance_id" =~ ^\< ]]; then
             node "$PROXY_HELPER" close-port "${port_to_close}" "${instance_id}" "both"
        fi
    fi

    if [ -d "$server_dir" ]; then
        echo "🗑️  Deleting directory: $server_dir"
        sudo rm -rf "$server_dir"
    fi
    
    # Remove from Proxy Config
    echo "🔗 Removing from proxy config..."
    node "$PROXY_HELPER" remove-server "$service_name"
    
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
