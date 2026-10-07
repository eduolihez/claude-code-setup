# Diseño: repositorio `claude-code-setup`

Fecha: 2026-10-07 · Autor: eduolihez · Estado: pendiente de revisión

## 1. Objetivo

Repositorio público de GitHub con el setup de Claude Code de un analista SOC / Blue Team que automatiza con Python, participa en hackathons y desarrolla su web y proyectos propios.

Criterios de éxito:

- Un equipo nuevo reproduce el setup con un solo comando (`install.ps1`).
- Ningún secreto ni dato personal llega al repo ni a su historial.
- Cada pieza (instalador, hooks, agentes, skills) tiene verificación automática.
- El repo sirve de portfolio: README claro, estructura limpia, CI en verde.

## 2. Alcance

**Fase 1 (este spec):** subir el setup actual con seguridad y documentación, más un conjunto acotado de contenido nuevo.

**Fuera de alcance (roadmap):** plugin con marketplace propio (Fase 2), `install.sh` para Linux/macOS, hooks adicionales, más agentes y skills.

## 3. Supuestos

- Solo se publica la configuración portable. Quedan fuera credenciales, historial, sesiones, proyectos, backups, telemetría y snapshots.
- Las skills de terceros (gstack y similares) no se copian. Se documentan como dependencias.
- Los hooks existentes están en PowerShell, así que la Fase 1 es Windows-first.
- Licencia MIT. Repo local en `<ruta-local>`; remoto `eduolihez/claude-code-setup` (nombre modificable).

## 4. Estructura

```
claude-code-setup/
├── README.md
├── LICENSE
├── SECURITY.md
├── CHANGELOG.md
├── install.ps1
├── .gitignore                # allowlist
├── .gitleaks.toml
├── .github/workflows/ci.yml
├── claude/                   # espejo portable de ~/.claude
│   ├── CLAUDE.md
│   ├── settings.json
│   ├── agents/
│   ├── skills/               # solo skills propias
│   └── hooks/
├── templates/
│   ├── python-automation.md
│   ├── hackathon.md
│   ├── web.md
│   └── soc-detection.md
├── tests/                    # Pester + validación de frontmatter
├── docs/
│   ├── dependencies.md
│   ├── roadmap.md
│   └── superpowers/specs/
└── plugin/README.md          # placeholder de Fase 2
```

## 5. Seguridad de publicación

1. `.gitignore` en modo allowlist: se ignora todo salvo rutas listadas explícitamente.
2. Revisión manual de cada archivo candidato antes del primer commit: rutas con el nombre de usuario local, tokens, correos y datos personales.
3. `settings.json` publicable. Los valores personales van a `settings.local.json`, ignorado.
4. gitleaks en CI y como pre-commit local opcional.
5. El repo se crea **privado**. Antes de hacerlo público: escaneo con gitleaks del árbol y del historial, y revisión de la salida con el usuario. Pasar a público requiere su confirmación explícita.
6. `SECURITY.md` documenta qué no se publica y cómo reportar problemas.

## 6. Instalador (`install.ps1`)

- Gestiona solo una lista fija de rutas: `CLAUDE.md`, `settings.json`, `agents/`, `hooks/` y las skills propias. Nunca toca `.credentials.json`, `projects/`, `sessions/` ni `history.jsonl`.
- Modo por defecto: symlinks. Si Windows no permite crearlos (sin modo desarrollador ni admin), usa copia y avisa.
- Antes de modificar nada, mueve lo existente a `~/.claude/backups/setup-YYYYMMDD-HHMMSS/`.
- Flags: `-DryRun`, `-Copy`, `-Uninstall`.
- `-Uninstall` devuelve cada ruta gestionada a su estado previo a instalar: la restaura desde el backup `setup-*` más antiguo que la contiene, o la quita si no está en ninguno. Antes, lo instalado que difiere del repo (por ejemplo, memoria `#` añadida a `CLAUDE.md`) se mueve a `~/.claude/backups/pre-uninstall-YYYYMMDD-HHMMSS/`. Los backups se conservan.
- Un enlace previo del usuario en una ruta gestionada se mueve tal cual al backup y `-Uninstall` lo recrea.
- Las rutas de hooks en `settings.json` usan `%USERPROFILE%`.
- Al terminar, verifica cada destino e imprime el resultado. Termina con código distinto de cero si algo falla.

