# MyNatura para iOS — Diseño de la app nativa (Swift / SwiftUI)

> **⚠️ Arquitectura vigente (desde M7, 2026-11-27): app local primero, sin backend propio.** El iPhone guarda todos los datos (SwiftData) y habla directo con Natura. Referencias: `docs/local-first-migration.md` (plan M1–M8 y su §3 de arquitectura) y `docs/natura-integration.md`. Las secciones que hablan del backend (§2 decisión, §4.1 login, §7 sync, §8 `APIClient`, §9 backend, §13.5) quedan como **historia**; cada una lo indica.


> Documento derivado del análisis completo del repositorio `mynatura` (privado: PWA Vue 3 + backend Fastify/PostgreSQL).
> Las rutas `docs/…`, `backend/…` y `frontend/…` citadas aquí se refieren a ese repositorio.
> Objetivo: construir la **misma aplicación** como app nativa de iPhone, sin perder ninguna regla de negocio
> ni el modelo offline‑first ya definido en `docs/`.

---

## 1. Qué es la app (extracto de ideas)

App de trabajo diario para **una persona consultora Natura** (una cuenta = un negocio, sin multiusuario) que:

1. **Importa pedidos entregados desde Natura** (login con código cliente + contraseña, bajo demanda).
2. Mantiene un **catálogo restringido**: solo productos comprados en pedidos Natura o creados manualmente.
3. Lleva **inventario auditable por eventos** (recepciones, ventas, conciliaciones) y **por lotes** (FIFO/LIFO) para calcular costo de venta.
4. **Vende rápido desde el teléfono**, incluso sin conexión, con reglas de precio justificadas (descuento / regalo).
5. **Recibe pedidos** físicamente: línea por línea, escaneando EAN/SKU, o asistido por **OCR de la boleta**.
6. Registra **clientes** y **pedidos de clientes por ciclo** (intención de compra, no mueven stock).
7. Muestra **historial**: kardex por producto y ventas.

### Principios que el port iOS debe preservar (no negociables)

| Principio | Consecuencia en iOS |
|---|---|
| Natura es la verdad externa (pedidos, SKU, precios sugeridos) | La app no inventa catálogo: se arma con los pedidos y el catálogo del ciclo, importados directo de Natura. |
| El conteo físico es la verdad operativa | La conciliación es un evento propio; nunca se pisa el historial. |
| Catálogo restringido por cuenta de vendedor | Se muestra `sellerProduct`, nunca el maestro completo. |
| Credenciales protegidas | La contraseña de Natura se guarda, si la consultora quiere, solo en el Keychain de este iPhone, protegida con Touch ID (M5). Nunca va en el respaldo. |
| Local primero | SwiftData es la fuente de verdad; lo de Natura se trae bajo demanda y se guarda con fecha de lectura. Respaldo JSON (M5). |
| UI en español, código en inglés | `Localizable.xcstrings` con `es-CL` como idioma base. |

---

## 2. Decisión de arquitectura

**Vigente (desde M7, 2026-11-27): app local primero, sin backend propio.** Detalle y motivos en `local-first-migration.md` §1–§3.

- **SwiftData es la fuente de verdad**: productos, lotes, ventas y obsequios, clientes, pedidos de clientes, pedidos Natura, borradores y caché de Natura.
- **Natura directo** (paquete `Natura`): login por HTTP (minegocio + GSP), pedidos entregados con su Excel, catálogo y ofertas del ciclo, cuenta y crédito. Ver `natura-integration.md`.
- **Reglas en `Core`** (costo por lotes, ganancia, precios, recepción, voz), con tests.
- **Respaldo JSON** y contraseña de Natura en el Keychain con Touch ID (M5).
- El backend anterior (Fastify + PostgreSQL) y la PWA quedan como referencia en el repo `mynatura`, sin cambios.

Lo que aporta ser nativo: escáner VisionKit, Vision para fotos de producto, voz con Speech, hápticos y Atajos de Siri.

---

## 3. Navegación

La PWA tiene una barra inferior de 6 ítems + una pantalla Inicio que solo es un lanzador. En iOS el **TabView ya es el lanzador**, así que Inicio desaparece y se agrupa a 5 pestañas (límite cómodo de iPhone):

