# Sistema de Monitoreo del Proxy Server

Documentación técnica del sistema de monitoreo que permite al Proxy Server mantener control sobre el estado del servidor de Minecraft (encendido/apagado).

---

## 📋 Índice

1. [Visión General](#visión-general)
2. [Arquitectura del Sistema](#arquitectura-del-sistema)
3. [Componentes](#componentes)
4. [Diagramas de Flujo](#diagramas-de-flujo)
5. [Configuración](#configuración)
6. [API de Referencia](#api-de-referencia)

---

## Visión General

El sistema de monitoreo implementa un patrón de **polling** que consulta el estado de la instancia EC2 de AWS cada 10 segundos. Esto permite al proxy:

- ✅ Mostrar el estado real del servidor en el MOTD (Message of the Day)
- ✅ Encender automáticamente el servidor cuando un jugador intenta conectarse
- ✅ Proxy transparente del tráfico cuando el servidor está encendido
- ✅ Mostrar mensajes informativos durante estados de transición

---

## Arquitectura del Sistema

```mermaid
graph TB
    subgraph "Proxy Server (Siempre Activo)"
        A[index.js<br/>Servidor Principal] --> B[StatusCache<br/>Sistema de Polling]
        A --> C[aws.js<br/>Cliente AWS EC2]
        B --> C
    end

    subgraph "AWS Cloud"
        D[(EC2 Instance<br/>Minecraft Server)]
    end

    subgraph "Clientes"
        E[🎮 Jugador 1]
        F[🎮 Jugador 2]
        G[🎮 Jugador N]
    end

    C <-->|API Calls| D
    E & F & G -->|Conexión TCP| A

    style A fill:#4a90d9,color:#fff
    style B fill:#50c878,color:#fff
    style C fill:#ff9500,color:#fff
    style D fill:#9b59b6,color:#fff
```

---

## Componentes

### 1. `src/aws.js` - Cliente AWS EC2

Módulo que encapsula todas las operaciones con AWS EC2.

| Función             | Parámetros           | Retorno            | Descripción                              |
| ------------------- | -------------------- | ------------------ | ---------------------------------------- |
| `getServerStatus()` | `instanceId: string` | `Promise<string>`  | Obtiene el estado actual de la instancia |
| `startServer()`     | `instanceId: string` | `Promise<boolean>` | Inicia la instancia EC2                  |
| `stopServer()`      | `instanceId: string` | `Promise<boolean>` | Detiene la instancia EC2                 |

**Estados posibles de EC2:**

- `running` - Servidor encendido y operativo
- `stopped` - Servidor apagado
- `pending` - Servidor iniciándose
- `stopping` - Servidor apagándose
- `shutting-down` - Servidor terminándose
- `terminated` - Servidor terminado
- `unknown` - Error al consultar estado
- `notFound` - Instancia no encontrada

---

### 2. `src/utils/status-cache.js` - Sistema de Caché y Polling

Implementa el patrón Singleton para mantener un cache centralizado del estado del servidor.

#### Clase `StatusCache`

```javascript
class StatusCache {
    constructor(instanceId, pollIntervalMs = 10000)
    start()           // Inicia el polling
    stop()            // Detiene el polling
    update()          // Fuerza actualización inmediata
    getStatus()       // Retorna estado cacheado
    isRunning()       // true si status === 'running'
    isStopped()       // true si status === 'stopped'
    getAge()          // ms desde última actualización
}
```

#### Funciones Exportadas

| Función                                       | Descripción                        |
| --------------------------------------------- | ---------------------------------- |
| `initStatusCache(instanceId, pollIntervalMs)` | Inicializa el singleton            |
| `getStatusCache()`                            | Obtiene la instancia del singleton |

---

### 3. `src/index.js` - Servidor Proxy Principal

Orquesta todo el sistema y maneja las conexiones de los jugadores.

**Flujo de Estados del Protocolo:**

| Estado                | Valor | Descripción                                         |
| --------------------- | ----- | --------------------------------------------------- |
| `HANDSHAKE`           | 0     | Esperando handshake inicial                         |
| `WAIT_STATUS_REQUEST` | 2     | Esperando solicitud de estado (lista de servidores) |
| `WAIT_PING`           | 4     | Esperando ping para responder pong                  |
| `WAIT_LOGIN`          | 3     | Esperando intento de login (conexión real)          |

---

## Diagramas de Flujo

### Flujo de Monitoreo (Polling)

```mermaid
flowchart TD
    A[🚀 Inicio del Proxy] --> B[Inicializar StatusCache]
    B --> C[Consulta Inicial a AWS]
    C --> D[Guardar Estado en Cache]
    D --> E[⏰ Esperar 10 segundos]
    E --> F{¿Proxy Activo?}
    F -->|Sí| G[Consultar AWS EC2]
    G --> H[Actualizar Cache]
    H --> I[Registrar Timestamp]
    I --> E
    F -->|No| J[🛑 Detener Polling]

    style A fill:#4a90d9,color:#fff
    style B fill:#50c878,color:#fff
    style G fill:#ff9500,color:#fff
    style J fill:#e74c3c,color:#fff
```

---

### Flujo de Conexión de Jugador

```mermaid
flowchart TD
    A[🎮 Jugador se Conecta] --> B[Recibir Handshake]
    B --> C{Tipo de<br/>Conexión?}

    C -->|Status Request<br/>nextState=1| D[Construir MOTD]
    D --> E{¿Servidor<br/>Running?}
    E -->|Sí| F["§aOnline<br/>+ MOTD Normal"]
    E -->|No| G["§cOffline<br/>Sleeping..."]
    F & G --> H[Enviar Status Response]
    H --> I[Esperar Ping]
    I --> J[Responder Pong]
    J --> K[Cerrar Conexión]

    C -->|Login<br/>nextState=2| L{¿Estado del<br/>Servidor?}

    L -->|running| M[Conectar a Backend]
    M --> N[Enviar Handshake al Backend]
    N --> O[Enviar Login Packet]
    O --> P[🔗 Pipe Bidireccional]
    P --> Q[Jugador en el Servidor]

    L -->|stopped| R[Llamar startServer]
    R --> S["Enviar Disconnect:<br/>§eServer waking up! 😴"]

    L -->|pending/stopping| T["Enviar Disconnect:<br/>§eStatus: {estado}"]

    L -->|unknown/error| U["Enviar Disconnect:<br/>§cError"]

    style A fill:#4a90d9,color:#fff
    style M fill:#50c878,color:#fff
    style R fill:#ff9500,color:#fff
    style Q fill:#9b59b6,color:#fff
```

---

### Flujo de Estados del Servidor EC2

```mermaid
stateDiagram-v2
    [*] --> stopped : Estado Inicial

    stopped --> pending : startServer()
    pending --> running : AWS Boot Complete

    running --> stopping : stopServer()
    stopping --> stopped : AWS Shutdown Complete

    running --> shutting_down : terminate()
    shutting_down --> terminated : AWS Termination
    terminated --> [*]

    note right of stopped
        Jugador conecta → startServer()
    end note
    note right of running
        Proxy conecta jugador al backend
    end note
    note right of pending
        Mensaje: Esperando
    end note
```

---

### Secuencia de Inicio Automático

```mermaid
sequenceDiagram
    participant J as 🎮 Jugador
    participant P as Proxy Server
    participant C as StatusCache
    participant A as AWS EC2
    participant M as MC Server

    Note over C: Polling cada 10s
    C->>A: DescribeInstances
    A-->>C: status: "stopped"

    J->>P: Conexión TCP
    P->>P: Parse Handshake (nextState=2)
    P->>P: Parse Login Start
    P->>C: getStatus()
    C-->>P: "stopped"
    P->>C: isStopped()
    C-->>P: true

    P->>A: StartInstances
    A-->>P: Starting...
    P->>J: Disconnect: "Server waking up!"

    Note over A,M: ~30-60 segundos
    A->>M: Boot Instance
    M->>M: Start Minecraft

    Note over C: Próximo polling
    C->>A: DescribeInstances
    A-->>C: status: "running"

    J->>P: Reconexión
    P->>C: isRunning()
    C-->>P: true
    P->>M: Proxy Connection
    M-->>P: Connection OK
    P->>J: Pipe bidireccional

    Note over J,M: 🎮 Jugando!
```

---

## Configuración

### Archivo `config.json`

```json
{
  "region": "us-east-1",
  "proxy_port": 25599,
  "backend": {
    "fabric": {
      "instanceId": "i-xxxxxxxxxxxxxxxxx",
      "host": "ec2-xx-xx-xx-xx.compute-1.amazonaws.com",
      "port": 25565
    }
  },
  "motd": {
    "line1": "§5§lPurple Kingdom",
    "line2": "§7Welcome to the server!"
  }
}
```

### Variables de Entorno (Opcional)

```bash
AWS_REGION=us-east-1
AWS_ACCESS_KEY_ID=your-access-key
AWS_SECRET_ACCESS_KEY=your-secret-key
```

---

## API de Referencia

### Inicialización del StatusCache

```javascript
const { initStatusCache } = require("./utils/status-cache");

// Inicializa con polling cada 10 segundos (default)
const statusCache = initStatusCache("i-1234567890abcdef0");

// O con intervalo personalizado (5 segundos)
const statusCache = initStatusCache("i-1234567890abcdef0", 5000);
```

### Uso del StatusCache

```javascript
// Obtener estado actual
const status = statusCache.getStatus();
// Posibles valores: 'running', 'stopped', 'pending', 'stopping', 'unknown'

// Verificar si está corriendo
if (statusCache.isRunning()) {
  // Conectar jugador al backend
}

// Verificar si está detenido
if (statusCache.isStopped()) {
  // Iniciar servidor
  startServer(instanceId);
}

// Obtener antigüedad del cache
const ageMs = statusCache.getAge();
console.log(`Última actualización hace ${ageMs}ms`);
```

### Control del Servidor

```javascript
const { startServer, stopServer, getServerStatus } = require("./aws");

// Encender servidor
await startServer("i-1234567890abcdef0");

// Apagar servidor
await stopServer("i-1234567890abcdef0");

// Consulta directa (sin cache)
const status = await getServerStatus("i-1234567890abcdef0");
```

---

## Notas Técnicas

> [!IMPORTANT]
> El intervalo de polling de 10 segundos es un balance entre:
>
> - **Responsividad**: Detectar cambios de estado rápidamente
> - **Costo**: Minimizar llamadas a la API de AWS (son gratuitas pero tienen rate limits)

> [!TIP]
> Para depuración, puedes reducir el intervalo temporalmente:
>
> ```javascript
> const statusCache = initStatusCache(instanceId, 3000); // 3 segundos
> ```

> [!WARNING]
> El sistema asume que hay una única instancia del proxy. Si ejecutas múltiples proxies apuntando al mismo servidor, podrían haber conflictos de arranque.

---

## Archivos Relacionados

| Archivo           | Ubicación                         | Descripción               |
| ----------------- | --------------------------------- | ------------------------- |
| `aws.js`          | `proxy/src/aws.js`                | Cliente AWS EC2           |
| `status-cache.js` | `proxy/src/utils/status-cache.js` | Sistema de polling        |
| `index.js`        | `proxy/src/index.js`              | Servidor proxy principal  |
| `config.json`     | `proxy/config.json`               | Configuración del sistema |
