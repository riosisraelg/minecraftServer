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

# JVM Settings
JVM_MX="2048M"
JVM_MS="1024M"
JVM_ARGS=""

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
    read -p "   Presiona ENTER para continuar..." _
}

# ===== MAIN MENU =====

main_menu() {
    while true; do
        clear_screen
        print_header "🎮 Minecraft Server Manager"
        echo ""
        echo "   1) 🆕 Crear nuevo servidor"
        echo "   2) 📋 Gestionar servidores existentes"
        echo "   3) ❌ Salir"
        echo ""
        read -p "   Selecciona una opción [1-3]: " choice
        
        case "$choice" in
            1) create_server_flow ;;
            2) manage_servers_flow ;;
            3) echo ""; print_info "¡Hasta luego!"; exit 0 ;;
            *) print_error "Opción inválida"; sleep 1 ;;
        esac
    done
}

# ===== CREATE SERVER FLOW =====

create_server_flow() {
    clear_screen
    print_header "🆕 Crear Nuevo Servidor"
    
    # Step 1: Select type
    select_server_type || return
    
    # Step 2: Select gamemode
    select_gamemode || return
    
    # Step 3: Configure RAM
    configure_ram
    
    # Step 4: Show summary and confirm
    print_subheader "📋 Resumen de Configuración"
    echo ""
    echo "   Tipo:      ${MC_TYPE^} ${MC_VERSION}"
    echo "   Modo:      ${GAMEMODE^}"
    echo "   Memoria:   ${JVM_MX} máx / ${JVM_MS} mín"
    echo ""
    read -p "   ¿Proceder con la instalación? [S/n]: " confirm
    
    if [[ "$confirm" =~ ^[Nn]$ ]]; then
        print_warning "Instalación cancelada."
        press_enter
        return
    fi
    
    # Step 5: Find ID and install
    find_next_available_id
    configure_server_paths
    install_server
    press_enter
}

select_server_type() {
    print_subheader "📦 Tipo de Servidor"
    echo ""
    echo "   1) Fabric  - Recomendado para mods + rendimiento"
    echo "   2) Forge   - Plataforma clásica de mods"
    echo "   3) Vanilla - Minecraft puro"
    echo "   0) Volver"
    echo ""
    read -p "   Selecciona [0-3]: " type_choice
    
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
            print_error "Opción inválida"
            sleep 1
            select_server_type
            return $?
            ;;
    esac
    
    print_success "Seleccionado: ${MC_TYPE^} ${MC_VERSION}"
    return 0
}

select_gamemode() {
    print_subheader "🎯 Modo de Juego"
    echo ""
    echo "   1) Survival  - Experiencia clásica"
    echo "   2) Creative  - Construcción libre"
    echo "   3) Hardcore  - Una sola vida"
    echo "   0) Volver"
    echo ""
    read -p "   Selecciona [0-3]: " mode_choice
    
    case "$mode_choice" in
        0) return 1 ;;
        1) GAMEMODE="survival" ;;
        2) GAMEMODE="creative" ;;
        3) GAMEMODE="hardcore" ;;
        *)
            print_error "Opción inválida"
            sleep 1
            select_gamemode
            return $?
            ;;
    esac
    
    print_success "Modo: ${GAMEMODE^}"
    return 0
}

configure_ram() {
    print_subheader "💾 Configuración de Memoria"
    echo ""
    echo "   Ejemplos: 1024M, 2048M, 4G"
    echo ""
    read -p "   Memoria máxima (default 2048M): " user_mx
    JVM_MX=${user_mx:-"2048M"}
    
    read -p "   Memoria mínima (default 1024M): " user_ms
    JVM_MS=${user_ms:-"1024M"}
    
    # Validate
    local mx_int=$(echo "$JVM_MX" | tr -cd '0-9')
    local ms_int=$(echo "$JVM_MS" | tr -cd '0-9')
    [[ "$JVM_MX" == *[Gg]* ]] && mx_int=$((mx_int * 1024))
    [[ "$JVM_MS" == *[Gg]* ]] && ms_int=$((ms_int * 1024))
    
    if [ "$ms_int" -gt "$mx_int" ]; then
        print_warning "Mín > Máx. Ajustando mín = máx."
        JVM_MS="$JVM_MX"
    fi
    
    JVM_ARGS="-Xmx${JVM_MX} -Xms${JVM_MS}"
    print_success "Memoria: $JVM_ARGS"
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
    print_error "No hay IDs disponibles (01-99)."
    exit 1
}