| Tab | SF Symbol | Contiene (rutas PWA equivalentes) |
|---|---|---|
| **Vender** | `cart` | `/pos`, `/pos/cart` (sheet), historial de ventas (toolbar) |
| **Productos** | `shippingbox` | `/products`, detalle producto con EAN + conciliación + **kardex** (`/history` movimientos) |
| **Recepción** | `tray.and.arrow.down` | `/purchases`, `/purchases/:id`, `/lines`, `/scan` |
| **Clientes** | `person.2` | Segmento *Pedidos* (`/customer-orders`, editor) y *Clientes* (`/customers`, detalle) |
| **Ajustes** | `gearshape` | `/settings`: sesión, estado offline, FIFO/LIFO, importar Natura, historial de importaciones |

Cada tab tiene su propio `NavigationStack` con rutas tipadas (`enum Route: Hashable`).
El **indicador de conectividad/sync** (En línea · Pendiente sync · Sin conexión · Sync falló · Sincronizando) va como pastilla en la toolbar de todas las pantallas y como `.badge` en el tab Ajustes cuando hay fallidos.

---

## 4. Pantallas (paridad funcional)

### 4.1 Login

No hay login a la app (M7). Abre directo con un perfil local (`AppProfile`). Las credenciales de Natura se piden solo al traer datos de Natura (Ajustes › Natura) y se pueden guardar con Touch ID.

### 4.2 Vender (POS)
- Lista de productos **vendibles con stock operativo > 0**, búsqueda por nombre, SKU o EAN (`.searchable`).
- Botón de escáner en la barra de búsqueda: un EAN leído agrega directo al carro (equivale a *Enter → addFirstExactMatch*).
- Cada fila: nombre, SKU, primer EAN (+N), precio sugerido, "N disp.", botón **Agregar** / "Sin stock". Háptico al agregar.
- Botón Carro con badge de unidades.

### 4.3 Carro (sheet)
- Líneas con stepper (máx = stock operativo), **precio final** editable (`MoneyField`), "Sugerido: $X".
- Si precio final < sugerido o = 0 → aparece **Motivo** (Picker filtrado por categoría) + observación opcional.
- Nota general, total, botón **Registrar venta**.
- Selector opcional de cliente (el DTO `CreateSaleInputDto` ya acepta `customerId`).
- El carro persiste en SwiftData (`CartDraft`), igual que el *persist cart* de la PWA.
- Al registrar: se crea localmente, se descuenta stock local, se encola `sale.create` y se intenta push inmediato.

### 4.4 Historial de ventas
- Lista de ventas (cliente o "Sin cliente", fecha, nota, total) con detalle desplegable de líneas (cantidad × precio, SKU, motivo).
- Ventas no sincronizadas marcadas con ícono `icloud.slash` / fallidas en rojo con acción "Revisar".

### 4.5 Productos
- Lista con búsqueda por nombre/SKU; fila con nombre, SKU, badge Vendible/No vendible, compra, sugerido, stock, origen (Manual / Catálogo / Importado).
- **Detalle de producto** (reemplaza los acordeones de la PWA):
  - **EAN asociados** + "Agregar EAN" (teclado o escáner). Error claro si el EAN ya pertenece a otro producto.
  - **Conciliación física**: teórico vs operativo, conteo físico, observación, "Delta esperado ±N", Guardar.
  - **Kardex**: tabla Fecha · Tipo · Nota · Entrada · Salida · Saldo (running balance).
- Toolbar: "+" creación rápida por SKU (con autocompletado desde `GET /api/catalog/master-products/lookup`).

