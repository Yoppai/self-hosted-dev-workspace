# PRD: Pipeline de Deploy Automatizado a Dokploy

## 1. Resumen Ejecutivo

### Problema

El workspace self-hosted tiene todos los servicios definidos como Docker Compose y CI/CD que builda imágenes ARM64 y las pushea a GHCR. Sin embargo, **no hay conexión entre el pipeline de CI y Dokploy**: cada nuevo build requiere intervención manual para actualizar los contenedores en el VPS. Esto rompe el ciclo de automatización y hace que cada deploy sea un paso manual propenso a error.

### Solución propuesta

Implementar un pipeline de deploy automatizado que conecte GitHub Actions con Dokploy mediante un **webhook de redeploy**. Cuando el CI pushea nuevas imágenes a GHCR, notifica a Dokploy para que ejecute un `docker compose pull + up` automáticamente, sin intervención manual. La configuración del lado Dokploy usa el método **Raw Compose source** — el `docker-compose.prod.yml` se pega directamente en la UI de Dokploy, sin dependencia de git clone.

### Criterios de éxito

- **Push → Deploy en < 90s**: Un push a `main` que modifica servicios dispara el build, push a GHCR, webhook a Dokploy, y redeploy de todos los contenedores.
- **Cero intervención manual**: El developer hace push y el workspace se actualiza solo.
- **Persistencia intacta**: Los volúmenes (`workspace_projects`, `workspace_profile`, `toolchains`) sobreviven redeploys sin pérdida de datos.
- **Errores no bloqueantes**: Si Dokploy no responde al webhook, el pipeline de CI no falla — las imágenes ya están en GHCR y el redeploy puede reintentarse.
- **4/4 servicios healthy**: `code-server`, `opencode`, CodeNomad y KasmVNC responden correctamente después de cada redeploy.

---

## 2. Experiencia de Usuario y Funcionalidad

### Persona principal

- **Developer individual**: Tiene el workspace corriendo en un VPS Oracle A1 Flex administrado por Dokploy. Quiere que sus cambios de configuración e imágenes se reflejen automáticamente sin tener que loguearse al VPS o a la UI de Dokploy para cada update.

### Historias de usuario

#### Historia 1: Deploy automático desde GitHub

Como developer, quiero que al pushear a `main` el workspace se actualice solo, para no tener que intervenir manualmente en Dokploy después de cada cambio.

Criterios de aceptación:

- El pipeline de CI (`build-images.yml`) notifica exitosamente a Dokploy después de cada push de imágenes exitoso.
- Dokploy recibe la notificación, ejecuta `pull` de las nuevas imágenes y redeploya los servicios.
- El deploy se completa dentro de los 90 segundos posteriores al webhook.
- Si el webhook falla (Dokploy no accesible), el pipeline de CI no se rompe — emite un warning.

#### Historia 2: Configuración inicial de Dokploy

Como developer, quiero una guía clara para configurar Dokploy la primera vez, para no tener que adivinar dónde pegar el compose file, cómo autenticar contra GHCR, o dónde poner las variables de entorno.

Criterios de aceptación:

- Existe un documento `docs/deploy-dokploy.md` con los 7 pasos exactos: volúmenes → proyecto → registry → compose → env vars → webhook → deploy.
- Cada paso incluye nombres de campos, valores esperados y capturas conceptuales.
- La guía cubre rollback y troubleshooting de errores comunes.

#### Historia 3: Variables de entorno y secretos

Como developer, quiero que API keys y passwords se inyecten desde Dokploy sin estar en el repositorio ni en las imágenes, para mantener la seguridad de las credenciales.

Criterios de aceptación:

- Las 8 variables de entorno (`ANTHROPIC_API_KEY`, `OPENAI_API_KEY`, `CODE_SERVER_PASSWORD`, `OPENCODE_SERVER_USERNAME`, `OPENCODE_SERVER_PASSWORD`, `CODENOMAD_SERVER_USERNAME`, `CODENOMAD_SERVER_PASSWORD`, `KASMVNC_PASSWORD`) se configuran en la pestaña Environment de Dokploy.
- `docker-compose.prod.yml` usa `${VAR:?err}` para fallar rápido si falta alguna variable.
- Ningún secreto aparece en el repositorio ni en las imágenes Docker.

#### Historia 4: Rollback ante deploy fallido

Como developer, quiero poder revertir a una versión anterior del workspace si un deploy rompe algo, sin perder datos de proyectos ni configuración.

Criterios de aceptación:

- Puedo cambiar el tag de imagen en Dokploy a un SHA anterior y redeployar.
- Los volúmenes persistentes (`workspace_projects`, `workspace_profile`, `toolchains`) mantienen sus datos durante el rollback.
- El procedimiento de rollback está documentado.

### No objetivos

