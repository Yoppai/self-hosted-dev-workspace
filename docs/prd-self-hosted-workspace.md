# PRD: Workspace de desarrollo self-hosted en Dokploy

## 1. Resumen ejecutivo

### Problema

El entorno de desarrollo actual depende de dispositivos configurados individualmente. Esto genera trabajo repetido, diferencias entre configuraciones y dificultad para continuar trabajando al cambiar de equipo. El objetivo es centralizar el entorno de desarrollo en un VPS para que herramientas, código, plugins, CLIs y configuraciones estén disponibles desde cualquier dispositivo mediante el navegador.

### Solución propuesta

Construir un workspace de desarrollo personal, single-user y self-hosted sobre un VPS Oracle Cloud A1 Flex administrado con Dokploy. El MVP desplegará un servicio Docker Compose con herramientas de desarrollo accesibles desde navegador, volúmenes persistentes compartidos y un entorno de escritorio remoto, protegido por Cloudflare Access, HTTPS vía Dokploy/Traefik y autenticación propia de cada aplicación.

### Criterios de éxito

- El usuario puede acceder al workspace desde cualquier dispositivo mediante dominios públicos HTTPS protegidos por Cloudflare Access.
- `code-server`, `opencode`, CodeNomad y KasmVNC pueden acceder a los mismos archivos de trabajo cuando corresponda.
- Plugins, CLIs, skills, servidores MCP, extensiones del editor y configuraciones instaladas persisten entre reinicios y redeploys.
- Ningún puerto interno de servicio queda expuesto directamente a internet; todo acceso pasa por Cloudflare Access y Dokploy/Traefik.
- El MVP corre de forma estable en Oracle A1 Flex: 4 OCPU, 24 GB RAM, 200 GB de disco, Ubuntu, `linux/arm64`.

## 2. Experiencia de usuario y funcionalidad

### Persona principal

- **Usuario principal**: desarrollador individual que quiere una estación de desarrollo persistente, accesible desde navegador y disponible en múltiples dispositivos sin reinstalar herramientas localmente.

### Historias de usuario

#### Historia 1: Acceso remoto al workspace

Como desarrollador, quiero abrir mi workspace desde cualquier dispositivo confiable para poder programar sin configurar ese dispositivo localmente.

Criterios de aceptación:

- El workspace está disponible mediante dominios públicos HTTPS gestionados por Dokploy/Traefik.
- Cloudflare Access protege cada ruta pública antes de que la solicitud llegue al VPS.
- Cada aplicación expuesta mantiene su autenticación interna habilitada.
- El usuario puede abrir al menos un IDE web, una interfaz de AI coding y una sesión de escritorio desde navegador.

#### Historia 2: Entorno de desarrollo persistente

Como desarrollador, quiero que herramientas, plugins, servidores MCP, skills y configuraciones sobrevivan reinicios para que el workspace se comporte como una máquina real y duradera.

Criterios de aceptación:

- Las extensiones y configuraciones de `code-server` persisten.
- La configuración global de `opencode`, configuración por proyecto, skills, agentes, MCP y configuración relacionada con auth persisten.
- La configuración, instancias, historial de chats y estado de sesión de CodeNomad persisten cuando aplique.
- La configuración de usuario y estado de escritorio de KasmVNC persisten cuando aplique.
- Las cachés de package managers pueden persistir si aportan valor, pero no deben tratarse como datos críticos.

#### Historia 3: Archivos compartidos entre herramientas

Como desarrollador, quiero que todas las herramientas accedan a carpetas comunes de trabajo para editar, inspeccionar y ejecutar los mismos proyectos desde distintas interfaces.

Criterios de aceptación:

- Un volumen compartido de workspace se monta en `code-server`, `opencode`, CodeNomad y KasmVNC.
- La propiedad y permisos de archivos permiten que los contenedores previstos lean y escriban sin arreglos manuales de `chown` después de cada deploy.
- Los volúmenes de configuración específicos de cada herramienta están separados de los volúmenes de proyectos/workspace.
- El diseño Compose documenta qué volúmenes son compartidos y cuáles son privados.

#### Historia 4: Escritorio remoto de respaldo

Como desarrollador, quiero un entorno de escritorio accesible desde navegador para usar herramientas GUI cuando la terminal o las UIs web no sean suficientes.

Criterios de aceptación:

- KasmVNC expone una sesión de escritorio accesible desde navegador detrás de HTTPS.
- El entorno de escritorio puede acceder al volumen compartido de workspace.
- La imagen de escritorio incluye o permite instalar herramientas base como Node.js, Bun, pnpm, Git y editores.

### No objetivos