## 7. Templates

`CLAUDE.md` base por tipo de proyecto. Estructura común: contexto, comandos de test y lint, convenciones, reglas de seguridad, definición de "hecho".

| Template | Contenido clave |
|---|---|
| `python-automation.md` | `uv`/`venv`, `ruff`, `pytest`, tipado, logging, secretos por variables de entorno, scripts idempotentes |
| `hackathon.md` | MVP primero, demo-first, checklist de entrega, README de pitch |
| `web.md` | Stack, build y deploy, accesibilidad, rendimiento, validación de entradas |
| `soc-detection.md` | Sigma/YARA, mapeo a MITRE ATT&CK, datos de ejemplo sanitizados, tuning de falsos positivos |

`web.md` y `hackathon.md` llevan marcadores `<!-- completar -->` en lo que depende del stack del usuario, que debe aportarse antes de cerrar la Fase 1 o quedará en el roadmap.

## 8. Contenido nuevo de Fase 1

| Pieza | Tipo | Función |
|---|---|---|
| `alert-triage` | agente (solo lectura) | Hipótesis, evidencia a pedir, severidad y siguientes pasos para una alerta sanitizada. No ejecuta acciones |
| `detection-engineer` | agente (solo lectura) | Escribe y revisa reglas Sigma/YARA, mapeo ATT&CK, casos de prueba y falsos positivos |
| `hackathon-scaffold` | skill | Arranca un proyecto de hackathon: MVP, README de pitch, checklist de entrega |
| `ioc-defang` | skill | Defangea IOCs (URLs, IPs, dominios) antes de pegarlos en docs o commits |
| `block-secrets-write.ps1` | hook PreToolUse (Write/Edit) | Bloquea escrituras con patrones de secretos |

Se mantienen `plan-checker` y `security-reviewer`. Los agentes nuevos no reciben herramientas de escritura ni de ejecución.

Reglas del contenido SOC: nunca incluir logs ni IOCs reales de entornos del usuario; los ejemplos son sintéticos o están sanitizados.

## 9. Documentación

- `README.md`: qué es, instalación en pocos comandos, árbol del repo, qué hace cada pieza, filosofía. Texto de cara al público, por lo que pasa por la skill `humanizer` antes de entregarse.
- `docs/dependencies.md`: plugins y skills de terceros con enlace y comando de instalación.
- `docs/roadmap.md`: Fase 2 (plugin con agentes y skills SOC), Linux/macOS, más hooks.
- `CHANGELOG.md` desde la primera versión.

## 10. Verificación

- **Pester:** `install.ps1` en directorio temporal (`-DryRun`, instalar, desinstalar, no tocar credenciales, fallback a copia). Hooks con entradas maliciosas y benignas.
- **Validación de frontmatter:** script que comprueba `name` y `description` en cada agente y skill.
- **CI (GitHub Actions):** gitleaks, PSScriptAnalyzer, Pester, markdownlint en cada push y pull request.
- **Pre-publicación:** gitleaks sobre árbol e historial, con la salida mostrada al usuario.
- Cada afirmación de "hecho" se apoya en la salida del comando correspondiente.

## 11. Orden de entrega

1. Repo local, allowlist, revisión de secretos, instalador y tests.
2. Contenido nuevo (agentes, skills, hook).
3. README, docs y CI.
4. Creación del repo en GitHub como privado, escaneo y, con confirmación del usuario, paso a público.

## 12. Riesgos

| Riesgo | Mitigación |
|---|---|
| Fuga de secretos o datos personales | Allowlist, revisión manual, gitleaks, repo privado hasta verificar |
| Symlinks no permitidos en Windows | Fallback automático a copia |
| El instalador sobrescribe config existente | Backup previo y `-DryRun` |
| Licencia de contenido de terceros | No se copia; solo se documenta como dependencia |
| Templates genéricos sin valor | Empiezan breves y se afinan con uso real; el usuario aporta su stack |
