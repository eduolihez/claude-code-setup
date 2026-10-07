# Proyecto: ingeniería de detección (SOC)

## Contexto
- Reglas de detección en Sigma (y YARA para ficheros/memoria): <fuentes de log y plataforma SIEM objetivo>
- Cada regla se mapea a técnicas de `MITRE ATT&CK`
- Repositorio: reglas en `rules/`, casos de prueba en `tests/`

## Comandos
- Validar reglas: `sigma check rules/`
- Convertir a la plataforma objetivo: `sigma convert -t <backend> -p <pipeline> rules/`
- Compilar YARA: `yarac rules/yara/<regla>.yar /dev/null`
- Tests de casos: <comando del proyecto para ejecutar los casos positivos y negativos>

## Convenciones
- Metadatos obligatorios en cada regla Sigma: `id` (UUID), `title`, `status`, `description`, `author`, `date`, `logsource`, `level`, `tags`, `falsepositives`
- `status`: `experimental` al crear, `test` tras validar, `stable` solo con tuning documentado
- `tags`: técnicas ATT&CK con formato `attack.tXXXX` (p. ej. `attack.t1059.001` PowerShell, `attack.t1003.001` LSASS); usa solo IDs que hayas verificado
- Cada regla tiene al menos un caso positivo (debe alertar) y uno negativo (no debe alertar)
- Tuning de falsos positivos: documenta exclusiones y su motivo en `falsepositives`; nada de exclusiones genéricas
- Ejemplos con valores reservados: `example.com`, `192.0.2.0/24`, `198.51.100.0/24`, `203.0.113.0/24`

## Seguridad
- Nunca escribas secretos en código ni en commits
- Nunca incluyas logs ni IOCs reales: los datos de prueba son sintéticos o sanitizados (IPs, dominios, usuarios, hostnames)
- Si necesitas citar un IOC, hazlo con defang (`hxxps://example[.]com`)
- Valida toda entrada externa antes de convertirla en regla

## Definición de hecho
- `sigma check rules/` sin errores ni avisos nuevos
- Metadatos completos y técnica ATT&CK verificada
- Casos de prueba positivo y negativo incluidos y en verde
- Falsos positivos esperados y su tuning documentados
- Sin datos reales en el diff