- Multi-tenancy o aislamiento para equipos/múltiples usuarios.
- Orquestación con Kubernetes.
- Provisionamiento efímero completo por repositorio.
- Acceso público anónimo.
- Reemplazar por completo el desarrollo local en cargas que requieren hardware local, simuladores móviles o tareas intensivas de GPU.
- Gestionar deployments de aplicaciones productivas; este PRD se enfoca en el workspace de desarrollo.

## 3. Requisitos del sistema de IA

### Requisitos de herramientas

- `opencode` debe estar disponible como CLI y como motor de AI coding en modo servidor.
- CodeNomad debe poder invocar `opencode` desde su entorno de ejecución.
- Las credenciales de proveedores de IA deben almacenarse fuera de la imagen e inyectarse mediante variables de entorno de Dokploy, archivos de secretos montados o volúmenes persistentes de configuración.
- El workspace debe permitir agregar servidores MCP, skills y agentes en el futuro sin reconstruir todo el sistema por cada cambio de configuración.

### Estrategia de evaluación

- Verificar que `opencode` puede ejecutarse sobre un proyecto ubicado dentro del volumen compartido de workspace.
- Verificar que CodeNomad puede crear y reanudar sesiones después de reiniciar el contenedor.
- Verificar que skills, agentes y configuración MCP de `opencode` persisten después de un redeploy.
- Verificar que los secretos no quedan embebidos en imágenes Docker ni comprometidos en archivos del repositorio.

## 4. Especificaciones técnicas

### Arquitectura general

El MVP usa un servicio Compose en Dokploy con múltiples contenedores conectados mediante redes Docker privadas y volúmenes nombrados compartidos.

```text
Navegador del usuario
  -> Cloudflare Access
  -> Routing HTTPS de Dokploy / Traefik
  -> Contenedores de aplicación
       - code-server
       - servidor / CLI de opencode
       - CodeNomad server
       - escritorio KasmVNC
  -> Volúmenes Docker compartidos
       - proyectos del workspace
       - home/configuración de usuario
       - configuración persistente por herramienta
       - volúmenes de paquetes/caché
```

### Infraestructura objetivo

| Área | Requisito |
|---|---|
| VPS | Oracle Cloud A1 Flex |
| CPU | 4 OCPU |
| RAM | 24 GB |
| Disco | 200 GB |
| SO | Ubuntu |
| Plataforma de administración | Dokploy |
| Arquitectura de CPU | `linux/arm64` |

### Servicios iniciales

| Servicio | Propósito | Puerto esperado | Notas de persistencia |
|---|---:|---:|---|
| `code-server` | IDE VS Code en navegador | `8080` | Persistir `/home/coder/.config`, extensiones y archivos del workspace |
| `opencode` | CLI/servidor de AI coding | `4096` | Persistir `~/.config/opencode`, `opencode.json` por proyecto, `AGENTS.md`, skills y configuración MCP |
| CodeNomad | Cockpit web de AI coding sobre `opencode` | `9898` HTTPS / `9899` HTTP | Persistir `~/.config/codenomad` e instancias/sesiones |
| KasmVNC | Entorno de escritorio en navegador | configurable | Persistir configuración VNC, home de usuario y acceso al workspace compartido |

### Estrategia de volúmenes

| Volumen | Compartido por | Propósito |
|---|---|---|
| `workspace_projects` | Todas las herramientas de desarrollo | Repositorios y archivos principales de trabajo |
| `workspace_profile` | Herramientas que deben compartir identidad/configuración de usuario | Perfil persistente común para rutas como `~/.config`, `~/.gentle-ai`, `~/.agents`, `~/.local`, `~/.ssh` cuando corresponda |
| `workspace_home` | Escritorio y herramientas orientadas a CLI | Home de usuario persistente para entornos interactivos; debe evitar mezclar datos críticos con cachés temporales |
| `opencode_config` | `opencode`, CodeNomad cuando sea necesario | Configuración global de opencode, agentes, skills y MCP |
| `codenomad_config` | CodeNomad | Configuración, instancias y datos de chat/sesión |
| `code_server_config` | `code-server` | Configuración de VS Code, extensiones y config de code-server |
| `kasm_config` | KasmVNC | Password/config/logs de VNC y settings de escritorio |
| `package_caches` | Contenedores de build/CLI | Persistencia opcional de cachés npm/pnpm/bun |
| `toolchains` | Entornos CLI compatibles | Toolchains de usuario instaladas en rutas versionables como `~/.local`, `~/.bun`, `~/.npm-global`, `~/.pnpm-store`, `~/.cargo` o equivalentes |

Regla de diseño: los datos de proyecto y la configuración de herramientas no deben mezclarse en un único volumen indiferenciado. Compartir acceso es útil; compartir estado sin control vuelve el sistema frágil.

#### Estrategia para configuraciones globales y skills

Algunas herramientas, como `gentle-ai`, `opencode`, agentes, MCP servers y gestores de skills, guardan estado global fuera del directorio del proyecto. El MVP debe tratar estas rutas como parte del perfil persistente del workspace, no como datos efímeros del contenedor.