### 4.6 Recepción
- **Lista de pedidos Natura**: número, fecha de entrega, ciclo, badges OCR (Pendiente/Leído/Falló) y revisión (Borrador/Cerrado), progreso "Recepción X / Y" con `ProgressView`. Búsqueda por número.
- **Detalle de pedido**: 3 MiniStats (Recibido, Pendiente, Estado: pendiente/parcial/completo), barra de progreso, dos entradas grandes:
  - **Recibir por línea** — por cada línea: stock, precio compra, precio venta; stepper "Cantidad a recibir" (0…cantidad pedida), precio venta editable, faltante, "Guardar línea". Arriba: tarjeta **Comprobante** (foto → OCR → propuestas de precio/cantidad que el usuario acepta) y tarjeta **Asistencia de conciliación** ("Aplicar faltantes al stock": crea una conciliación por línea con faltante, nota *"Faltante confirmado en pedido N: k unidad(es)"*).
  - **Recibir por código** — campo + **escáner continuo**: cada lectura (EAN o SKU, mín. 5 caracteres) suma 1 a la línea que coincide; háptico de éxito/error; lista de líneas debajo.
  - **Cerrar pedido / Reabrir pedido**. Cerrado ⇒ todo deshabilitado (recepción, OCR, precios).
- OCR y "Cargar pedidos" son **solo online**: botones deshabilitados con explicación cuando no hay red.

### 4.7 Clientes
- **Pedidos de clientes**: lista (cliente, "Ciclo N · fecha", estado, nº líneas, nota) + "Nuevo pedido".
- **Editor de pedido** (optimizado para hablar con el cliente):
  1. Nombre del cliente con autocompletado local (nombre normalizado); "Cliente seleccionado" vs "Cliente nuevo" — no bloquea.
  2. Ciclo (obligatorio, numérico, formato `AAAACC`, p. ej. 202606) + Estado (Borrador/Confirmado/Cumplido/Cancelado) + nota.
  3. Agregar producto: búsqueda por nombre/SKU; si no existe, **creación rápida SKU + nombre** (reutiliza si el SKU ya existe).
  4. Líneas: cantidad, precio sugerido, precio final; swipe para quitar.
- **Clientes**: búsqueda, ficha (nombre, RUT, teléfono, notas) y pedidos del cliente.
- Todo funciona 100 % offline (IDs locales UUID, creados antes de sincronizar).

### 4.8 Ajustes

- **Consultora:** código Natura (se recuerda al importar).
- **Método de costeo:** FIFO, LIFO o Mayor precio (`local-first-migration.md` §4.4).
- **Natura:** código y contraseña (opcional: guardarla con Touch ID), "Traer mis pedidos" / "Actualizar desde Natura", última importación, ciclo vigente, **Cuenta Natura** (crédito y pagos), **Ofertas del ciclo** y "Agregar inventario actual" (una vez).
- **Respaldo:** exportar e importar JSON, con recordatorio semanal.
- **Voz:** servidores de Apple, respuestas habladas, recepción sin manos, frases no entendidas (locales) y ejemplos.
- **Historial y reportes:** ventas y Ganancias.
- **Borrar datos del iPhone**, versión y **Diagnóstico** (red, último error, log).

---

## 5. Reglas de dominio (paquete `Core`)

Todo esto se porta como funciones puras testeadas, idénticas al backend, para que el modo offline valide igual que el servidor.

### 5.1 Dinero
- Los campos `*Cents` del API son en realidad **pesos chilenos enteros** (Natura entrega `$12.990` y el backend quita puntos → `12990`). En Swift: `struct Money { let pesos: Int }` con formatter `es_CL`, 0 decimales.

### 5.2 Normalizadores
```swift
enum Normalize {
    static func naturaSku(_ s: String) -> String   // quita "#" inicial y espacios
    static func ean(_ s: String) -> String          // solo dígitos
    static func rut(_ s: String) -> String          // [0-9K] en mayúscula
    static func customerName(_ s: String) -> String // minúsculas, sin tildes, espacios colapsados
    static func scanCode(_ s: String) -> String     // todo dígitos → ean, si no → sku
}
```

### 5.3 Reglas de precio de venta
```swift
enum PricingRuleError: Error { case zeroPriceRequiresGift, belowSuggestedRequiresDiscount, invalidQuantity, notSellable, insufficientStock(available: Int) }

func validate(line: CartLine, suggested: Money?, reason: PricingReason?) throws(PricingRuleError) {
    guard line.quantity > 0 else { throw .invalidQuantity }
    if line.finalPrice.pesos == 0 {
        guard reason?.category == .gift else { throw .zeroPriceRequiresGift }
    } else if let suggested, line.finalPrice < suggested {
        guard reason?.category == .discount else { throw .belowSuggestedRequiresDiscount }
    }
}
```
- Precio por defecto = sugerido. Productos `isSellable == false` no aparecen en Vender.
- Motivos semilla: `discount_manual` (descuento), `gift_manual` (regalo); se descargan de `GET /api/sales/pricing-reasons`.

