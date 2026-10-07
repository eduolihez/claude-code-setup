# Roadmap

## Pendiente conocido

- `templates/web.md` y `templates/hackathon.md` conservan marcadores `<!-- completar -->` a la espera del stack del propietario.
- `block-secrets-write.ps1` solo cubre las herramientas Write y Edit. MultiEdit y NotebookEdit no pasan por él.
- Los tests del instalador en modo enlace solo corren en CI y en máquinas con privilegio de symlink.

## Fase 2: plugin SOC

Empaquetar agentes y skills de SOC en un plugin dentro de [plugin/](../plugin/README.md), para instalarlo sin tocar el resto de la configuración.

## Más adelante

- `install.sh` para Linux y macOS.
- Más hooks.
