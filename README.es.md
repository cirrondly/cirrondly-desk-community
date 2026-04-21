# Cirrondly Desk Community

[English](README.md) | Español | [Français](README.fr.md)

Una app nativa de macOS para la barra de menús que rastrea el uso de tus
herramientas de programación con IA entre múltiples proveedores de forma local,
privada y gratuita.

<p align="center">
	<img src="demo/Desk.png" alt="Cirrondly Desk Community" width="600">
</p>

## Funcionalidades

- **10+ proveedores compatibles**: rastrea Claude Code, Cursor, Codex,
	Copilot, Kiro, Windsurf, JetBrains AI, Gemini CLI, Continue, Aider, Amp,
	Kimi, MiniMax, Perplexity, Antigravity, OpenCode Go, Synthetic, Z.AI y más.
- **Estado del servicio de un vistazo**: consulta la salud del servicio de cada
	proveedor directamente en el popover y en la configuración de Sources.
- **Cronología de uso e historial**: sigue la actividad por sesión, semanal y
	mensual con barras de progreso y un mapa de calor de uso de 90 días.
- **Tokens restantes y tiempo hasta el reinicio**: supervisa el uso, los
	tokens/solicitudes/créditos restantes y la cuenta atrás hasta la siguiente
	ventana de reinicio.
- **Notificaciones de alerta de cuota**: recibe alertas locales de macOS cuando
	un proveedor cruza los umbrales de cuota configurados.
- **Etiquetas de suscripción y tipo de cuenta**: cada proveedor aparece marcado
	como Subscription, API, Usage Based o Free.
- **Resumen unificado en la barra de menús**: mantén visible el coste de hoy,
	el burn rate y el uso activo sin abrir un dashboard.
- **Exportación de statusline**: escribe `~/.cirrondly/usage.json` para usarlo
	con statusLine de Claude Code, prompts de shell, tmux y otros flujos locales.
- **Datos 100% locales**: sin cuenta, sin telemetría, sin nube. Todos los datos
	de uso permanecen en tu Mac.

## Instalación

1. Descarga el último archivo `.dmg` desde
   [Releases](https://github.com/cirrondly/cirrondly-desk-community/releases)
2. Abre el `.dmg` y arrastra `Cirrondly Desk Community.app` a `Applications`.
3. **Solo en el primer lanzamiento**: Gatekeeper puede bloquear la app. Haz clic
	derecho sobre la app en `Applications`, elige `Open` y luego vuelve a elegir
	`Open` en el diálogo.

	Si eso no funciona, abre Terminal y ejecuta:

```bash
xattr -cr /Applications/Cirrondly\ Desk\ Community.app
```

4. Abre la app. Eso es todo.

Estamos trabajando en la firma de Apple para una futura versión. Hasta entonces,
las GitHub Releases no están firmadas ni notarizadas, por lo que Gatekeeper
puede mostrar una advertencia en el primer lanzamiento.

## Requisitos

- macOS 14 (Sonoma) o posterior
- No se requiere cuenta de Claude, Cursor ni Copilot. La app lee archivos
	locales que ya tienes si esas herramientas están instaladas.

## Capturas

<p align="center">
	<img src="demo/iconbar.png" alt="Icono de la barra de menús" width="220">
	<img src="demo/app%20copilot.png" alt="Popover de uso por proveedor" width="320">
</p>

<p align="center">
	<img src="demo/app%20kiro.png" alt="Detalles del proveedor Kiro" width="320">
	<img src="demo/settings%20sources.png" alt="Configuración de Sources" width="320">
</p>

<p align="center">
	<img src="demo/setting%20general.png" alt="Configuración general y alertas de cuota" width="420">
</p>

<p align="center">
	<img src="demo/forecast.png" alt="Popup de historial y forecast" width="320">
	<img src="demo/outage.png" alt="Estado de outage del proveedor" width="320">
</p>

## Compilar desde el código fuente

```bash
git clone https://github.com/cirrondly/cirrondly-desk-community.git
cd cirrondly-desk-community
open CirrondlyDesk.xcodeproj
```

Requiere Xcode 16 o posterior.

## Contribuir

Consulta [CONTRIBUTING.md](CONTRIBUTING.md).

## Agradecimientos

Este proyecto se inspira en excelente trabajo open source:

- **[openusage](https://github.com/robinebers/openusage)** por su arquitectura
	de plugins para el seguimiento de uso multi-proveedor.
- **[Claude-Code-Usage-Monitor](https://github.com/Maciek-roboblog/Claude-Code-Usage-Monitor)** por su lógica de burn rate y predicción.
- **[ClaudeMeter](https://github.com/eddmann/ClaudeMeter)** por su indicador de
	barra de menús con colores y su estructura de configuración.
- **[Claude-Usage-Tracker](https://github.com/hamed-elfayome/Claude-Usage-Tracker)** por su enfoque multi-perfil y patrones nativos de macOS.
- **[ccusage](https://github.com/ryoppippi/ccusage)** como referencia para el
	parseo de JSONL de Claude Code.

Estos proyectos son independientes y están bajo sus propias licencias.
Reimplementamos funcionalidad similar en Swift desde cero; no se copió código.

## Descargo de responsabilidad

Esta es una herramienta no oficial y no está afiliada, respaldada ni soportada
por Anthropic, OpenAI, GitHub, Amazon, Google, JetBrains, Cursor ni ningún otro
proveedor de herramientas de programación con IA.

Los datos se leen de archivos locales en tu propio Mac. No se accede a cuentas.
No se hacen llamadas a APIs de proveedores de IA salvo que las configures
explícitamente en la sección Sources.

## Licencia

Licencia Apache 2.0. Consulta [LICENSE](LICENSE).

"Cirrondly" y el logotipo de nube de Cirrondly son marcas registradas de
Cirrondly SAS; consulta [TRADEMARKS.md](TRADEMARKS.md).