### 5.4 Stock
- **Teórico** = Σ recepciones − Σ ventas (± eventos futuros).
- **Operativo** = teórico corregido por la última conciliación.
- **Conciliación**: guarda `countedQuantity`, `theoreticalQuantityBefore`, `deltaApplied = counted − theoretical`, nota.
- **Stock local offline** = último `stockSummary` descargado − ventas locales pendientes + ajustes de conciliaciones locales pendientes. Se marca como "local · pendiente".

### 5.5 Recepción
- `receivingStatus`: `pending` (0 recibido), `partial`, `complete` (recibido ≥ pedido).
- `receivingReviewStatus`: `draft` / `closed` (`receivingClosedAt`). Cerrado ⇒ rechaza edición.
- Escaneo: incrementa `receivedConfirmationQuantity` de la línea cuyo SKU o EAN coincide.
- Faltante = cantidad pedida − confirmada; conteo sugerido = max(0, stock operativo − faltante).

### 5.6 Importación (referencia, vive en backend)
- Solo pedidos con estado **"Entregado"**; idempotente por `(seller, externalOrderId)` y receipts únicos por línea.
- Ciclo: si `cycle ≥ 10000` → `AAAACC`; si no, año desde fecha de entrega/pedido.
- Vendibilidad inferida: tipo "regalo" con nombre *revista / catálogo / carta* ⇒ no vendible; el resto vendible.

### 5.7 Lotes FIFO/LIFO (backend)
- Cada recepción crea un `inventory_lot` con costo y precio sugerido; la venta consume lotes en el orden de la preferencia y guarda `costUnitPrice`/`costTotal` por línea (margen real). La app solo muestra el resultado; **no** replica la asignación de lotes offline.

---

## 6. Persistencia local (SwiftData)

Modelos vigentes (paquete `Persistence`, todos filtrados por `sellerId`; archivo con `completeUntilFirstUserAuthentication`):

| Modelo | Qué guarda |
|---|---|
| `SessionSummary` | Perfil local: `sellerId` y código de consultora |
| `SellerSettings` | Método de costeo, ciclo vigente con fechas, última importación, inventario inicial, último respaldo |
| `CatalogProduct` · `StockItem` | Catálogo (pedidos + ciclo de GSP, con precios, puntos y oferta del ciclo) y stock = suma de lotes |
| `InventoryLotRecord` · `InventoryEventRecord` | Lotes con costo y origen; kardex |
| `LocalSale` | Ventas, obsequios y ventas previas, con el costo de cada línea |
| `NaturaOrder` · `NaturaOrderLine` | Pedidos Natura importados y su recepción |
| `Customer` · `CustomerOrder` | Clientes y pedidos por ciclo |
| `NaturaOrderDraft` | Borrador del pedido Natura del ciclo (M8) |
| `NaturaAccountSnapshot` | Caché de cuenta, crédito y pagos de Natura |
| `CartDraft` · `CartDraftLine` · `PricingReasonRecord` | Carro en curso y motivos de precio |

Sin uso desde M7 (se quitan con una migración versionada, `pending.md` §0): `PendingMutation`, `DatasetSyncState`, los campos `syncState` y los de OCR.

---

## 7. Motor de sincronización (paquete `Sync`)

> **Obsoleto desde M7 (2026-11-27):** no hay sincronización. `LocalStore` (paquete `Store`) escribe directo en SwiftData e importa desde Natura. La versión anterior de esta sección está en el historial de git.

---

## 8. Capa de red (paquete `APIClient`)

> **Obsoleto desde M7 (2026-11-27):** el paquete `APIClient` se eliminó. La red es solo con Natura: `natura-integration.md` y el paquete `Natura` (`NaturaClient`).

---

## 9. Ajustes necesarios en el backend