configure_server_paths() {
    local timestamp=$(date +%Y%m%d_%H%M%S)
    MC_SERVICE_NAME="${SERVER_ID}-${MC_TYPE}-${MC_VERSION}-${GAMEMODE}"
    SERVER_DIR="${MC_DIR}/${MC_SERVICE_NAME}-${timestamp}"
}

install_server() {
    print_subheader "🚀 Instalando Servidor"
    
    # Setup user and directories
    echo "👤 Configurando usuario y directorios..."
    if [ ! -d "${MC_DIR}" ]; then
        sudo mkdir -p "${MC_DIR}"
        id -u "${MC_USER}" &>/dev/null || sudo useradd -m "${MC_USER}"
        sudo chown -R "${MC_USER}:${MC_USER}" "${MC_DIR}"
    fi
    
    sudo mkdir -p "${SERVER_DIR}"
    sudo chown -R "${MC_USER}:${MC_USER}" "${SERVER_DIR}"
    cd "${SERVER_DIR}"
    
    # Download
    echo "⬇️  Descargando ${MC_TYPE}..."
    sudo -u "${MC_USER}" wget -q "${INSTALLER_URL}" -O "${SERVER_DIR}/${INSTALLER_JAR}"
    
    # Install based on type
    echo "🔨 Instalando..."
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
    echo "📜 Configurando..."
    if [ -f "eula.txt" ]; then
        sudo -u "${MC_USER}" sed -i 's/eula=false/eula=true/' eula.txt
    else
        sudo -u "${MC_USER}" bash -c "echo 'eula=true' > ${SERVER_DIR}/eula.txt"
    fi
    
    if [ -f "server.properties" ]; then
        sudo -u "${MC_USER}" sed -i 's/online-mode=true/online-mode=false/' server.properties
        sudo -u "${MC_USER}" sed -i 's/enforce-secure-profile=true/enforce-secure-profile=false/' server.properties
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
    echo "⚙️  Creando servicio systemd..."
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
    
    # Final summary
    print_header "✅ INSTALACIÓN COMPLETADA"
    echo ""
    echo "   Servicio:   ${MC_SERVICE_NAME}"
    echo "   Directorio: ${SERVER_DIR}"
    echo "   Puerto:     25565"
    echo ""
    echo "   Comandos útiles:"
    echo "   • Iniciar: sudo systemctl start ${MC_SERVICE_NAME}"
    echo "   • Detener: sudo systemctl stop ${MC_SERVICE_NAME}"
    echo "   • Estado:  sudo systemctl status ${MC_SERVICE_NAME}"
    echo "   • Logs:    journalctl -u ${MC_SERVICE_NAME} -f"
}

# ===== MANAGE SERVERS FLOW =====

