# Proyecto: hackathon

## Contexto
- Evento y reto: <nombre, tema, fecha y hora de entrega>
- Equipo: <quién hace qué>
- Stack habitual: <!-- completar --> lenguaje, framework y servicios que usas normalmente en hackathones
- Despliegue de la demo: <!-- completar --> dónde se publica (plataforma o local)

## Comandos
- Instalar y arrancar: <!-- completar --> comandos del stack elegido
- Tests rápidos: <!-- completar --> comando de test, si el stack lo tiene
- Demo: <!-- completar --> un solo comando que deje la demo lista

## Convenciones
- MVP primero: una sola funcionalidad central que funcione de punta a punta antes de añadir nada
- Demo-first: lo que no se ve en la demo no se construye
- Time-boxing: cada tarea con tiempo máximo; si se pasa, se recorta alcance
- Sin sobreingeniería: sin abstracciones ni configuración que la demo no necesite
- Commits pequeños y frecuentes; la rama principal siempre arranca
- Datos de la demo sintéticos o sanitizados

## Seguridad
- Nunca escribas secretos en código ni en commits: claves de API en `.env` fuera del repo, con `.env.example` sin valores
- Valida toda entrada externa, aunque sea un prototipo
- Revisa que el repo público no contenga claves antes de entregar

## Definición de hecho
- La demo funciona de punta a punta desde un clone limpio
- README de pitch: problema, solución, captura o GIF, cómo ejecutarlo, stack, equipo
- Checklist de entrega: repo público, README, demo ensayada, vídeo o enlace si lo piden, formulario enviado antes de la hora límite
- Sin secretos en el historial de git