> **Obsoleto desde M7 (2026-11-27):** no hay backend propio.

---

## 10. Design system (iOS)

Se toma el "north star" de `docs/plan/refactor-plan.md` (*"la app debe sentirse como un iPhone"*), que en nativo sale casi gratis:

- Un color de acento (azul sistema) para acciones primarias; semánticos solo para estado (verde ok, rojo error, ámbar advertencia).
- Listas `.insetGrouped`, objetivos táctiles ≥ 44 pt, Dynamic Type, modo oscuro, VoiceOver.
- Componentes únicos (resuelven las duplicaciones detectadas en la PWA): `StatusBadge` (una sola fuente de colores por estado), `MiniStat`, `ReceivingProgressBar`, `AlertBanner` (calmo, inline), `MoneyField`, `QuantityStepper`, `CustomerForm` (compartido entre lista y detalle), `ReceivingLineRow` (compartido entre recepción por línea y por código), `SyncStatusPill`, `ScannerButton`.
- Estados: `ContentUnavailableView` para vacíos, `redacted(.placeholder)` para carga, errores inline (nunca alertas bloqueantes por estar offline).
- Hápticos: éxito al agregar al carro / escanear, error al escanear código desconocido.

---

## 11. Plan de entrega por slices

| # | Slice | Contenido | Criterio de salida |
|---|---|---|---|
| 0 | Fundación | `project.yml` (XcodeGen), workflow `ios.yml` que produce IPA sin firmar, app "Hola" instalada con Sideloadly, paquetes, `Core` con normalizadores + reglas de precio + tests (`swift test` en Windows), `APIClient` base, DesignSystem mínimo, pantalla Diagnóstico | IPA de CI instalada en el iPhone y tests de `Core` verdes |
| 1 | Sesión | Login, restaurar sesión, logout, `SessionSummary` offline | Entrar online y offline |
| 2 | Catálogo + stock (lectura) | Pull de catálogo y stock a SwiftData, Productos con búsqueda | Productos visibles en modo avión |
| 3 | Venta | POS, escáner EAN, Carro persistido, reglas de precio, venta online | Venta registrada con motivo |
| 4 | Cola offline | `PendingMutation`, `SyncEngine` push/pull, `NWPathMonitor`, pastilla de estado, Ajustes › estado offline | Venta en modo avión sincroniza sola al volver la red, sin duplicar |
| 5 | Inventario | Conciliación, EAN (teclado + escáner), kardex | Conciliación offline auditada |
| 6 | Recepción | Lista/detalle pedidos, por línea, por código con escáner continuo, cerrar/reabrir, faltantes → conciliación | Pedido recibido completo offline |
| 7 | Natura + OCR | Importar pedidos (online), historial de importaciones, foto de boleta → OCR → propuestas | Import y OCR funcionando contra backend |
| 8 | Clientes | Clientes, pedidos por ciclo, creación rápida de producto, todo offline | Pedido de cliente creado offline y sincronizado |
| 9 | Pulido | Conflictos (revisar venta fallida), BG refresh, accesibilidad | Uso diario estable con re‑firma semanal |
| 10 | Siguiente (de `plan.md` slice 6) | Convertir pedido de cliente en venta, historial por cliente, reportes de margen | — |

Las correcciones de backend del §9 (1–3) deben estar antes del slice 4.

### Estado