- Instalación de Dokploy en el VPS (ya está corriendo).
- Configuración de Cloudflare Access (cambio separado).
- Automatización de backups de volúmenes (v1.1).
- Multi-arch builds o deploys a múltiples VPS.
- Gestión de múltiples entornos (staging/producción).
- Deploy de aplicaciones productivas — este PRD cubre solo el workspace de desarrollo.

---

## 3. Especificaciones Técnicas

### 3.1 Estrategias de Deploy Evaluadas

Se investigaron 6 métodos para desplegar en Dokploy:

| Método | Cómo funciona | Complejidad | Automatización | ¿Recomendado? |
|---|---|---|---|---|
| **Raw Compose source** | Pegar YAML directamente en la UI de Dokploy | Baja | Alta (webhook) | ✅ **SÍ** |
| Git provider | Dokploy clona un repo y deploya desde ahí | Baja | Alta (auto-deploy) | ❌ `git clone` limpia el directorio en cada deploy |
| Dokploy API (tRPC) | Usar endpoints `compose.deploy` programáticamente | Media | Alta | ❌ Overkill — requiere manejar auth tokens |
| CLI local | `dokploy` CLI desde el VPS | Baja | Baja | ❌ Manual, no CI-friendly |
| Template | Crear desde template predefinido en Dokploy | Media | Media | ❌ Single-use, no actualizable |
| UI manual | Botón "Deploy" en la UI | Baja | Nula | ❌ Sin automatización |

**Estrategia seleccionada**: Raw Compose source con webhook trigger.

**Justificación**:
- Raw source mantiene a Dokploy stateless — no depende de git clone que puede limpiar directorios.
- El webhook es nativo de Dokploy, no requiere API keys adicionales.
- Mapea 1:1 con el job `notify-dokploy` existente en CI.
- Todas las imágenes ya se pushean a GHCR; Dokploy solo necesita credenciales de pull.

### 3.2 Arquitectura General

```
Developer push a main
        │
        ▼
┌─────────────────────────┐
│   GitHub Actions CI     │  Self-hosted ARM64 runner
│   build → validate      │
│   → push-images         │
│   → notify-dokploy      │
└──────────┬──────────────┘
           │  POST webhook
           ▼
┌─────────────────────────┐
│   Dokploy (VPS)         │
│   Compose service       │  Raw source: docker-compose.prod.yml
│   Pull latest images    │
│   Redeploy containers   │
└──────────┬──────────────┘
           │
    ┌──────┼──────┬──────────┐
    ▼      ▼      ▼          ▼
code-server  opencode  CodeNomad  KasmVNC
 (8080)     (4096)    (9898)     (6901)
    │         │         │          │
    └─────────┴────┬────┴──────────┘
                   ▼
    ┌──────────────────────────┐
    │  Volúmenes persistentes  │
    │  workspace_projects      │
    │  workspace_profile       │
    │  toolchains              │
    │  + 6 volúmenes de config │
    └──────────────────────────┘
```

### 3.3 Componentes del Sistema

#### Dokploy Service Configuration

| Propiedad | Valor |
|---|---|
| Proyecto | `self-hosted-workspace` |
| Servicio | `workspace-compose` |
| Tipo | Docker Compose |
| Fuente | **Raw** (pegar `docker-compose.prod.yml`) |
| Imágenes | `ghcr.io/yoppai/self-hosted-dev-workspace/*:latest` |

El `docker-compose.prod.yml` **no requiere modificaciones** — ya es Dokploy-compatible:
- Usa `image:` (no `build:`), apuntando a GHCR.
- Tiene labels de Traefik autosuficientes.
- Usa `restart: unless-stopped`.
- Sin port bindings al host (Traefik es el único ingress).

#### GHCR Registry Authentication

| Campo | Valor |
|---|---|
| Registry URL | `https://ghcr.io` |
| Username | `yoppai` (GitHub user) |
| Password | PAT con scope `read:packages` |
| Verificación | Test-pull de `ghcr.io/yoppai/self-hosted-dev-workspace/opencode-server:latest` |

#### Variables de Entorno (Dokploy Environment Tab)

| Variable | Consumida por | Tipo |
|---|---|---|
| `ANTHROPIC_API_KEY` | opencode-server, codenomad-server | Secreto |
| `OPENAI_API_KEY` | opencode-server, codenomad-server | Secreto |
| `CODE_SERVER_PASSWORD` | code-server | Secreto |
| `OPENCODE_SERVER_USERNAME` | opencode-server | Config |
| `OPENCODE_SERVER_PASSWORD` | opencode-server | Secreto |
| `CODENOMAD_SERVER_USERNAME` | codenomad-server | Config |
| `CODENOMAD_SERVER_PASSWORD` | codenomad-server | Secreto |
| `KASMVNC_PASSWORD` | kasmvnc-workspace | Secreto |

