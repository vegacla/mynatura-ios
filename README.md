# MyNatura iOS

App nativa (Swift / SwiftUI) para la venta e inventario de una consultora Natura.
**Local primero, sin backend propio:** los datos viven en el iPhone (SwiftData) y la app habla directo con Natura.

Diseño: [docs/local-first-migration.md](docs/local-first-migration.md) (arquitectura y etapas),
[docs/natura-integration.md](docs/natura-integration.md) (Natura) y [docs/ios-app-design.md](docs/ios-app-design.md) (pantallas y dominio).

## Flujo de desarrollo (sin Mac)

1. Editar en Windows y hacer `git push` a `main`.
2. GitHub Actions compila un **IPA sin firmar** en macOS. Por ahora es lo único que corre (regla temporal: CI mínimo).
3. Descargar el IPA:
   ```bash
   gh run download --repo vegacla/mynatura-ios --name MyNatura-ipa -D build
   ```
4. Abrir **Sideloadly**, arrastrar `build/MyNatura.ipa`, elegir el iPhone e ingresar el Apple ID.
5. En el iPhone: activar *Modo de desarrollador* y confiar en el perfil (*Ajustes › General › VPN y gestión de dispositivos*).

Con Apple ID gratis la app expira a los 7 días: volver a instalar con Sideloadly (los datos se conservan).
Exporta un respaldo de vez en cuando (Ajustes › Respaldo).

## Estructura

```text
project.yml            # XcodeGen (el .xcodeproj se genera en CI, no se versiona)
MyNatura/              # target app: @main, TabView raíz, inyección de dependencias
Packages/Core/         # reglas de dominio puras (dinero, costeo y lotes, precios, recepción, Natura, voz)
Packages/Persistence/  # modelos SwiftData y respaldo JSON
Packages/Natura/       # cliente HTTP de Natura (minegocio + GSP), lector de XLSX, Keychain
Packages/Store/        # LocalStore: acciones locales e importación desde Natura
Packages/DesignSystem/ # componentes SwiftUI reutilizables
Packages/Features/     # pantallas (Sales, Catalog, Receiving, Customers, Settings, Natura)
.github/workflows/     # CI: IPA sin firmar
docs/                  # diseño
```

## Tests locales en Windows (opcional)

```powershell
winget install Swift.Toolchain
cd Packages/Core; swift test
```

Bundle ID: `cl.mynatura.app` (no cambiarlo: cambiarlo instala una app distinta y pierde los datos).
