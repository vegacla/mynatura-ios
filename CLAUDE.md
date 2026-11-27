# CLAUDE.md — MyNatura iOS


App nativa iOS (Swift 6 / SwiftUI) de venta e inventario para una persona consultora Natura.
**Local primero, sin backend propio** (desde M7, 2026-11-27): el iPhone guarda todos los datos en SwiftData y habla directo con Natura (minegocio y GSP).
El backend anterior (Fastify + PostgreSQL, repo privado `mynatura`, local `../../Node/mynatura`) queda solo como **referencia** (p. ej. el OCR de boleta con Tesseract).

## Documentos rectores
- **`docs/local-first-migration.md`** — arquitectura vigente (§3), reglas de costo (§4), respaldo (§6), etapas M1–M8 y su implementación (§8.x).
- **`docs/natura-integration.md`** — referencia técnica de Natura (login, pedidos, Excel, GSP, cuenta, ofertas).
- **`docs/ios-app-design.md`** — pantallas, dominio, modelos y design system. Sus secciones de backend/sync están marcadas como obsoletas. Contiene:
- §1 qué hace la app y principios no negociables
- §3–4 navegación (5 tabs) y pantallas con paridad funcional
- §5 reglas de dominio · §6 modelos SwiftData · §10 design system
- **§11 plan por etapas + tabla de estado** (actualizarla al cerrar cada etapa)
- §13 flujo Windows + GitHub Actions + Sideloadly

## Entorno de desarrollo (importante)
- **No hay Mac ni Xcode ni Swift local.** Se edita en Windows; la compilación ocurre en GitHub Actions.
- Verificar cambios = commit + `git push` + revisar el run:
  `gh run list --repo vegacla/mynatura-ios --limit 3` · `gh run view <id> --log-failed`
- IPA: `gh run download <id> --repo vegacla/mynatura-ios --name MyNatura-ipa -D build` → instalar con Sideloadly.
- El remoto usa **SSH** (el token de `gh` no tiene scope `workflow`; un push HTTPS que toque `.github/workflows` falla).
- El workflow ignora cambios solo en `docs/**` y `*.md`.
- **Regla temporal (2026-11-27):** CI mínimo; el workflow solo compila la IPA (tests y build de simulador desactivados).

## Convenciones
- Código, identificadores y commits en **inglés**; textos de UI en **español (es-CL)**.
- Proyecto definido en `project.yml` (XcodeGen). **No versionar `.xcodeproj`** ni `MyNatura/Resources/Info.plist` (generados). Permisos y claves de Info.plist van en `project.yml`.
- Cada paquete nuevo en `Packages/` debe declararse en `project.yml` (`packages:` y `dependencies:`).
- `Packages/Core` = dominio puro, **solo Foundation** (tests en Linux). Sin SwiftUI/SwiftData/UIKit ahí.
- `Packages/Store` = `LocalStore`: acciones que escriben directo en SwiftData e importación desde Natura. `Packages/Natura` = cliente HTTP de Natura y Keychain.
- Tests con Swift Testing (`import Testing`, `@Test`, `#expect`).
- Las reglas de negocio viven en `Core`, con tests.
- Dinero: `Money(pesos:)` — pesos CLP enteros.
- Bundle ID **fijo**: `cl.mynatura.app` (cambiarlo = otra app en el iPhone y pérdida de datos).
- Apple ID gratis: sin extensiones/widgets, sin push, sin iCloud/App Groups.
- La contraseña de Natura solo se guarda en el Keychain del iPhone, con Touch ID (`NaturaCredentialStore`), si la consultora lo pide; nunca en SwiftData, en el respaldo ni en logs.
- Repo **público**: no incluir secretos, rutas locales con nombre de usuario ni datos personales.
