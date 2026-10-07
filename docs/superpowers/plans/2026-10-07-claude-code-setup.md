# claude-code-setup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Publicar el setup de Claude Code de eduolihez como repo de GitHub reproducible con un comando, sin fugas de secretos y con verificación automática.

**Architecture:** Repo espejo de `~/.claude` (carpeta `claude/`) con `.gitignore` en allowlist, un instalador PowerShell que enlaza o copia con backup previo, contenido propio (agentes, skills, hook) validado por tests Pester, y CI con gitleaks, PSScriptAnalyzer, Pester y markdownlint. El repo nace privado y solo pasa a público con confirmación explícita.

**Tech Stack:** Windows PowerShell 5.1, Pester 5.x, PSScriptAnalyzer, markdownlint-cli2, gitleaks (Docker), GitHub Actions, `gh` CLI.

**Spec:** `docs/superpowers/specs/2026-10-07-claude-code-setup-design.md`

## Global Constraints

- Repo local `<ruta-local>`; remoto `eduolihez/claude-code-setup`; licencia MIT.
- Solo existe Windows PowerShell 5.1 (`powershell.exe`, no hay `pwsh`). Prohibido `?:`, `&&`, `??` y `ConvertFrom-Json -AsHashtable`.
- Los `.ps1` son ASCII puro (mensajes en español sin tildes): PS 5.1 lee UTF-8 sin BOM como ANSI. Los tests que necesiten caracteres no ASCII los construyen con `[char]0xF1`.
- El Pester 3.4.0 preinstalado no sirve: los tests usan sintaxis Pester >= 5.5 (`BeforeAll`, `Should -Be`).
- gitleaks no está instalado: se ejecuta con `docker run --rm -v <repo>:/repo zricethezav/gitleaks:latest ...`.
- Los fixtures de secretos en tests se construyen en tiempo de ejecución (`'AKIA' + 'IOSFODNN7EXAMPLE'`) para no disparar gitleaks sobre el propio repo. Los IOCs de ejemplo usan rangos reservados (`example.com`, `192.0.2.0/24`).
- Rutas gestionadas por el instalador, y solo estas: `CLAUDE.md`, `settings.json`, cada archivo de `claude/agents/` y `claude/hooks/`, y cada carpeta de `claude/skills/`. Nunca `.credentials.json`, `projects/`, `sessions/` ni `history.jsonl`.
- Backups en `<TargetDir>\backups\setup-YYYYMMDD-HHMMSS\`. Flags del instalador: `-DryRun`, `-Copy`, `-Uninstall`. Falla con código distinto de cero si algo no verifica.
- Rutas de hooks en `settings.json` usan `%USERPROFILE%`; ningún archivo versionado contiene rutas de perfil (`C:` + `\Users\...`) ni el nombre de usuario local (salvo el handle público `eduolihez` en docs).
- Agentes nuevos: `tools: Read, Grep, Glob` (sin escritura ni ejecución).
- CI en cada `push` y `pull_request`: gitleaks, PSScriptAnalyzer, Pester, markdownlint.
- Commits pequeños en imperativo, sin force-push; cada mensaje termina con `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`.
- Texto de cara al público (README, SECURITY) pasa por la skill `humanizer` antes de commitear.
- No crear el repo remoto, ni hacerlo público, sin la confirmación del usuario descrita en las Tasks 13 y 14.

## Review Focus

1. Hook con stdin vacío o JSON inválido: debe devolver `{}` con exit 0, sin traza de error (Tasks 4 y 5).
2. Variantes de comandos peligrosos que esquivan el regex actual: `rm -fr`, `rm -r -f`, `RM -RF`, `git push -f` (Task 4).
3. Archivos con finales de línea CRLF (autocrlf en Windows) al leer frontmatter (Task 2).
4. `TargetDir` con espacios y caracteres no ASCII, o que apunta a un archivo (Task 6).
5. Desinstalar enlaces simbólicos de carpetas sin borrar el contenido del repo; `-Uninstall` sin backup no borra nada (Task 7).

---

### Task 1: Arnés de tests y `.gitignore` en allowlist

**Files:**
- Create: `.gitignore`, `.gitattributes`, `LICENSE`, `tests/Invoke-Tests.ps1`, `tests/helpers.ps1`, `tests/Gitignore.Tests.ps1`

**Interfaces:**
- Produces: `tests/Invoke-Tests.ps1` (sin parámetros; ejecuta `tests/` con Pester 5, exit 1 si hay fallos) y `Test-GitIgnored -RepoRoot <string> -Path <string> -> [bool]` en `tests/helpers.ps1` (usa `git check-ignore -q`, exit 0 = ignorado).

- [ ] **Step 1: Instalar Pester 5** — `powershell -NoProfile -Command "Install-Module Pester -MinimumVersion 5.5 -Scope CurrentUser -Force -SkipPublisherCheck"`. Verificar con `Get-Module -ListAvailable Pester`: aparece una versión >= 5.5.
- [ ] **Step 2: Escribir `tests/Gitignore.Tests.ps1` (fallará)**. Casos `-ForEach`:
  - Ignorados: `claude/.credentials.json`, `claude/settings.local.json`, `claude/history.jsonl`, `claude/projects/p/a.jsonl`, `claude/sessions/s.json`, `claude/backups/b`, `claude/hooks/token.txt`, `.env`.
  - No ignorados: `README.md`, `LICENSE`, `.gitattributes`, `.gitleaks.toml`, `install.ps1`, `claude/CLAUDE.md`, `claude/settings.json`, `claude/agents/a.md`, `claude/hooks/a.ps1`, `claude/skills/s/SKILL.md`, `templates/web.md`, `docs/roadmap.md`, `tests/X.Tests.ps1`, `scripts/Get-Frontmatter.ps1`, `.github/workflows/ci.yml`, `.githooks/pre-commit`, `plugin/README.md`, `PSScriptAnalyzerSettings.psd1`, `.markdownlint.jsonc`.
- [ ] **Step 3: Ejecutar** `powershell -NoProfile -File tests/Invoke-Tests.ps1`. Esperado: FAIL (todos los ignorados salen como no ignorados).
- [ ] **Step 4: Escribir `.gitignore`**: `*` y luego `!` explícitos por directorio (re-incluir cada directorio padre antes de sus archivos). Dentro de `claude/` solo `CLAUDE.md`, `settings.json`, `agents/*.md`, `hooks/*.ps1`, `skills/*/SKILL.md`. `.gitattributes`: `* text=auto eol=lf`. `LICENSE`: MIT, 2026, eduolihez.
- [ ] **Step 5: Ejecutar** el runner. Esperado: todos los casos PASS, exit 0.
- [ ] **Step 6: Commit** — `git add -A && git commit -m "chore: añade arnés Pester, allowlist de .gitignore y licencia MIT"`.

### Task 2: Lector de frontmatter

**Files:**
- Create: `scripts/Get-Frontmatter.ps1`, `tests/Frontmatter.Tests.ps1`

**Interfaces:**
- Produces: `Get-Frontmatter -Path <string> -> [System.Collections.Specialized.OrderedDictionary]` con claves y valores de las líneas `clave: valor` entre las dos primeras líneas `---`. Lanza `"Frontmatter ausente: <path>"` si falta el delimitador de apertura o de cierre.

- [ ] **Step 1: Escribir los tests (fallan)** con archivos en `TestDrive:`:
  - `lee name y description de un archivo válido`.
  - `conserva el valor completo cuando contiene dos puntos` (`description: a: b` devuelve `a: b`).
  - `lanza si no hay delimitador de apertura` y `lanza si no hay delimitador de cierre`.
  - `lee frontmatter con finales de línea CRLF` (escribir el archivo con `` `r`n ``; `name` no debe acabar en `` `r ``).
