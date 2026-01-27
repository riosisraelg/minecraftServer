const { SSMClient, SendCommandCommand, GetCommandInvocationCommand } = require("@aws-sdk/client-ssm");
const config = require("../config.json"); //

const client = new SSMClient({ region: config.region }); //

/**
 * Envía un comando a la instancia EC2 para detener el servicio de Minecraft de forma segura.
 * Utiliza detección dinámica de servicios (01-, 02-, etc.) para ser escalable.
 * * @param {string} instanceId - El ID de la instancia EC2
 * @returns {Promise<boolean>} - True si tuvo éxito, false de lo contrario
 */
async function stopMinecraftService(instanceId) {
    console.log(`[SSM] Intentando detener el servicio de Minecraft en ${instanceId}...`);
    
    // Script escalable que detecta cualquier servicio activo con el patrón ID-MOTOR-VERSION
    //
    const shellScript = [
        "#!/bin/bash",
        // Detectar dinámicamente el servicio activo (ej: 01-fabric, 02-papermc)
        "SERVICE=$(systemctl list-units --type=service --state=active --no-legend | grep -o -E '[0-9]{2}-[a-zA-Z0-9]+-[^ ]+' | head -n 1)",
        
        "if [ -n \"$SERVICE\" ]; then",
        "    echo \"Servicio detectado: $SERVICE\"",
        "    echo \"Deteniendo mediante systemctl (SIGTERM)...\"",
        
        // Detener el servicio. Systemd envía SIGTERM y Minecraft guarda el mundo antes de cerrar.
        "    sudo systemctl stop \"$SERVICE\"",
        
        "    # Sincronizar cambios en disco para asegurar integridad de los datos
        "    sync",
        "    echo \"Proceso de apagado completado.\"",
        "else",
        "    echo \"No se encontró ningún servicio activo con el patrón numérico (01-fabric, 02-papermc, etc.).\"",
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
        
        console.log(`[SSM] Comando enviado (ID: ${commandId}). Esperando finalización...`);

        // Esperar a que el comando se complete en la instancia
        return await waitForCommand(instanceId, commandId);

    } catch (err) {
        console.error("[SSM] Error al enviar el comando de parada:", err);
        return false;
    }
}

/**
 * Realiza polling para verificar el estado de la ejecución del comando en AWS SSM.
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
                console.log("[SSM] El comando de apagado seguro finalizó correctamente.");
                return true;
            } else if (['Failed', 'Cancelled', 'TimedOut'].includes(status)) {
                console.error(`[SSM] El comando falló con estado: ${status}`);
                console.error("[SSM] Stderr:", response.StandardErrorContent);
                return false;
            }

            // Esperar 2 segundos antes de volver a consultar
            await new Promise(resolve => setTimeout(resolve, 2000));
            
        } catch (err) {
            console.error(`[SSM] Error consultando estado del comando (intento ${i+1}):`, err.message);
            await new Promise(resolve => setTimeout(resolve, 2000));
        }
    }
    
    console.error("[SSM] Tiempo de espera agotado para la finalización del comando");
    return false;
}

module.exports = { stopMinecraftService }; //
