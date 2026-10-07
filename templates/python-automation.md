# Proyecto: automatización con Python

## Contexto
- Scripts de automatización para tareas de SOC / Blue Team: <qué automatiza este proyecto>
- Entradas: <fuentes de datos, APIs, ficheros>. Salidas: <informes, tickets, alertas>
- Python <versión>; gestor de entorno: `uv` (alternativa: `venv` + `pip`)

## Comandos
- Instalar: `uv sync` (o `python -m venv .venv` y `pip install -r requirements.txt`)
- Tests: `uv run pytest`
- Lint: `uv run ruff check .`
- Formato: `uv run ruff format .`
- Ejecutar con simulación: `uv run python -m <paquete> --dry-run`

## Convenciones
- Type hints en todas las funciones públicas
- `logging` en vez de `print`; nivel configurable
- Scripts idempotentes: ejecutarlos dos veces no debe cambiar el resultado
- Todo lo destructivo (borrar, mover, bloquear, enviar) lleva flag `--dry-run` y por defecto no actúa
- Dependencias fijadas (`uv.lock` o versiones exactas en `requirements.txt`)
- Funciones pequeñas y testeables; la E/S va separada de la lógica

## Seguridad
- Nunca escribas secretos en código ni en commits: claves y tokens solo por variables de entorno
- Valida toda entrada externa (ficheros, respuestas de API, argumentos)
- Datos de ejemplo y fixtures sintéticos o sanitizados; nunca logs ni IOCs reales
- No loguees credenciales ni datos personales

## Definición de hecho
- `uv run ruff check .` y `uv run ruff format --check .` sin errores
- `uv run pytest` en verde, con tests del caso normal y de error
- `--dry-run` probado y documentado en el README
- Sin secretos en el diff; dependencias fijadas