- [ ] **Step 2: Ejecutar** `Invoke-Tests.ps1`. Esperado: FAIL, `Get-Frontmatter` no existe.
- [ ] **Step 3: Implementar `Get-Frontmatter`** en `scripts/Get-Frontmatter.ps1` (leer con `Get-Content -Raw`, dividir por `\r?\n`, separar por el primer `:`, recortar).
- [ ] **Step 4: Ejecutar** el runner. Esperado: PASS.
- [ ] **Step 5: Commit** — `feat: añade lector de frontmatter para validar agentes y skills`.

### Task 3: Importar el setup actual

**Files:**
- Create: `claude/CLAUDE.md`, `claude/settings.json`, `claude/agents/plan-checker.md`, `claude/agents/security-reviewer.md`, `claude/hooks/block-dangerous.ps1`, `claude/hooks/statusline.ps1`, `claude/skills/commit/SKILL.md`, `claude/skills/handoff/SKILL.md`, `claude/skills/log-decision/SKILL.md`, `tests/Definitions.Tests.ps1`

**Interfaces:**
- Consumes: `Get-Frontmatter` (Task 2).
- Produces: `tests/Definitions.Tests.ps1` con tests que recorren `claude/agents/*.md` y `claude/skills/*/SKILL.md`; las Tasks 5, 8 y 9 añaden casos aquí.