manage_servers_flow() {
    while true; do
        clear_screen
        print_header "📋 Gestionar Servidores"
        
        # Find all services
        local services=($(ls /etc/systemd/system/*.service 2>/dev/null | xargs -I{} basename {} .service | grep -E "^[0-9]{2}-(fabric|forge|vanilla)-"))
        local count=${#services[@]}
        
        if [ $count -eq 0 ]; then
            echo ""
            print_warning "No hay servidores instalados."
            press_enter
            return
        fi
        
        echo ""
        echo "   #   SERVICIO                           ESTADO"
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
        echo "   0) Volver al menú principal"
        echo ""
        read -p "   Selecciona servidor [0-$count]: " selection
        
        [[ "$selection" == "0" ]] && return
        
        if [[ "$selection" =~ ^[0-9]+$ ]] && [ "$selection" -ge 1 ] && [ "$selection" -le $count ]; then
            local selected_service="${services[$((selection-1))]}"
            server_actions_menu "$selected_service"
        else
            print_error "Selección inválida"
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
        echo "   Estado actual: $status_icon $status"
        echo ""
        
        if [[ "$status" == "active" ]]; then
            echo "   1) 🛑 Detener servidor"
        else
            echo "   1) ▶️  Iniciar servidor"
        fi
        echo "   2) 🔄 Reiniciar servidor"
        echo "   3) 📋 Ver logs (últimas 50 líneas)"
        echo "   4) 📋 Ver logs en vivo"
        echo "   5) 🔄 Reinstalar (wipe completo)"
        echo "   6) 🗑️  Eliminar servidor"
        echo "   0) ← Volver"
        echo ""
        read -p "   Selecciona acción [0-6]: " action
        
        case "$action" in
            0) return ;;
            1)
                if [[ "$status" == "active" ]]; then
                    echo "🛑 Deteniendo..."
                    sudo systemctl stop "$service_name"
                    print_success "Servidor detenido"
                else
                    echo "▶️  Iniciando..."
                    sudo systemctl start "$service_name"
                    print_success "Servidor iniciado"
                fi
                sleep 2
                ;;
            2)
                echo "🔄 Reiniciando..."
                sudo systemctl restart "$service_name"
                print_success "Servidor reiniciado"
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
                print_info "Presiona Ctrl+C para salir de los logs"
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
                print_error "Opción inválida"
                sleep 1
                ;;
        esac
    done
}

reinstall_server() {
    local service_name="$1"
    
    print_subheader "🔄 Reinstalar: $service_name"
    echo ""
    print_warning "Esto eliminará TODOS los datos del servidor y lo reinstalará."
    read -p "   ¿Estás seguro? Escribe 'REINSTALAR' para confirmar: " confirm
    
    if [[ "$confirm" != "REINSTALAR" ]]; then
        print_warning "Reinstalación cancelada."
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
    
    echo "🛑 Deteniendo servicio..."
    sudo systemctl stop "$service_name" 2>/dev/null || true
    sudo systemctl disable "$service_name" 2>/dev/null || true
    
    echo "🗑️  Eliminando servicio y datos..."
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
    
    print_subheader "🗑️  Eliminar: $service_name"
    echo ""
    print_warning "Esto eliminará PERMANENTEMENTE el servidor y todos sus datos."
    read -p "   ¿Estás seguro? Escribe 'ELIMINAR' para confirmar: " confirm
    
    if [[ "$confirm" != "ELIMINAR" ]]; then
        print_warning "Eliminación cancelada."
        press_enter
        return
    fi
    
    local server_dir=$(systemctl show -p WorkingDirectory --value "$service_name")
    
    echo "🛑 Deteniendo servicio..."
    sudo systemctl stop "$service_name" 2>/dev/null || true
    sudo systemctl disable "$service_name" 2>/dev/null || true
    
    echo "🗑️  Eliminando servicio..."
    sudo rm -f "/etc/systemd/system/${service_name}.service"
    sudo systemctl daemon-reload
    
    if [ -d "$server_dir" ]; then
        echo "🗑️  Eliminando directorio: $server_dir"
        sudo rm -rf "$server_dir"
    fi
    
    print_success "Servidor '$service_name' eliminado."
    press_enter
}

# ===== ENTRY POINT =====

main() {
    # Check if running as root
    if [ "$EUID" -eq 0 ]; then
        print_error "No ejecutes este script como root. Usa un usuario normal."
        exit 1
    fi
    
    main_menu
}

main "$@"