Rutas candidatas para persistencia compartida:

- `~/.config`
- `~/.gentle-ai`
- `~/.agents`
- `~/.local`
- `~/.ssh` cuando se requiera acceso Git/SSH
- stores/cachés de package managers cuando aporten velocidad sin volverse datos críticos

Estas rutas deben montarse con el mismo UID/GID en los contenedores que las compartan. Si dos herramientas escriben sobre la misma ruta global, el diseño debe documentarlo explícitamente para evitar corrupción de estado o diferencias de permisos.

#### Estrategia para CLIs y herramientas instaladas

Las instalaciones de CLIs no deben resolverse compartiendo `/usr/bin`, `/usr/local` o directorios del sistema entre contenedores. Eso es frágil porque mezcla binarios, librerías del sistema, arquitectura, permisos y dependencias de imágenes diferentes.

La estrategia recomendada es:

1. **Imagen base de desarrollo**: crear una imagen ARM64 común con herramientas estables como Git, Node.js, Bun, pnpm, shells, editores CLI y dependencias base. Los servicios interactivos que necesiten esas herramientas deben derivar de esa imagen o instalar el mismo bootstrap.
2. **Perfil persistente de usuario**: guardar herramientas instaladas por el usuario en rutas como `~/.local/bin`, `~/.bun/bin`, `~/.npm-global/bin` o equivalentes, montadas desde `workspace_profile`/`toolchains`.
3. **PATH consistente**: todos los contenedores que usen el perfil compartido deben declarar el mismo `PATH` para encontrar esas herramientas de usuario.
4. **Contenedor toolbox opcional**: agregar un servicio CLI dedicado para mantenimiento, instalación de herramientas y tareas de shell sobre los mismos volúmenes compartidos.

Ejemplo conceptual:

```text
Imagen base dev
  -> Git, Node.js, Bun, pnpm, paquetes del sistema

Volúmenes persistentes
  -> workspace_projects: repositorios
  -> workspace_profile: ~/.config, ~/.gentle-ai, ~/.agents, ~/.local
  -> toolchains: stores y binarios de usuario versionables

Servicios
  -> code-server, opencode, CodeNomad, KasmVNC y toolbox montan los volúmenes necesarios
```

Git debe considerarse una herramienta base de imagen, no una instalación compartida por volumen. Lo que sí se comparte son su configuración y credenciales de usuario, por ejemplo `~/.gitconfig`, `~/.ssh` y helpers de credenciales si se habilitan.

### Red y routing

- Cada app pública recibe un dominio o subdominio dedicado mediante Dokploy/Traefik.
- Cloudflare Access debe proteger todas las rutas públicas.
- La autenticación interna de cada app se mantiene activa:
  - Auth por password en `code-server`.
  - Password/basic auth del servidor `opencode` cuando esté disponible.
  - Usuario/password en CodeNomad.
  - Password en KasmVNC.
- Los contenedores se comunican por nombre de servicio dentro de redes Docker internas.
- Ninguna app debe publicar puertos directamente fuera de Traefik salvo que se habilite explícitamente para debugging.

### Seguridad y privacidad

- El workspace debe tratarse como una superficie administrativa: puede acceder a código fuente, terminales, tokens y credenciales de modelos.
- Cloudflare Access es obligatorio para el acceso público.
- La autenticación propia de cada app es obligatoria como defensa en profundidad.
- Los secretos deben guardarse en variables de entorno de Dokploy, archivos de secretos montados o volúmenes de configuración; nunca dentro de imágenes.
- Usar permisos de contenedor con mínimo privilegio cuando sea posible, sin romper la escritura en volúmenes compartidos.
- Preferir versiones pineadas en lugar de `latest` una vez estabilizado el MVP.
- Los backups deben cubrir volúmenes de workspace y configuración antes de considerar confiable el sistema.

#### Estrategia de secretos y autenticación persistente

El workspace debe separar herramientas, configuración y secretos en capas distintas:

| Capa | Uso | Ejemplos |
|---|---|---|
| Imagen base | Herramientas sin secretos | Git, Node.js, Bun, pnpm, paquetes del sistema |
| Dokploy env/secrets | Secretos de servicio | `ANTHROPIC_API_KEY`, `OPENAI_API_KEY`, `OPENCODE_SERVER_PASSWORD`, `CODENOMAD_SERVER_PASSWORD` |
| `workspace_profile` | Estado interactivo de usuario | OAuth de `opencode`, `~/.config/opencode`, `~/.local/share`, `~/.ssh`, `~/.gitconfig` |
| `workspace_projects` | Código y archivos de proyecto | Repositorios, documentación, archivos de trabajo |

Reglas:

