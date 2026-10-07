# claude-code-setup

Mi configuración de Claude Code, versionada y reproducible. Incluye instrucciones globales, agentes, skills, hooks de seguridad y plantillas de `CLAUDE.md` por tipo de proyecto. Está pensada para trabajo de SOC / Blue Team, automatización con Python, hackathons y desarrollo web propio, pero cualquiera puede clonarla y adaptarla.

## Instalación

Requiere Windows con PowerShell 5.1.

```powershell
git clone https://github.com/eduolihez/claude-code-setup.git
cd claude-code-setup
.\install.ps1 -DryRun     # muestra qué haría, sin tocar nada
.\install.ps1             # instala en %USERPROFILE%\.claude
.\install.ps1 -Uninstall  # restaura el backup más reciente
```

Parámetros de `install.ps1`:

- `-TargetDir`: carpeta de destino. Por defecto `%USERPROFILE%\.claude`.
- `-Copy`: copia los archivos en lugar de enlazarlos.
- `-DryRun`: simula la operación e imprime los pasos.
- `-Uninstall`: quita lo instalado y restaura el backup más reciente. Si no hay backups, aborta sin borrar nada.

Por defecto el instalador crea enlaces simbólicos, así que editar el repo cambia la configuración activa. En Windows eso exige modo desarrollador o una consola de administrador. Sin ese permiso, el instalador avisa y copia los archivos. Lo que ya existía en el destino se guarda antes en `backups\setup-<fecha>` dentro de `TargetDir`.

El instalador solo gestiona `CLAUDE.md`, `settings.json`, `agents/`, `hooks/` y las carpetas de `skills/` que están en este repo. No toca credenciales, historial, sesiones ni otras skills que ya tengas.

## Estructura

```text
claude/
  CLAUDE.md        instrucciones globales
  settings.json    permisos, hooks, statusline y plugin
  agents/          plan-checker, security-reviewer, alert-triage, detection-engineer
  skills/          commit, handoff, log-decision, hackathon-scaffold, ioc-defang
  hooks/           block-dangerous.ps1, block-secrets-write.ps1, statusline.ps1
templates/         CLAUDE.md por tipo de proyecto
docs/              dependencias, roadmap y documentos de diseño
plugin/            reservado para la Fase 2
scripts/           utilidades de los tests
tests/             tests Pester
install.ps1        instalador
```

## Qué hace cada pieza

### Agentes

- `plan-checker`: compara el diff con `SPEC.md` y reporta huecos.
- `security-reviewer`: revisa el código en busca de vulnerabilidades.
- `alert-triage`: triage de una alerta SOC ya sanitizada. Propone hipótesis, evidencia a pedir, severidad y siguientes pasos.
- `detection-engineer`: redacta reglas Sigma o YARA con mapeo a ATT&CK, casos de prueba y ajuste de falsos positivos.

### Skills

- `commit`: revisa el diff, separa en commits pequeños y redacta los mensajes.
- `handoff`: guarda el estado de la sesión antes de limpiar contexto.
- `log-decision`: registra una decisión de diseño en `DECISIONS.md`.
- `hackathon-scaffold`: prepara un proyecto de hackathon con MVP, estructura mínima, README de pitch y checklist de entrega.
- `ioc-defang`: neutraliza IOCs (URLs, IPs, dominios, emails) antes de ponerlos en documentos, tickets o commits.

### Hooks

- `block-dangerous.ps1`: bloquea `rm -rf` y `git push` forzado.
- `block-secrets-write.ps1`: bloquea escrituras (Write y Edit) cuyo contenido parece una clave de AWS, un token de GitHub, Anthropic o Slack, o una clave privada.
- `statusline.ps1`: línea de estado de Claude Code.

### Templates

Plantillas de `CLAUDE.md` para copiar a la raíz de un proyecto:

- [python-automation](templates/python-automation.md)
- [soc-detection](templates/soc-detection.md)
- [hackathon](templates/hackathon.md)
- [web](templates/web.md)

`hackathon` y `web` aún tienen marcadores `<!-- completar -->` a la espera del stack. Ver el [roadmap](docs/roadmap.md).

## Dependencias

El plugin `superpowers` y las skills de terceros no viven en este repo. Detalle en [docs/dependencies.md](docs/dependencies.md).

## Tests

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tests/Invoke-Tests.ps1
```

Necesita Pester 5.5 o superior. Los tests del instalador usan carpetas temporales y no tocan tu `.claude`. Los de modo enlace solo corren si la máquina puede crear symlinks.

La integración continua ejecuta gitleaks, PSScriptAnalyzer, Pester y markdownlint en cada push y pull request.

### Pre-commit local (opcional)

```powershell
git config core.hooksPath .githooks
```

Activa el hook de `.githooks/pre-commit` antes de cada commit.

## Seguridad

Qué se publica y qué no, y cómo reportar un problema: [SECURITY.md](SECURITY.md).

## Licencia

MIT. Ver [LICENSE](LICENSE).