| Etapa | Estado |
|---|---|
| 0 · Fundación | ✅ Completada (2026‑11‑23): XcodeGen, CI verde (18 tests de `Core` + IPA sin firmar), shell de 5 tabs + Diagnóstico. Pendiente: confirmar instalación con Sideloadly en el iPhone. |
| 1 · Sesión | ✅ Implementada (2026‑11‑23): `APIClient` (transporte propio, cookie de sesión en Keychain porque la del backend no tiene `Expires`, mapeo de errores, tests en Linux), `Persistence` (`SessionSummary`), login con URL de servidor, restauración online/offline (`SessionRestorePolicy` en `Core`), revalidación en foreground, logout que borra datos locales, Diagnóstico con "Probar conexión". |
| 2 · Catálogo + stock | ✅ Implementada (2026‑11‑23): paquetes `DesignSystem` (StatusBadge, MiniStat, AlertBanner, MoneyText), `Sync` (`SyncEngine.pullAll`: catálogo, stock y ajustes; merge que no pisa entidades pendientes) y `Features` (Session, Settings, Catalog). Modelos `CatalogProduct`, `StockItem`, `SellerSettings`, `DatasetSyncState`. Productos con búsqueda nombre/SKU/EAN (`ProductSearch` en `Core`), detalle de lectura, pull‑to‑refresh. Ajustes: FIFO/LIFO (online) y estado por dataset. |
| 3 · Venta | ✅ Implementada (2026‑11‑24): Vender (vendibles con stock, búsqueda, escáner VisionKit con *addFirstExactMatch*, háptico), Carro persistido (`CartDraft`/`CartDraftLine`) con stepper ≤ stock, `MoneyField`, motivo filtrado por categoría (`CartRules`), cliente opcional y nota; registro local + push inmediato; Historial de ventas. |
| 4 · Cola offline | ✅ Implementada: `PendingMutation` en la misma transacción que el cambio, push ordenado (§7.3, `SyncQueue`) con backoff 1 s…5 min, 4xx ⇒ `failed`, red/5xx ⇒ pendiente; `POST /sync/events` best‑effort; pull de todos los datasets sin pisar lo pendiente; remapeo de IDs locales (§7.6, `LocalID`); bloqueo de mutaciones que dependen de entidades aún locales; `NWPathMonitor` con sync al reconectar; pastilla de estado en todas las pantallas y badge en Ajustes; Ajustes › Estado offline (reintentar/descartar). Venta duplicada (§9.1) se trata como éxito en el cliente. |
| 5 · Inventario | ✅ Implementada: conciliación offline (evento propio, "Delta esperado ±N"), EAN por teclado o escáner con error si pertenece a otro producto, kardex con saldo corrido (`Kardex`) que incluye eventos locales pendientes. |
| 6 · Recepción | ✅ Implementada: lista con badges OCR/revisión y progreso, detalle con MiniStats, recibir por línea (stepper, precio venta, faltante, guardar) y por código con escáner continuo (`ReceivingScan`), asistencia "Aplicar faltantes al stock", cerrar/reabrir (online). Recepción offline con LWW por línea (`receiving.line.confirm`). |
| 7 · Natura + OCR | ✅ Implementada: importar pedidos entregados (credenciales solo en memoria), historial de importaciones, foto de boleta (VNDocumentCamera o PhotosPicker) → multipart a `receipt-ocr` → "Aceptar propuestas". |
| 8 · Clientes | ✅ Implementada: clientes (ficha compartida, búsqueda), pedidos por ciclo con autocompletado de cliente (seleccionado / nuevo), ciclo AAAACC (`CycleCode`), estado, creación rápida SKU + nombre (mutación propia `catalog.product.quick`), todo offline con IDs locales. |
| 9 · Pulido | ✅ Implementada: "Revisar venta" (editar cantidades y reenviar con el mismo `clientMutationId`, o descartar devolviendo stock), `BGAppRefreshTask` (`cl.mynatura.app.refresh`), Diagnóstico con log `OSLogStore` compartible y cola de mutaciones, etiquetas de accesibilidad. |
| 10 · Siguiente | ✅ Implementada: convertir pedido de cliente en venta (carga el carro y lo marca Cumplido al registrar), historial de compras por cliente, reporte de margen por periodo y producto. |
| Local primero (M1–M8) | Desde 2026-11-26 el plan sigue en `local-first-migration.md` §8 (M1–M3 y M5–M7 hechas, M4 descartada, M8 en curso). Las etapas 1–9 de arriba describen la versión con backend: su comportamiento de sync, login y OCR ya no aplica. |
| Validación en iPhone | ⏳ Pendiente: ninguna etapa se ha probado aún en el dispositivo. |

---

## 12. Riesgos

| Riesgo | Control |
|---|---|
| Natura cambia su web o API | Parseo aislado en `Core` (Natura) y `NaturaClient`, con tests; errores visibles en Ajustes › Natura. |
| Pérdida de datos locales | Respaldo JSON con recordatorio, respaldo de iCloud del iPhone, mismo Bundle ID al reinstalar. |
| Credenciales Natura | Solo en el Keychain de este iPhone con Touch ID, si la consultora lo pide; nunca en el respaldo ni en logs. |