- [ ] **Step 1: Escribir `Definitions.Tests.ps1` (falla)**:
  - Cada agente: `name` igual al nombre de archivo sin extensión, `description` y `tools` no vacíos.
  - Cada skill: `name` igual al nombre de su carpeta, `description` no vacía.
  - `settings.json` es JSON válido y su texto no contiene rutas de perfil (`C:` + `\Users`) ni el nombre de usuario local.
  - Todo `command` de hook en `settings.json` contiene `%USERPROFILE%`.
  - `claude/` no contiene `.credentials.json`, `history.jsonl`, `projects`, `sessions` ni `backups`.
- [ ] **Step 2: Ejecutar** el runner. Esperado: FAIL (no existe `claude/`).
- [ ] **Step 3: Copiar** desde `<ruta-local-de-.claude>` solo los 9 archivos de la lista (`Copy-Item`, nunca el directorio entero).
- [ ] **Step 4: Revisión manual de secretos**: `git grep -n -i -P "token|secret|password|api[_-]?key|<usuario>|C:\x5c+Users"` sobre `claude/` (`<usuario>` es el nombre de usuario local). Esperado: sin coincidencias; si aparece alguna, se corrige antes de continuar y se muestra al usuario.
- [ ] **Step 5: Ejecutar** el runner. Esperado: PASS.
- [ ] **Step 6: Commit** — `feat: importa el setup actual (CLAUDE.md, settings, agentes, hooks y skills propias)`.

### Task 4: Tests y endurecimiento de `block-dangerous.ps1`

**Files:**
- Modify: `claude/hooks/block-dangerous.ps1`, `tests/helpers.ps1`
- Test: `tests/BlockDangerous.Tests.ps1`

**Interfaces:**
- Produces: `Invoke-Script -Path <string> [-StdinText <string>] [-Arguments <string[]>] -> [pscustomobject]@{ExitCode; Stdout; Stderr}` en `tests/helpers.ps1` (lanza `powershell.exe -NoProfile -ExecutionPolicy Bypass -File` con `System.Diagnostics.Process` y stdin redirigido).
- Contrato del hook: entrada `{"tool_input":{"command":"..."}}`; salida `{}` o `{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"<texto>"}}`.

- [ ] **Step 1: Escribir los tests (algunos fallan)**:
  - Deny: `rm -rf /tmp/x`, `rm -fr dir`, `rm -r -f dir`, `RM -RF dir`, `git push --force origin main`, `git push -f origin main`, `git push --force-with-lease`. Cada uno con `permissionDecision` igual a `deny` y `permissionDecisionReason` no vacío.
  - Allow (`{}`): `git status`, `rm file.txt`, `git push origin main`, `npm run test`.
  - `devuelve {} con stdin vacío`, `devuelve {} con JSON inválido`, `devuelve {} si falta tool_input.command` (JSON de otra herramienta). Todos con exit 0 y Stderr vacío.
- [ ] **Step 2: Ejecutar** el runner. Esperado: FAIL en `rm -fr`, `rm -r -f`, `git push -f` y en los casos de entrada inválida.
- [ ] **Step 3: Modificar el hook**: parseo dentro de `try/catch` que devuelve `{}`, y regex que cubra las variantes (insensible a mayúsculas, combinaciones de `-r`/`-f` en cualquier orden, `-f` y `--force` en `git push`). Añadir `permissionDecisionReason`.
- [ ] **Step 4: Ejecutar** el runner. Esperado: PASS.
- [ ] **Step 5: Commit** — `fix: block-dangerous cubre variantes de rm y force-push y tolera entrada inválida`.

### Task 5: Hook `block-secrets-write.ps1`

**Files:**
- Create: `claude/hooks/block-secrets-write.ps1`, `tests/BlockSecretsWrite.Tests.ps1`
- Modify: `claude/settings.json`, `tests/Definitions.Tests.ps1`

