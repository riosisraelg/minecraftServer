# 🎮 Instrucciones para Desplegar en EC2

## ✅ Lo que se ha actualizado

He corregido y mejorado completamente el proyecto para solucionar el error **EADDRINUSE** y otros problemas:

### 📦 Archivos Nuevos Creados:

1. **`proxy/ecosystem.config.js`** - Configuración de PM2 para gestión de procesos
2. **`proxy/manage-proxy.sh`** - Script de gestión del proxy (start/stop/restart/etc)
3. **`proxy/deploy.sh`** - Script de despliegue automatizado para EC2
4. **`proxy/.env.example`** - Plantilla de configuración de entorno
5. **`proxy/.gitignore`** - Reglas para excluir logs y archivos sensibles
6. **`proxy/README.md`** - Documentación completa del proxy
7. **`proxy/QUICKSTART.sh`** - Guía rápida de referencia
8. **`docs/DEPLOYMENT.md`** - Guía paso a paso para desplegar en EC2
9. **`CHANGELOG.md`** - Registro de todos los cambios

### 🔧 Archivos Modificados:

1. **`proxy/src/index.js`** - Se agregó:
   - Manejo proper de errores EADDRINUSE con mensajes útiles
   - Shutdown graceful (SIGTERM, SIGINT)
   - Manejo de excepciones no capturadas
   - Mejor logging

2. **`README.MD`** - Actualizado con:
   - Nuevas instrucciones de despliegue
   - Sección de troubleshooting
   - Corrección del puerto (25599 en lugar de 25565)

---

## 🚀 INSTRUCCIONES PARA DESPLEGAR EN TU EC2

### Paso 1: Haz Push de los Cambios

Desde tu máquina local (donde estás ahora):

```bash
cd /Users/riosisraelg/Desktop/3/minecraftServer
git push origin main
```

### Paso 2: Conéctate a tu EC2 Proxy

```bash
ssh -i mcServer-kp.pem ec2-user@<TU-IP-PUBLICA-PROXY>
```

### Paso 3: Actualiza el Código

```bash
cd /home/ec2-user/minecraftServer
git pull origin main
```

### Paso 4: Despliega el Proxy (OPCIÓN FÁCIL)

```bash
cd proxy
./deploy.sh
```

Esto automáticamente:
- Instalará dependencias
- Instalará PM2
- Limpiará procesos viejos
- Iniciará el proxy correctamente
- Configurará auto-inicio

### Paso 5: Verificar que Funciona

```bash
pm2 list
# Deberías ver "minecraft-proxy" como "online"

pm2 logs minecraft-proxy
# Deberías ver: "✓ Proxy successfully started on port 25599"
```

---

## 🛠️ COMANDOS ÚTILES

### Gestión del Proxy

```bash
# Ver estado
./manage-proxy.sh status

# Reiniciar
./manage-proxy.sh restart

# Ver logs en vivo
./manage-proxy.sh logs

# Limpiar procesos duplicados (arregla EADDRINUSE)
./manage-proxy.sh cleanup

# Ver guía rápida
./QUICKSTART.sh
```

### Debugging

```bash
# Ver todos los procesos PM2
pm2 list

# Ver qué está usando el puerto 25599
sudo lsof -i :25599

# Ver logs de errores
pm2 logs minecraft-proxy --err
```

---

## 🐛 SI TODAVÍA VES EL ERROR EADDRINUSE

Ejecuta estos comandos en tu EC2:

```bash
cd /home/ec2-user/minecraftServer/proxy

# Opción 1: Usar el script de limpieza
./manage-proxy.sh cleanup
./manage-proxy.sh start

# Opción 2: Manual
pm2 stop all
pm2 delete all
sudo kill -9 $(sudo lsof -t -i:25599)
./deploy.sh
```

---

## 📊 VERIFICACIÓN FINAL

Después del despliegue, verifica:

1. ✅ Proxy corriendo:
   ```bash
   pm2 list
   # "minecraft-proxy" debe estar en "online"
   ```

2. ✅ Puerto escuchando:
   ```bash
   sudo lsof -i :25599
   # Debe mostrar node escuchando
   ```

3. ✅ Logs sin errores:
   ```bash
   pm2 logs minecraft-proxy --lines 20
   ```

4. ✅ Conectar desde Minecraft:
   - Agregar servidor: `<IP-PUBLICA>:25599`
   - Deberías ver el mensaje "Purple Kingdom"

---

## 📚 DOCUMENTACIÓN ADICIONAL

- **`proxy/README.md`** - Documentación completa del proxy
- **`docs/DEPLOYMENT.md`** - Guía detallada de despliegue
- **`CHANGELOG.md`** - Todos los cambios realizados
- **`./QUICKSTART.sh`** - Referencia rápida de comandos

---

## 🎯 RESUMEN DE LO SOLUCIONADO

### Problema Original:
```
Error: listen EADDRINUSE: address already in use :::25599
```

### Soluciones Implementadas:
1. ✅ Script de gestión (`manage-proxy.sh`) que limpia procesos viejos
2. ✅ Configuración PM2 que previene procesos duplicados
3. ✅ Detección automática de conflictos de puerto con mensajes útiles
4. ✅ Shutdown graceful para evitar procesos zombies
5. ✅ Límite de reintentos para evitar loops infinitos
6. ✅ Scripts de despliegue automatizados

---

## 🆘 SOPORTE

Si tienes algún problema:

1. Revisa los logs: `pm2 logs minecraft-proxy`
2. Verifica el estado: `./manage-proxy.sh status`
3. Ejecuta limpieza: `./manage-proxy.sh cleanup`
4. Consulta: `proxy/README.md` o `docs/DEPLOYMENT.md`

---

**¡Listo para deployar! 🚀**
