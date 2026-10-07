---
name: ioc-defang
description: Neutraliza IOCs (URLs, IPs, dominios, emails) antes de ponerlos en documentos, tickets o commits
---
Aplica defang a todo IOC que vaya a escribirse en docs, tickets o commits,
para que nadie lo abra o ejecute por accidente.

## Reglas

| Tipo | Original | Defanged |
|------|----------|----------|
| Esquema | `http` / `https` | `hxxp` / `hxxps` |
| Dominio | `.` | `[.]` |
| IP | `.` | `[.]` |
| Email | `@` | `[@]` |

## Ejemplos (solo valores reservados)

- URL: `hxxps://example[.]com/login`
- IP: `192[.]0[.]2[.]1`
- Email: `analista[@]example[.]com`

## No tocar

- Código o comandos que deben ejecutarse
- Hashes (MD5, SHA-1, SHA-256)
- Rutas de archivo

## Notas

- Nunca incluyas IOCs reales de entornos del usuario en ejemplos ni en el repo.
- El refang no se hace automáticamente: lo hace el analista, de forma
  deliberada, cuando necesite el valor original.
