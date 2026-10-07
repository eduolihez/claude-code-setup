# Dependencias

Este repo no incluye código de terceros. Lo siguiente se instala aparte.

## Plugin superpowers

- Plugin: `superpowers@superpowers-marketplace`.
- Marketplace: `obra/superpowers-marketplace` (GitHub). Repositorio: <https://github.com/obra/superpowers-marketplace>.
- Ya está declarado en `claude/settings.json` (`extraKnownMarketplaces` y `enabledPlugins`), así que Claude Code lo ofrece al instalar la configuración.

## Skills de terceros (gstack)

La suite de unas 60 skills que uso en `~/.claude/skills` viene de <https://github.com/garrytan/gstack>, que es su propio repositorio. La instalé por separado y este repo no la incluye ni la gestiona: el instalador solo enlaza las cinco skills propias. Para instalarla, sigue las instrucciones de ese repositorio.

## Herramientas para los tests y la CI

- Pester 5.5 o superior, para `tests/Invoke-Tests.ps1`.
- Node.js con `npx`, para `markdownlint-cli2`.
- PSScriptAnalyzer y gitleaks, que ejecuta la integración continua.