---

## 13. Flujo de desarrollo: Windows + GitHub Actions + Sideloadly

Sin Mac y sin cuenta de pago de Apple:

```text
 PC Windows (editor + backend Node con pnpm + PostgreSQL de Windows)
   │  git push
   ▼
 GitHub Actions · runner macOS (Xcode)
   │  xcodegen → xcodebuild archive (SIN firmar) → MyNatura.ipa (artifact)
   ▼
 PC Windows · descargar artifact (gh run download)
   │  Sideloadly firma con Apple ID gratis + instala por USB/Wi‑Fi
   ▼
 iPhone (Modo desarrollador activado)
```

### 13.1 Consecuencias para el diseño

| Restricción | Impacto | Decisión |
|---|---|---|
| No hay Xcode, Simulator ni Previews en Windows | Cada prueba visual = push + build en CI (~5‑10 min) + instalar | Máxima lógica en paquetes Swift puros testeables sin UI (`Core`, `Sync` con fakes). UI simple y con componentes reutilizables. |
| `.xcodeproj` no se puede editar a mano con seguridad | Conflictos y corrupción del proyecto | **XcodeGen**: el proyecto se describe en `project.yml` y se genera en CI. El `.xcodeproj` no se versiona. |
| Apple ID gratis: la app **expira a los 7 días** | Hay que re‑firmar semanalmente | Sideloadly con *auto‑refresh* por Wi‑Fi (PC encendido en la misma red) o reinstalar. **Los datos SwiftData se conservan** si se reinstala con el mismo bundle ID y Apple ID. |
| Apple ID gratis: máx. **3 apps** sideloaded y límite de App IDs por semana | Cada extensión (widget, share extension) cuenta como App ID | **Sin extensiones** en la primera versión: widgets fuera de alcance. Bundle ID fijo (`cl.mynatura.app`), nunca cambiarlo. |
| Capacidades no disponibles con equipo personal gratis | Push notifications, iCloud/CloudKit, App Groups, etc. | El diseño no usa ninguna: SwiftData local + backend propio. `BGTaskScheduler` (Background Modes) y Keychain sí funcionan; si `BGAppRefreshTask` diera problemas, la sync en foreground cubre el caso. |
| Sin debugger | Errores difíciles de diagnosticar | Pantalla oculta **Diagnóstico** en Ajustes: logs de `OSLogStore` del proceso, cola de mutaciones, último error de red, botón "Copiar/compartir log". Crash logs en iPhone: *Ajustes › Privacidad › Análisis*. |
| Repo **privado** | Minutos de macOS limitados en el plan gratis (macOS consume mucho más que Linux; verificar el modelo de cobro vigente en *Settings › Billing* de GitHub) | Ver §13.4. |

### 13.2 Estructura de este repositorio (`Codigo/iOS/Swift`)

```text
./
  project.yml                 # XcodeGen
  MyNatura/                   # target app (SwiftUI)
    App/  Resources/ (Assets.xcassets, Localizable.xcstrings, Info.plist)
  Packages/                   # Core, APIClient, Persistence, Sync, DesignSystem, Features/*
  docs/                       # este diseño
  .github/workflows/ios.yml   # build unsigned IPA (+ tests de paquetes)
```

El backend sigue en el repo `mynatura`; este repo solo contiene la app iOS.

`project.yml` (esbozo):

```yaml
name: MyNatura
options:
  bundleIdPrefix: cl.mynatura
  deploymentTarget: { iOS: "17.0" }
packages:
  Core: { path: Packages/Core }
  APIClient: { path: Packages/APIClient }
  Persistence: { path: Packages/Persistence }
  Sync: { path: Packages/Sync }
  DesignSystem: { path: Packages/DesignSystem }
  Features: { path: Packages/Features }
targets:
  MyNatura:
    type: application
    platform: iOS
    sources: [MyNatura]
    dependencies:
      - package: Core
      - package: APIClient
      - package: Persistence
      - package: Sync
      - package: DesignSystem
      - package: Features
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: cl.mynatura.app
        SWIFT_VERSION: "6.0"
        TARGETED_DEVICE_FAMILY: "1"
        INFOPLIST_FILE: MyNatura/Resources/Info.plist
```

