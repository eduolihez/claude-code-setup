# Seguridad

## Qué no se publica

Este repo usa un `.gitignore` de lista blanca: se ignora todo salvo lo que se re-incluye de forma explícita. Nunca se versiona:

- Credenciales y tokens.
- Historial de conversaciones y sesiones.
- Proyectos de trabajo.
- Backups del instalador.

Cualquier archivo nuevo queda fuera hasta que se añade a la lista blanca a propósito. Los tests comprueban que esas rutas siguen ignoradas.

## Qué protegen los hooks

- `block-dangerous.ps1` deniega `rm -rf` y `git push` forzado antes de que Claude Code los ejecute.
- `block-secrets-write.ps1` deniega escribir contenido que parezca una clave de AWS, un token de GitHub, Anthropic o Slack, o una clave privada. El mensaje nombra el tipo de secreto sin reproducirlo.

Límites conocidos: el hook de secretos solo se aplica a las herramientas Write y Edit, no a MultiEdit ni NotebookEdit, y detecta unos pocos formatos. Es una red de seguridad, no un escáner completo. Está en el [roadmap](docs/roadmap.md).

## Cómo reportar un problema

- Una vulnerabilidad o un secreto expuesto: usa el reporte privado de vulnerabilidades de GitHub (pestaña Security del repo). Si no está disponible, abre un issue sin detalles sensibles y pide un canal privado.
- Cualquier otro fallo: abre un issue en el repo.

El mantenedor es [eduolihez](https://github.com/eduolihez).