**Interfaces:**
- Consumes: `Invoke-Script` (Task 4).
- Contrato: entrada `{"tool_name":"Write","tool_input":{"content":"..."}}` o `{"tool_name":"Edit","tool_input":{"new_string":"..."}}`. Salida `{}` o `deny` con razón que nombra el tipo de secreto y nunca lo reproduce.
- Patrones (nombre en la razón): `AKIA[0-9A-Z]{16}` (AWS), `gh[pousr]_[A-Za-z0-9]{36,}` (GitHub), `sk-ant-[A-Za-z0-9_-]{20,}` (Anthropic), `xox[baprs]-[A-Za-z0-9-]{10,}` (Slack), `-----BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY-----` (clave privada).

- [ ] **Step 1: Escribir los tests (fallan)**:
  - Un caso de deny por patrón, para `Write` (campo `content`) y para `Edit` (campo `new_string`), con el secreto construido en tiempo de ejecución. Se comprueba que `Stdout` no contiene el secreto y que la razón nombra el tipo.
  - Benignos con `{}`: código normal, la palabra `password` en prosa, `AKIA123` (demasiado corto), `ghp_abc` (demasiado corto).
  - `devuelve {} con stdin vacío`, `con JSON inválido` y `sin content ni new_string`, todos con exit 0 y Stderr vacío.
- [ ] **Step 2: Añadir a `Definitions.Tests.ps1`**: `settings.json` tiene una entrada `PreToolUse` cuyo `matcher` cubre `Write` y `Edit` y cuyo `command` referencia `block-secrets-write.ps1`; todo script de hook referenciado en `settings.json` existe en `claude/hooks/`.
- [ ] **Step 3: Ejecutar** el runner. Esperado: FAIL.
- [ ] **Step 4: Implementar el hook** con la misma estructura de `try/catch` que `block-dangerous.ps1`, y registrarlo en `settings.json` con comando `powershell -NoProfile -ExecutionPolicy Bypass -File "%USERPROFILE%\.claude\hooks\block-secrets-write.ps1"`.
- [ ] **Step 5: Ejecutar** el runner. Esperado: PASS.
- [ ] **Step 6: Commit** — `feat: añade hook que bloquea escritura de secretos`.

### Task 6: Instalador en modo copia

**Files:**
- Create: `install.ps1`, `tests/Install.Tests.ps1`

**Interfaces:**
- Consumes: `Invoke-Script` (Task 4).
- Produces: `install.ps1 [-TargetDir <string> = "$env:USERPROFILE\.claude"] [-Copy] [-DryRun]`. Esta task implementa solo copia (acepta `-Copy`, aún no enlaza). Devuelve 0 si todo se verificó, 1 si no. La Task 7 añade symlinks y `-Uninstall`.

- [ ] **Step 1: Escribir los tests (fallan)**; cada uno prepara un `TargetDir` en `TestDrive:` con `.credentials.json`, `history.jsonl`, `projects/p.txt`, `sessions/s.json`, `skills/gstack/SKILL.md` y `agents/mine.md`:
  - `copia todas las rutas gestionadas idénticas al repo` (hash por archivo, exit 0).
  - `mueve un CLAUDE.md existente a backups/setup-<timestamp>/CLAUDE.md`.
  - `no modifica credenciales, historial, proyectos, sesiones ni skills y agentes ajenos` (hash antes y después; ninguno aparece en el backup).
  - `-DryRun no cambia nada` (hash del árbol igual, sin carpeta `backups`, salida con prefijo `[DryRun]`).
  - `es idempotente`: segunda ejecución exit 0 y sin nueva carpeta de backup.
  - `funciona con TargetDir con espacios y caracteres no ASCII` (nombre con `[char]0xF1`).
  - `falla con exit distinto de cero si TargetDir es un archivo`, sin modificar nada.
- [ ] **Step 2: Ejecutar** el runner. Esperado: FAIL.
- [ ] **Step 3: Implementar `install.ps1`**: enumerar entradas gestionadas desde `claude/` según la lista de Global Constraints; backup previo solo de lo que difiere; copia; verificación final por entrada con resumen impreso. La marca de tiempo del backup no debe colisionar entre dos ejecuciones en el mismo segundo.
- [ ] **Step 4: Ejecutar** el runner. Esperado: PASS.
- [ ] **Step 5: Commit** — `feat: añade install.ps1 en modo copia con backup y dry-run`.

### Task 7: Symlinks por defecto, fallback y `-Uninstall`

