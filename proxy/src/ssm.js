const { SSMClient, SendCommandCommand, GetCommandInvocationCommand } = require("@aws-sdk/client-ssm");
const config = require("../config.json");

const client = new SSMClient({ region: config.region });

/**
 * Envía un comando a la instancia EC2 para detener todos los servicios de Minecraft activos.
 * Utiliza detección dinámica (01-, 02-, etc.) para cerrar cada mundo de forma cíclica.
 * * @param {string} instanceId - El ID de la instancia EC2
 * @returns {Promise<boolean>} - True si tuvo éxito, false de lo contrario
 */
async function stopMinecraftService(instanceId) {
    console.log(`[SSM] Intentando detener todos los servicios de Minecraft en ${instanceId}...`);

    // Script cíclico que detecta y cierra cada mundo activo siguiendo el patrón ID-MOTOR-VERSION
    const shellScript = [
        "#!/bin/bash",
        // 1. Obtener la lista de todos los servicios activos que coincidan con el patrón numérico
        "SERVICES=$(systemctl list-units --type=service --state=active --no-legend | grep -o -E '[0-9]{2}-[a-zA-Z0-9]+-[^ ]+') ",
        
        "if [ -n \"$SERVICES\" ]; then",
        "    echo \"Servicios detectados para cierre:\"",
        "    echo \"$SERVICES\"",
        
        // 2. Bucle para detener cada servicio de forma individual
        "    for SERVICE in $SERVICES; do",
        "        echo \"✅ Deteniendo: $SERVICE\"",
        "        sudo systemctl stop \"$SERVICE\"",
        "    done",
        
        "    # 3. Sincronizar cambios en disco para asegurar la integridad de todos los mundos
        "    sync",
        "    echo \"✨ Todos los servicios de Minecraft han sido detenidos correctamente.\"",
        "else",
        "    echo \"❌ No se encontraron servicios de Minecraft activos (01-, 02-, etc.) para cerrar.\"",
        "fi"
    ];

    try {
        const command = new SendCommandCommand({
            InstanceIds: [instanceId],
            DocumentName: "AWS-RunShellScript",
            Parameters: {
                commands: shellScript
            }
        });

        const sendResponse = await client.send(command);
        const commandId = sendResponse.Command.CommandId;
        
        console.log(`[SSM] Comando enviado (ID: ${commandId}). Esperando que finalice el cierre cíclico...`);

        // Realizar seguimiento hasta que el comando termine en la instancia
        return await waitForCommand(instanceId, commandId);

    } catch (err) {
        console.error("[SSM] Error al enviar el comando de parada:", err);
        return false;
    }
}

/**
 * Realiza consultas periódicas (polling) para verificar el estado del comando en AWS SSM.
 */
async function waitForCommand(instanceId, commandId, maxAttempts = 20) {
    for (let i = 0; i < maxAttempts; i++) {
        try {
            const command = new GetCommandInvocationCommand({
                CommandId: commandId,
                InstanceId: instanceId
            });
            
            const response = await client.send(command);
            const status = response.Status; // Success, Failed, Cancelled, TimedOut, etc.
            
            if (status === 'Success') {
                console.log("[SSM] Salida del comando remoto:\n", response.StandardOutputContent);
                console.log("[SSM] El proceso de apagado cíclico finalizó con éxito.");
                return true;
            } else if (['Failed', 'Cancelled', 'TimedOut'].includes(status)) {
                console.error(`[SSM] El comando falló en la instancia con estado: ${status}`);
                console.error("[SSM] Stderr:", response.StandardErrorContent);
                return false;
            }

            // Esperar 2 segundos antes de la siguiente consulta
            await new Promise(resolve => setTimeout(resolve, 2000));
            
        } catch (err) {
            console.error(`[SSM] Error consultando estado (intento ${i+1}):`, err.message);
            await new Promise(resolve => setTimeout(resolve, 2000));
        }
    }
    
    console.error("[SSM] Tiempo de espera agotado.");
    return false;
}

module.exports = { stopMinecraftService };