Validación: `docker-compose.prod.yml` usa `${VAR:?err}` — Docker Compose falla inmediatamente si falta alguna variable requerida.

#### Estrategia de Volúmenes

| Volumen | Tipo | Pre-crear | Propósito |
|---|---|---|---|
| `workspace_projects` | External | ✅ `bootstrap.sh` | Proyectos compartidos (UID 1000) |
| `workspace_profile` | External | ✅ `bootstrap.sh` | `.config`, `.ssh`, `.agents` (UID 1000) |
| `toolchains` | External | ✅ `bootstrap.sh` | `~/.local/bin`, stores (UID 1000) |
| `workspace_home` | Named (auto) | ❌ | Home de escritorio KasmVNC |
| `opencode_config` | Named (auto) | ❌ | Config global opencode |
| `codenomad_config` | Named (auto) | ❌ | Sesiones CodeNomad |
| `code_server_config` | Named (auto) | ❌ | Extensiones VS Code |
| `kasm_config` | Named (auto) | ❌ | Settings VNC |
| `package_caches` | Named (auto) | ❌ | Cachés npm/pnpm |

Los volúmenes external deben pre-crearse con `scripts/bootstrap.sh` antes del primer deploy para garantizar UID 1000. Los named los crea Docker automáticamente.

#### Dominios y Traefik Routing

| Servicio | Dominio | Puerto | Esquema Backend |
|---|---|---|---|
| code-server | `code.workspace.yoppai.dev` | 8080 | HTTP |
| opencode-server | `ai.workspace.yoppai.dev` | 4096 | HTTP |
| codenomad-server | `codenomad.workspace.yoppai.dev` | 9898 | HTTPS |
| kasmvnc-workspace | `desktop.workspace.yoppai.dev` | 6901 | HTTPS |

- **Certificados**: `tls.certresolver=letsencrypt` en todas las rutas. Dokploy/Traefik provisiona certificados automáticamente.
- **Cloudflare Access**: Se configura a nivel DNS/edge, fuera del alcance de este PRD.
- **Redes internas**: `workspace-net` (bridge) para DNS entre servicios; Dokploy attacha los contenedores a `dokploy-network` para Traefik.

### 3.4 CI/CD Pipeline

#### Workflow Modificado: `build-images.yml`

**Job `notify-dokploy`** (actualizado):

```yaml
notify-dokploy:
  name: Notify Dokploy
  runs-on: self-hosted
  needs: push-images
  if: success()
  continue-on-error: true

  steps:
    - name: POST to Dokploy Compose webhook
      env:
        DOKPLOY_URL: ${{ secrets.DOKPLOY_WEBHOOK_URL }}
      run: |
        if [[ -z "$DOKPLOY_URL" ]]; then
          echo "::warning::DOKPLOY_WEBHOOK_URL not configured — skipping"
          exit 0
        fi
        HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
          -X POST -H "Content-Type: application/json" \
          -d '{"repository":"${{ github.repository }}","sha":"${{ github.sha }}","ref":"${{ github.ref }}"}' \
          "$DOKPLOY_URL" 2>/dev/null || echo "000")
        if [[ "$HTTP_STATUS" =~ ^[23] ]]; then
          echo "✅ Dokploy webhook accepted (HTTP ${HTTP_STATUS})"
        else
          echo "::warning::Dokploy webhook returned HTTP ${HTTP_STATUS}"
        fi
```

**Cambios respecto a la versión anterior**:
- `DOKPLOY_WEBHOOK_URL` → `DOKPLOY_WEBHOOK_URL`
- Eliminada referencia a `DOKPLOY_WEBHOOK_SECRET` (no necesario para Dokploy Compose webhook).
- Payload simplificado: `repository`, `sha`, `ref`.
- Comportamiento: warning en vez de error si falla (`continue-on-error: true`).

#### Secrets de GitHub Requeridos

| Secret | Dónde se obtiene |
|---|---|
| `DOKPLOY_WEBHOOK_URL` | Dokploy UI → Service → Webhook → Copy URL |

> 💡 La autenticación contra GHCR usa `GITHUB_TOKEN` (auto-provisionado por GitHub, sin configuración manual). El PAT con `read:packages` solo se necesita del lado Dokploy (Registries → GHCR).

### 3.5 Flujo de Deploy

#### First-Time Setup

1. Ejecutar `sudo ./scripts/bootstrap.sh` en el VPS (crea volúmenes external con UID 1000).
2. Dokploy UI → Create Project `self-hosted-workspace`.
3. Create Service tipo Compose → Raw source → pegar `docker-compose.prod.yml`.
4. Registries → Add `ghcr.io` con PAT `read:packages` → Test Registry.
5. Environment tab → Agregar las 8 variables de entorno.
6. Save and Deploy → verificar 4/4 servicios healthy.

