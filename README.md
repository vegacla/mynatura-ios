# MyNatura iOS

App nativa (Swift / SwiftUI) para la venta e inventario de productos Natura.
El backend vive en el repo privado `mynatura`; este repo contiene solo el cliente iOS.

Diseño completo: [docs/ios-app-design.md](docs/ios-app-design.md).

## Flujo de desarrollo (sin Mac)

1. Editar en Windows y hacer `git push` a `main`.
2. GitHub Actions corre los tests de `Core` (Linux) y compila un **IPA sin firmar** en macOS.
3. Descargar el IPA:
   ```bash
   gh run download --repo vegacla/mynatura-ios --name MyNatura-ipa -D build
   ```
4. Abrir **Sideloadly**, arrastrar `build/MyNatura.ipa`, elegir el iPhone e ingresar el Apple ID.
5. En el iPhone: activar *Modo de desarrollador* y confiar en el perfil (*Ajustes › General › VPN y gestión de dispositivos*).

Con Apple ID gratis la app expira a los 7 días: volver a instalar con Sideloadly (los datos se conservan).

## Probar en un simulador web (sin iPhone)

CI también genera `MyNatura-simulator` (un `.zip` con el `.app` compilado para simulador; los simuladores web no aceptan `.ipa`):

```bash
gh run download --repo vegacla/mynatura-ios --name MyNatura-simulator -D build
```

Súbelo en [appetize.io/upload](https://appetize.io/upload) (o en otro servicio que acepte `.app` de simulador).
Subida automática opcional: crea el secret `APPETIZE_API_TOKEN` en GitHub (Settings › Secrets › Actions); tras la primera subida,
guarda el `publicKey` que imprime el job en la variable `APPETIZE_APP_ID` para que los siguientes builds actualicen la misma app.

Limitaciones: sin cámara (escáner EAN y foto de boleta no disponibles; sí "Elegir foto"), y el simulador corre en la nube, así que
el backend debe estar en una URL pública HTTPS (p. ej. `cloudflared tunnel --url http://localhost:3000`), no en la IP de la red local.

## Estructura

```text
project.yml          # XcodeGen (el .xcodeproj se genera en CI, no se versiona)
MyNatura/            # target app: @main, TabView raíz, inyección de dependencias
Packages/Core/       # reglas de dominio puras (dinero, normalizadores, precios, recepción, stock, sesión)
Packages/APIClient/  # cliente HTTP del backend (DTOs, cookie de sesión, errores) — tests en Linux
Packages/Persistence/# modelos SwiftData
Packages/Sync/       # SyncEngine: pull de datasets (y cola offline desde la etapa 4)
Packages/DesignSystem/ # componentes SwiftUI reutilizables
Packages/Features/   # pantallas por módulo (Session, Sales, Catalog, Receiving, Customers, Settings)
.github/workflows/   # CI: tests + IPA sin firmar
docs/                # diseño
```

## Tests locales en Windows (opcional)

```powershell
winget install Swift.Toolchain
cd Packages/Core; swift test
cd ../APIClient; swift test
```

Bundle ID: `cl.mynatura.app` (no cambiarlo: cambiarlo instala una app distinta y pierde los datos).
