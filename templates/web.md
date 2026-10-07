# Proyecto: web

## Contexto
- Sitio o app: <qué es y para quién>
- Framework: <!-- completar --> framework y versión (o HTML/CSS/JS plano)
- Hosting y despliegue: <!-- completar --> plataforma y método de deploy

## Comandos
- Instalar: <!-- completar --> gestor de paquetes e instalación
- Desarrollo: <!-- completar --> servidor local
- Build: <!-- completar --> comando de build
- Tests y lint: <!-- completar --> comandos del stack
- Deploy: <!-- completar --> comando o pipeline

## Convenciones
- Accesibilidad: HTML semántico, un solo `h1`, `alt` en imágenes, contraste suficiente (WCAG AA), todo operable con teclado y foco visible
- Rendimiento: imágenes optimizadas y con dimensiones, carga diferida de lo no crítico, JS mínimo, comprobar Lighthouse antes de publicar
- Diseño responsive, mobile-first
- Textos de cara al público: aplica la skill /humanizer antes de entregarlos
- Componentes pequeños, sin dependencias que no se usen

## Seguridad
- Nunca escribas secretos en código ni en commits; ningún secreto en el cliente (todo lo que va al navegador es público)
- Valida toda entrada externa (formularios, parámetros de URL, respuestas de API), en cliente y sobre todo en servidor
- Escapa la salida para evitar XSS; no uses `innerHTML` con datos de usuario
- Cabeceras de seguridad (CSP, HSTS) y HTTPS en producción
- Dependencias auditadas antes de publicar

## Definición de hecho
- Build sin errores ni avisos nuevos
- Accesibilidad revisada: navegación por teclado y contraste
- Rendimiento comprobado (Lighthouse)
- Entradas validadas y sin secretos en el diff ni en el bundle
- Probado en móvil y escritorio