- Las API keys y passwords de servicios se configuran desde Dokploy, no desde el repositorio ni desde la imagen.
- Los logins interactivos/OAuth se guardan en el perfil persistente compartido solo para los contenedores que necesiten esa sesión.
- Git debe preferir SSH con una key dedicada para este workspace, persistida en `~/.ssh` con permisos estrictos.
- Si se usa Git por HTTPS con token, el credential helper debe guardar estado dentro del perfil persistente y nunca en el repositorio.
- Los backups de `workspace_profile` son obligatorios, pero deben tratarse como backups sensibles y cifrarse.
- Los contenedores que no necesiten acceso a credenciales no deben montar `workspace_profile` completo.

### Requisitos de compatibilidad

- Todas las imágenes y builds custom deben soportar `linux/arm64` porque Oracle A1 Flex está basado en ARM.
- CodeNomad puede requerir una imagen custom porque depende de Node.js y de tener el CLI de `opencode` disponible en `PATH`.
- Si una imagen upstream no es compatible con ARM, el MVP debe compilarla localmente para ARM64 o postergar ese componente.

## 5. Riesgos y roadmap

### Riesgos técnicos

| Riesgo | Impacto | Mitigación |
|---|---|---|---|
| Incompatibilidad de imágenes ARM64 | El servicio no puede correr en Oracle A1 | Exigir validación ARM64 para cada imagen antes de aceptar el MVP |
| Acoplamiento CodeNomad/opencode | CodeNomad puede romperse ante cambios de opencode | Pinear versiones y probar ambos juntos en la misma imagen/runtime |
| Permisos en volúmenes compartidos | Las herramientas fallan al leer/escribir archivos | Estandarizar UID/GID y documentar ownership de mounts |
| Exposición pública de herramientas dev | Riesgo alto de seguridad | Cloudflare Access + HTTPS Traefik + auth por app + sin puertos directos |
| Crecimiento de disco por cachés/repos | El disco del VPS se llena con el tiempo | Separar volúmenes de caché y definir política de limpieza |
| Falta de health checks estándar | Dokploy puede no detectar apps rotas | Agregar health checks custom por servicio cuando sea posible |
| Uso de recursos de KasmVNC | El escritorio puede consumir CPU/RAM | Definir límites de recursos y monitorear durante el MVP |
| Runner offline bloquea CI | Alto | systemd auto-restart + health check para el contenedor del runner |
| Dependabot PRs excesivos | Bajo | límite de 5 PRs abiertos + weekly cadence |

### Fases de rollout

#### MVP

- Desplegar un servicio Compose en Dokploy con `code-server`, `opencode`, CodeNomad y KasmVNC.
- Configurar Cloudflare Access y routing HTTPS para cada app pública.
- Implementar volumen compartido de workspace y volúmenes separados de configuración.
- Validar persistencia después de restart/redeploy.
- Validar compatibilidad ARM64.

#### v1.1

- Agregar jobs de backup de volúmenes.
- Agregar health checks y monitoreo.
- Pinear versiones de todos los servicios.
- Documentar procedimiento de restore.
- Agregar script base de bootstrap para Node.js, Bun, pnpm, Git y herramientas comunes de desarrollo.

#### v1.2 — CI/CD Automation

- GitHub Actions CI/CD pipeline for automated ARM64 Docker image builds
- Self-hosted runner on Oracle Cloud VPS
- Push to GitHub Container Registry (GHCR)
- Dokploy webhook integration for auto-deploy
- Dependabot for automated dependency version checking (Docker + npm)
- Auto-merge for patch-level dependency updates

#### v2.0

- Agregar workspaces aislados opcionales por proyecto.
- Agregar creación de workspaces basada en templates.
- Agregar más herramientas web y servidores MCP.
- Agregar gestión de secretos más fuerte si las variables nativas de Dokploy no son suficientes.

### Checklist de aceptación del MVP

- [ ] Todas las rutas públicas están protegidas por Cloudflare Access.
- [ ] Dokploy/Traefik provee HTTPS para todas las apps expuestas.
- [ ] La autenticación interna de cada app permanece habilitada.
- [ ] `workspace_projects` es legible/escribible desde code-server, opencode, CodeNomad y KasmVNC.
- [ ] Reiniciar contenedores no elimina plugins, extensiones, skills, configuración MCP ni settings de usuario.
- [ ] Redeployar el servicio Compose no elimina archivos de proyecto.
- [ ] Todas las imágenes/builds seleccionadas corren en `linux/arm64`.
- [ ] Los secretos no se guardan en el repositorio ni quedan embebidos en imágenes.

## Referencias

- CodeNomad: https://github.com/NeuralNomadsAI/CodeNomad
- code-server: https://github.com/coder/code-server
- KasmVNC: https://github.com/kasmtech/KasmVNC
- Docs de opencode: https://opencode.ai/docs/es
- anomalyco/opencode: https://github.com/anomalyco/opencode