**Files:**
- Modify: `install.ps1`, `tests/Install.Tests.ps1`

**Interfaces:**
- Consumes: parámetros de la Task 6.
- Produces: `install.ps1 ... [-Uninstall]`. Sin `-Copy` enlaza cada entrada gestionada; si no puede crear symlinks (o `CLAUDE_SETUP_NO_SYMLINK=1`) copia e imprime un aviso que contiene la palabra `copia`.

- [ ] **Step 1: Añadir tests (fallan)**:
  - Con symlinks (`-Skip` si el entorno no permite crearlos, sondeo en `BeforeDiscovery`): cada entrada gestionada tiene `LinkType` igual a `SymbolicLink` y apunta al repo; reinstalar no crea backup nuevo.
  - Con `CLAUDE_SETUP_NO_SYMLINK=1`: entradas como archivos normales, aviso con `copia`, exit 0.
  - `-Uninstall` tras instalar sobre un `CLAUDE.md` con marcador: elimina lo gestionado, restaura el marcador y no toca lo ajeno.
  - `-Uninstall` tras instalar con symlinks no borra nada dentro del repo (el contenido de `claude/skills/` y `claude/CLAUDE.md` sigue intacto).
  - `-Uninstall` sin carpeta de backups: exit distinto de cero, mensaje claro y nada borrado.
  - `-Uninstall -DryRun` no cambia nada.
- [ ] **Step 2: Ejecutar** el runner. Esperado: FAIL.
- [ ] **Step 3: Implementar** enlace por entrada y desinstalación. Para quitar un symlink de carpeta usar `[System.IO.Directory]::Delete($path)` (sin recursión): `Remove-Item -Recurse` en PS 5.1 puede borrar el contenido del destino. Restaurar desde el backup más reciente.
- [ ] **Step 4: Ejecutar** el runner. Esperado: PASS.
- [ ] **Step 5: Commit** — `feat: instalador enlaza por defecto, cae a copia y añade -Uninstall`.

### Task 8: Agentes `alert-triage` y `detection-engineer`

**Files:**
- Create: `claude/agents/alert-triage.md`, `claude/agents/detection-engineer.md`
- Modify: `tests/Definitions.Tests.ps1`

- [ ] **Step 1: Añadir tests (fallan)**: ambos agentes existen con `tools` exactamente `Read, Grep, Glob`; el cuerpo de `alert-triage` contiene `sanitiz` y `Severidad`; el de `detection-engineer` contiene `Sigma`, `YARA` y `ATT&CK`.
- [ ] **Step 2: Ejecutar** el runner. Esperado: FAIL.
- [ ] **Step 3: Escribir los dos agentes** en español, menos de 40 líneas cada uno. `alert-triage`: entrada esperada (alerta sanitizada), salida con secciones Hipótesis, Evidencia a pedir, Severidad con justificación, Siguientes pasos y Falsos positivos probables; pide sanitizar si ve IOCs reales o credenciales; no inventa telemetría; no ejecuta acciones. `detection-engineer`: salida Sigma o YARA, mapeo ATT&CK solo con IDs de los que esté seguro, casos de prueba positivos y negativos, falsos positivos y ajuste; recomienda validar con `sigma check` sin ejecutarlo.
- [ ] **Step 4: Ejecutar** el runner. Esperado: PASS.
- [ ] **Step 5: Commit** — `feat: añade agentes alert-triage y detection-engineer`.

### Task 9: Skills `hackathon-scaffold` e `ioc-defang`

**Files:**
- Create: `claude/skills/hackathon-scaffold/SKILL.md`, `claude/skills/ioc-defang/SKILL.md`
- Modify: `tests/Definitions.Tests.ps1`

- [ ] **Step 1: Añadir tests (fallan)**: `hackathon-scaffold` tiene `disable-model-invocation: true` y su cuerpo menciona `MVP`, `README` y `checklist`; `ioc-defang` contiene los ejemplos `hxxps://example[.]com` y `192[.]0[.]2[.]1`.
- [ ] **Step 2: Ejecutar** el runner. Esperado: FAIL.
- [ ] **Step 3: Escribir las skills** en español. `hackathon-scaffold`: pasos para fijar el MVP, estructura mínima, README de pitch y checklist de entrega. `ioc-defang`: reglas (`http` a `hxxp`, `.` a `[.]` en dominios e IPs, `@` a `[@]`), qué no tocar (código ejecutable), y los ejemplos con rangos reservados.
- [ ] **Step 4: Ejecutar** el runner. Esperado: PASS.
- [ ] **Step 5: Commit** — `feat: añade skills hackathon-scaffold e ioc-defang`.