### 13.3 Workflow de GitHub Actions (esbozo)

```yaml
name: iOS build
on:
  push:
    branches: [main]
    paths-ignore: ["docs/**", "**/*.md"]
  workflow_dispatch:
concurrency: { group: ios-${{ github.ref }}, cancel-in-progress: true }
jobs:
  build:
    runs-on: macos-15
    timeout-minutes: 30
    steps:
      - uses: actions/checkout@v4
      - run: brew install xcodegen
      - run: xcodegen generate
      - uses: actions/cache@v4
        with:
          path: ~/Library/Developer/Xcode/DerivedData
          key: dd-${{ hashFiles('**/Package.resolved', 'project.yml') }}
      - name: Archive (unsigned)
        run: |
          xcodebuild archive -project MyNatura.xcodeproj -scheme MyNatura \
            -configuration Release -destination 'generic/platform=iOS' \
            -archivePath build/MyNatura.xcarchive \
            CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=""
      - name: Package IPA
        working-directory: build
        run: |
          mkdir Payload
          cp -R MyNatura.xcarchive/Products/Applications/MyNatura.app Payload/
          zip -qry MyNatura.ipa Payload
      - uses: actions/upload-artifact@v4
        with: { name: MyNatura-ipa, path: build/MyNatura.ipa, retention-days: 7 }
```

Descarga en Windows: `gh run download --name MyNatura-ipa -D build` y arrastrar el `.ipa` a Sideloadly.
No se necesita ningún certificado ni secreto en GitHub: Sideloadly firma localmente con tu Apple ID.

### 13.4 Ahorro de minutos (repo privado)

- El workflow no corre con cambios solo de documentación; también se puede lanzar a mano; `cancel-in-progress` mata builds obsoletos.
- Caché de DerivedData y de paquetes SPM.
- Los **tests de `Core` corren en Windows** con el toolchain oficial de Swift para Windows (`winget install Swift.Toolchain`): `swift test` dentro de `Packages/Core`. `Core` solo usa Foundation para que esto funcione. SwiftUI/SwiftData no existen en Windows.
- Tests en simulador (`xcodebuild test`) solo en un workflow manual o semanal, no en cada push.
- Agrupar cambios: un push con varios commits = un solo build.
- Como la app iOS ya vive en un repo propio, se puede publicar en GitHub como **repo público**, donde los runners estándar son gratis sin límite. Implica exponer el código del cliente (no contiene secretos; la integración Natura sigue en el backend privado). Si se prefiere privado, aplican los límites de minutos.

### 13.5 Conectar el iPhone al backend de desarrollo

> **Obsoleto desde M7 (2026-11-27):** ya no hay backend al que conectarse.

### 13.6 Preparación única

1. Windows: instalar **Sideloadly** + controladores de Apple (app *Dispositivos Apple* o iTunes de la web de Apple, no de la Microsoft Store si Sideloadly lo indica), `gh` CLI, y opcionalmente el toolchain de Swift.
2. iPhone: *Ajustes › Privacidad y seguridad › Modo de desarrollador* → activar (aparece tras el primer intento de instalación) y confiar en el perfil del Apple ID en *Ajustes › General › VPN y gestión de dispositivos*.
3. Usar un Apple ID dedicado al desarrollo (recomendado) con verificación en dos pasos.

### 13.7 Info.plist mínimo requerido

| Clave | Motivo |
|---|---|
| `NSCameraUsageDescription` | Escáner EAN y foto de boleta |
| `NSPhotoLibraryUsageDescription` | Elegir foto de boleta |
| `NSLocalNetworkUsageDescription` + ATS `NSAllowsLocalNetworking` | Backend de desarrollo en la LAN |
| `UIBackgroundModes: [fetch]` + `BGTaskSchedulerPermittedIdentifiers` | Sync en segundo plano |
| `CFBundleDevelopmentRegion: es` | UI en español |
