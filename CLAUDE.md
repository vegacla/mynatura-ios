# CLAUDE.md — MyNatura iOS

App nativa iOS (Swift 6 / SwiftUI) que replica la PWA de MyNatura (venta e inventario para una persona consultora Natura).
El **backend** (Fastify + PostgreSQL) vive en el repo privado `mynatura` (local: `../../Node/mynatura`); esta app lo consume por HTTP.

## Documento rector
**`docs/ios-app-design.md`** — leerlo antes de cualquier tarea. Contiene:
- §1 qué hace la app y principios no negociables
- §3–4 navegación (5 tabs) y pantallas con paridad funcional
- §5 reglas de dominio · §6 modelos SwiftData · §7 motor de sync offline · §8 endpoints reales del backend
- §9 cambios pendientes en el backend · §10 design system
- **§11 plan por etapas + tabla de estado** (actualizarla al cerrar cada etapa)
- §13 flujo Windows + GitHub Actions + Sideloadly

## Entorno de desarrollo (importante)
- **No hay Mac ni Xcode ni Swift local.** Se edita en Windows; la compilación ocurre en GitHub Actions.
- Verificar cambios = commit + `git push` + revisar el run:
  `gh run list --repo vegacla/mynatura-ios --limit 3` · `gh run view <id> --log-failed`
- IPA: `gh run download <id> --repo vegacla/mynatura-ios --name MyNatura-ipa -D build` → instalar con Sideloadly.
- El remoto usa **SSH** (el token de `gh` no tiene scope `workflow`; un push HTTPS que toque `.github/workflows` falla).
- El workflow ignora cambios solo en `docs/**` y `*.md`.

## Convenciones
- Código, identificadores y commits en **inglés**; textos de UI en **español (es-CL)**.
- Proyecto definido en `project.yml` (XcodeGen). **No versionar `.xcodeproj`** ni `MyNatura/Resources/Info.plist` (generados). Permisos y claves de Info.plist van en `project.yml`.
- Cada paquete nuevo en `Packages/` debe declararse en `project.yml` (`packages:` y `dependencies:`).
- `Packages/Core` = dominio puro, **solo Foundation** (sus tests corren en Linux en CI). Sin SwiftUI/SwiftData/UIKit ahí.
- Tests con Swift Testing (`import Testing`, `@Test`, `#expect`).
- Las reglas de `Core` son espejo del backend; si cambian allá, cambiar aquí con tests.
- Dinero: `Money(pesos:)` — los campos `*Cents` del API son pesos CLP enteros.
- Bundle ID **fijo**: `cl.mynatura.app` (cambiarlo = otra app en el iPhone y pérdida de datos).
- Apple ID gratis: sin extensiones/widgets, sin push, sin iCloud/App Groups.
- Credenciales de Natura nunca se persisten en el dispositivo.
- Repo **público**: no incluir secretos, rutas locales con nombre de usuario ni datos personales.