### Task 10: Templates por tipo de proyecto

**Files:**
- Create: `templates/python-automation.md`, `templates/hackathon.md`, `templates/web.md`, `templates/soc-detection.md`, `tests/Templates.Tests.ps1`

- [ ] **Step 1: Pedir al usuario su stack** para `web.md` (framework, build, deploy) y `hackathon.md` (stack habitual). Si no lo da, esas secciones llevan `<!-- completar -->` y la Task 11 lo registra en el roadmap.
- [ ] **Step 2: Escribir `Templates.Tests.ps1` (falla)**: cada template tiene los encabezados `## Contexto`, `## Comandos`, `## Convenciones`, `## Seguridad` y `## Definición de hecho`; `web.md` y `hackathon.md` contienen `<!-- completar -->` solo si falta el stack; `python-automation.md` menciona `ruff` y `pytest`; `soc-detection.md` menciona `MITRE ATT&CK`, `Sigma` y `sanitiz`.
- [ ] **Step 3: Ejecutar** el runner. Esperado: FAIL.
- [ ] **Step 4: Escribir los 4 templates**, breves, con el contenido clave de la sección 7 del spec.
- [ ] **Step 5: Ejecutar** el runner. Esperado: PASS.
- [ ] **Step 6: Commit** — `feat: añade templates de CLAUDE.md por tipo de proyecto`.

### Task 11: Documentación

**Files:**
- Create: `README.md`, `SECURITY.md`, `CHANGELOG.md`, `docs/dependencies.md`, `docs/roadmap.md`, `plugin/README.md`, `.markdownlint.jsonc`, `tests/Docs.Tests.ps1`

- [ ] **Step 1: Averiguar el origen de las skills de terceros** (gstack): buscar un `.git` o README dentro de `~/.claude/skills/gstack/`. No inventar URLs; si no se encuentra, preguntar al usuario.
- [ ] **Step 2: Escribir `Docs.Tests.ps1` (falla)**: todo enlace relativo de los `*.md` del repo resuelve a un archivo existente; `README.md` contiene `install.ps1`, `-DryRun` y enlaces a los 4 templates; `docs/dependencies.md` contiene `obra/superpowers-marketplace`; `CHANGELOG.md` contiene `## [0.1.0]`.
- [ ] **Step 3: Ejecutar** el runner. Esperado: FAIL.
- [ ] **Step 4: Escribir los documentos**. README: qué es, instalación, árbol, qué hace cada pieza, pre-commit local opcional (`git config core.hooksPath .githooks`). `SECURITY.md`: qué no se publica y cómo reportar. `docs/roadmap.md`: Fase 2 (plugin SOC), Linux/macOS, más hooks y, si aplica, el stack pendiente de `web.md` y `hackathon.md`. `.markdownlint.jsonc` sin límite de longitud de línea.
- [ ] **Step 5: Aplicar la skill `humanizer`** a `README.md` y `SECURITY.md`.
- [ ] **Step 6: Verificar** — `powershell -NoProfile -File tests/Invoke-Tests.ps1` (PASS) y `npx markdownlint-cli2 "**/*.md"` (esperado: 0 errores).
- [ ] **Step 7: Commit** — `docs: añade README, SECURITY, CHANGELOG, dependencias y roadmap`.

### Task 12: CI, gitleaks y pre-commit local

**Files:**
- Create: `.gitleaks.toml`, `.github/workflows/ci.yml`, `.githooks/pre-commit`, `PSScriptAnalyzerSettings.psd1`, `tests/Ci.Tests.ps1`

- [ ] **Step 1: Escribir `Ci.Tests.ps1` (falla)**: `ci.yml` contiene `pull_request`, `push`, `gitleaks`, `Invoke-ScriptAnalyzer`, `Invoke-Tests.ps1` y `markdownlint`; `.githooks/pre-commit` contiene `gitleaks protect --staged`.
- [ ] **Step 2: Ejecutar** el runner. Esperado: FAIL.
- [ ] **Step 3: Escribir los archivos**. Workflow con dos jobs: gitleaks (checkout con `fetch-depth: 0`) y calidad en `windows-latest` (instala Pester >= 5.5 y PSScriptAnalyzer, ejecuta analizador, `tests/Invoke-Tests.ps1` y markdownlint-cli2). `.gitleaks.toml` extiende la configuración por defecto. `PSScriptAnalyzerSettings.psd1` excluye solo las reglas que se justifiquen, cada una con comentario.
- [ ] **Step 4: Verificar**:
  - `docker run --rm -v "<ruta-local>:/repo" rhysd/actionlint:latest -color` sin salida.
  - `Invoke-ScriptAnalyzer -Path . -Recurse -Settings PSScriptAnalyzerSettings.psd1` sin resultados.
  - El runner pasa en verde.
