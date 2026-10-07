---
name: commit
description: Revisa el diff, separa en commits pequeños y redacta mensajes descriptivos
disable-model-invocation: true
---
1. Ejecuta `git status` y `git diff` para ver todos los cambios.
2. Agrupa los cambios por propósito lógico (un commit = un cambio coherente).
3. Para cada grupo:
   - `git add` solo los archivos de ese grupo
   - Mensaje en imperativo, línea de asunto < 72 caracteres, cuerpo explicando el porqué si no es obvio
   - No menciones herramientas de IA en el mensaje
4. Antes de cada commit, muestra el diff que vas a incluir y pide confirmación si hay algo ambiguo.
5. Nunca uses `git push --force` ni `git commit --amend` salvo que se pida explícitamente.
6. Al terminar, muestra `git log --oneline -n <núm. commits creados>`.
