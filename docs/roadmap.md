# Roadmap

## Pendiente conocido

- `templates/web.md` y `templates/hackathon.md` conservan marcadores `<!-- completar -->` a la espera del stack del propietario.
- `block-secrets-write.ps1` solo cubre las herramientas Write y Edit. MultiEdit y NotebookEdit no pasan por él.
- Los tests del instalador en modo enlace solo corren en CI y en máquinas con privilegio de symlink.

## Limitaciones conocidas del instalador

- Un destino instalado por una versión anterior y no publicada del instalador (carpetas `setup-*` sin manifiesto) que ya se desinstaló puede volver a sembrarse desde un backup viejo al reinstalar.
- Un manifiesto editado a mano (JSON válido pero parcial) hace que `-Uninstall` omita entradas y aun así marque los backups como restaurados.
- Si ya existe `restored-setup-<mismo sello de tiempo>`, el renombrado posterior a `-Uninstall` falla y `-Uninstall` informa de un error hasta que se renombre a mano.
- Faltan tests para el manifiesto corrupto, la siembra al instalar y la ausencia de renombrado tras un fallo a mitad del bucle de restauración.
- `-Uninstall` no puede recrear un enlace del usuario que esté roto: lo informa como error.

## Fase 2: plugin SOC

Empaquetar agentes y skills de SOC en un plugin dentro de [plugin/](../plugin/README.md), para instalarlo sin tocar el resto de la configuración.

## Más adelante

- `install.sh` para Linux y macOS.
- Más hooks.