- [ ] **Step 5: Commit** — `ci: añade workflow, configuración de gitleaks y pre-commit opcional`.

### Task 13: Verificación previa y repo privado

**Files:** ninguno nuevo (solo comandos de verificación y publicación).

- [ ] **Step 1: Verificación completa**, mostrando cada salida al usuario:
  - `powershell -NoProfile -ExecutionPolicy Bypass -File tests/Invoke-Tests.ps1`: 0 fallos.
  - `Invoke-ScriptAnalyzer ...` y `npx markdownlint-cli2 "**/*.md" "#docs/superpowers" "#.superpowers" "#node_modules"`: sin hallazgos.
  - `docker run --rm -v "<ruta-local>:/repo" zricethezav/gitleaks:latest detect --source /repo --log-opts="--all" -v`: `no leaks found`.
  - `git ls-files` comparado con la allowlist, y `git grep -n -I -P "(?i)<usuario>(?!ihez)|C:\x5c+Users"` sin salida, sustituyendo `<usuario>` por el nombre de usuario local (la barra invertida va como `\x5c` para que el comando funcione igual en PowerShell y en Bash; solo se admite el handle `eduolihez` en docs).
- [ ] **Step 2: Dry-run sobre el `~/.claude` real**: `powershell -NoProfile -ExecutionPolicy Bypass -File install.ps1 -DryRun`. Mostrar la salida; no instalar de verdad salvo que el usuario lo pida.
- [ ] **Step 3: PARAR y pedir confirmación** al usuario para crear el repo remoto privado, enseñándole la salida del Step 1.
- [ ] **Step 4: Poner main al dia** (dos comandos; PowerShell 5.1 no tiene `&&`):
  - `git checkout main`
  - `git merge --ff-only feat/initial-setup`
- [ ] **Step 5: Con confirmación**, `gh repo create eduolihez/claude-code-setup --private --source . --remote origin --push --description "Mi setup de Claude Code: permisos, hooks, agentes y skills para SOC/Blue Team y desarrollo"`. Verificar con `gh repo view eduolihez/claude-code-setup --json visibility,url`: `PRIVATE`, y con `gh repo view eduolihez/claude-code-setup --json defaultBranchRef`: `main`.
- [ ] **Step 6: Verificar el CI remoto**: `gh run watch` sobre el último run. Esperado: todos los jobs en verde. Si falla, corregir y repetir antes de seguir.

### Task 14: Paso a público (solo con confirmación explícita)

**Files:** ninguno.

- [ ] **Step 1: Pedir confirmación explícita** al usuario para hacer público el repo, recordando que el contenido puede quedar indexado aunque se borre después.
- [ ] **Step 2: Con confirmación**, `gh repo edit eduolihez/claude-code-setup --visibility public --accept-visibility-change-consequences`. Verificar con `gh repo view eduolihez/claude-code-setup --json visibility`: `PUBLIC`.
- [ ] **Step 3: Etiquetar la versión** — `git tag v0.1.0 && git push origin v0.1.0`.

---

## Self-review

- **Cobertura del spec:** estructura (Tasks 1, 3, 10, 11, 12), seguridad de publicación (1, 3, 12, 13, 14), instalador (6, 7), templates (10), contenido nuevo (5, 8, 9), documentación (11), verificación (todas, más 12 y 13), orden de entrega (1 a 14 sigue los 4 pasos del spec).
- **Consistencia de tipos:** `Get-Frontmatter` (Task 2) se usa en la 3; `Invoke-Script` (Task 4) en las 5, 6 y 7; `Test-GitIgnored` (Task 1) solo en su test.
- **Decisión que se aparta del literal del spec:** el instalador gestiona entradas individuales de `agents/` y `hooks/` en vez de las carpetas completas, para no reemplazar agentes ajenos del usuario.