#### Deploy Normal (Push → Deployed)

1. Push a `main` (o merge de PR).
2. `build-images.yml` dispara: `changes` → `build-*` → `validate` → `push-images` → `notify-dokploy`.
3. `notify-dokploy` hace POST al webhook URL de Dokploy.
4. Dokploy encola redeploy, pullea `:latest` de GHCR.
5. Contenedores se reinician con nuevas imágenes; volúmenes persisten.
6. Health checks confirman servicios healthy.

#### Rollback

1. Dokploy UI → Stop service (o seleccionar deployment anterior).
2. Cambiar tags de `:latest` a un SHA conocido (ej. `:sha-a1b2c3d`).
3. Redeploy → contenedores inician con imágenes anteriores.
4. Datos en volúmenes intactos.

---

## 4. Riesgos y Roadmap

### Riesgos Técnicos

| Riesgo | Probabilidad | Impacto | Mitigación |
|---|---|---|---|
| Volúmenes external no creados pre-deploy | Media | Alto — contenedores no inician | `bootstrap.sh` documentado como paso obligatorio; fail-fast con error claro |
| GHCR PAT expira | Baja | Medio — Dokploy no puede pullear | Documentar renovación; Dokploy muestra error claro en logs |
| Webhook URL rota (rotación de Dokploy) | Baja | Bajo — CI sigue funcionando | `continue-on-error: true`; el redeploy puede dispararse manualmente |
| Conflicto de labels Traefik | Baja | Medio — dominios no resuelven | Labels son estándar; Dokploy las honra sin modificaciones |
| Cert resolver `letsencrypt` con nombre distinto en Dokploy | Media | Medio — sin HTTPS | Verificar durante setup; ajustar nombre de resolver si es necesario |
| Self-hosted runner offline | Media | Alto — pipeline no corre | systemd auto-restart en el VPS; health check del runner |
| Formato de webhook URL cambia entre versiones de Dokploy | Baja | Bajo | Payload mínimo; headers estándar; adaptable |

### Fases de Implementación

#### Fase 1 — Configuración Dokploy + Webhook (Actual)

- Crear el servicio Compose en Dokploy con Raw source.
- Registrar GHCR registry.
- Configurar las 8 variables de entorno.
- Actualizar `notify-dokploy` job en CI con el nuevo secret name y payload.
- Crear documentación `docs/deploy-dokploy.md`.
- Verificar YAML syntax (workflow + compose).

#### Fase 2 — E2E Verification (Requiere Entorno Live)

- Push a `main` y verificar webhook POST recibe HTTP 2xx.
- Confirmar redeploy en Dokploy dentro de 60s.
- Verificar 4/4 servicios healthy post-deploy.
- Verificar persistencia de `workspace_projects` (escribir archivo, redeployar, leer archivo).

#### Fase 3 — Backups y Monitoreo (v1.1)

- Automatizar backups de volúmenes con Dokploy Backup.
- Agregar health checks y alertas.
- Pinear versiones de todos los servicios.

#### Fase 4 — Expansión (v2.0)

- Workspaces aislados por proyecto.
- Templates para crear nuevos servicios.
- Gestión de secretos más robusta.

---

## 5. Requisitos del Sistema de IA

### Herramientas afectadas

- `opencode` y CodeNomad reciben `ANTHROPIC_API_KEY` y `OPENAI_API_KEY` desde Dokploy env vars.
- Las sesiones de CodeNomad persisten en `codenomad_config` (volume named).
- La config global de opencode persiste en `opencode_config`.

### Estrategia de verificación

- Confirmar que `opencode` puede ejecutarse sobre un proyecto en `workspace_projects` después de un redeploy.
- Confirmar que CodeNomad puede crear y reanudar sesiones después de reiniciar contenedores.
- Confirmar que skills, agentes y config MCP sobreviven redeploys.

---

## Referencias

- [Dokploy API MCP Skill](file:///C:/Users/adgbr/.agents/skills/dokploy-api-mcp/SKILL.md) — 449 tRPC endpoints, docs de compose deploy.
- [PRD del Workspace Self-Hosted](docs/prd-self-hosted-workspace.md) — PRD principal del proyecto.
- [SDD Exploration Report](openspec/changes/archive/dokploy-deployment/exploration.md) — Investigación de estrategias de deploy.
- [SDD Design](openspec/changes/archive/dokploy-deployment/design.md) — Diseño técnico detallado.
- [Deployment Guide](docs/deploy-dokploy.md) — Guía paso a paso para configurar Dokploy.
- [CI Workflow](.github/workflows/build-images.yml) — Pipeline modificado.
- [OpenSpec Specs](openspec/specs/dokploy-deployment/spec.md) — Especificaciones formales.
