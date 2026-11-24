# MyNatura para iOS — Diseño de la app nativa (Swift / SwiftUI)

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
| Natura es la verdad externa (pedidos, SKU, precios sugeridos) | La app no inventa catálogo; solo consume lo que importa el backend. |
| El conteo físico es la verdad operativa | La conciliación es un evento propio; nunca se pisa el historial. |
| Catálogo restringido por cuenta de vendedor | Se muestra `sellerProduct`, nunca el maestro completo. |
| Seguridad en backend | Credenciales Natura **nunca** se guardan en el dispositivo (ni Keychain). Se envían una vez al backend para importar. |
| Offline‑first en UX, backend‑first en consolidación | SwiftData es la fuente de la UI; el backend consolida y valida. |
| UI en español, código en inglés | `Localizable.xcstrings` con `es-CL` como idioma base. |

---

## 2. Decisión de arquitectura

### Recomendación: **cliente nativo SwiftUI + mismo backend**

Se conserva el backend Fastify/PostgreSQL tal cual (con pequeños ajustes, §9) y se reemplaza la PWA por una app nativa.

Motivos:
- El backend ya resuelve lo difícil y sensible: login Natura con **Playwright**, scraping de pedidos (`minegocio.natura.cl`), precios sugeridos desde la **revista digital** (`cl.natura.digital-catalogue.com`), **OCR** con Tesseract + sharp, lotes FIFO/LIFO, RLS por cuenta de vendedor.
- Los requisitos exigen que la integración Natura sea *backend‑owned*. Moverla al teléfono rompe esa regla.
- Los contratos DTO ya están tipados (`backend/src/modules/*/contracts`) y se mapean 1:1 a `Codable`.

Lo que **sí mejora** al ser nativo:
- Escáner de códigos de barras con **VisionKit `DataScannerViewController`** (mucho más rápido y fiable que la cámara web de `ProductsView`).
- Foto de boleta con cámara nativa + recorte/enderezado con **VisionKit `VNDocumentCameraViewController`** antes de enviarla al OCR del backend (mejor tasa de lectura).
- Sincronización en segundo plano con **`BGTaskScheduler`** y conectividad real con **`NWPathMonitor`**.
- Hápticos, swipe actions, `searchable`. (Widgets descartados mientras se use Apple ID gratis: cada extensión consume un App ID, ver §13.)

> Alternativa descartada por ahora: app 100 % local (SwiftData + CloudKit, login Natura en `WKWebView`, OCR con Vision).
> Es viable técnicamente, pero contradice "backend‑owned security", duplica la lógica de lotes y pierde la consolidación central. Queda como evolución posible.

### Stack iOS

| Área | Elección |
|---|---|
| Lenguaje | Swift 6 (strict concurrency) |
| UI | SwiftUI, iOS 17+ (recomendado 18+) |
| Estado | Observation (`@Observable`) — reemplaza Pinia |
| Persistencia local | **SwiftData** — reemplaza IndexedDB (`mynatura-offline`) |
| Red | `URLSession` + `async/await` + `Codable` — reemplaza `http-client.ts` + TanStack Query |
| Sesión | Cookie de sesión en `HTTPCookieStorage` (o token en Keychain si se agrega Bearer, §9) |
| Conectividad | `NWPathMonitor` |
| Sync en background | `BGTaskScheduler` (`BGAppRefreshTask`) + sync al volver a foreground |
| Escáner | VisionKit `DataScannerViewController` (EAN‑13/EAN‑8/Code128 + texto para SKU) |
| Cámara boleta | `VNDocumentCameraViewController` / `PhotosPicker` |
| Íconos | SF Symbols (reemplazan lucide) |
| Tests | Swift Testing / XCTest para dominio y sync (`Core` corre en Windows); XCUITest opcional en CI manual |
| Modularización | Swift Packages locales (abajo) |

### Estructura del proyecto

```text
./
  App/                         # @main, TabView raíz, inyección de dependencias
  Packages/
    Core/                      # Dominio puro: Money, normalizadores, reglas de precio, stock, ciclos
    APIClient/                 # Endpoints + DTOs Codable (espejo de contracts/*.ts)
    Persistence/               # Modelos SwiftData + repositorios locales
    Sync/                      # MutationQueue, SyncEngine, pull/push, ConnectivityMonitor
    DesignSystem/              # Componentes: StatusBadge, MiniStat, ProgressBar, AlertBanner, MoneyField…
    Features/
      Session/                 # Login, logout, restauración
      Sales/                   # Venta (POS), Carro, Historial de ventas
      Catalog/                 # Productos, EAN, conciliación
      Receiving/               # Pedidos Natura, recepción por línea / por código, OCR
      Customers/               # Clientes
      CustomerOrders/          # Pedidos de clientes
      History/                 # Kardex
      Settings/                # Estado offline, FIFO/LIFO, importación Natura
```

Regla de dependencias: `Features → Sync/Persistence/APIClient → Core`. `Core` no importa nada (testeable sin simulador).
Esto replica la separación *domain / application / infrastructure / http* del backend y la de *api / stores / views* del frontend.

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
- Código cliente + contraseña de **la app** (no de Natura). `POST /api/auth/login`.
- Restaura sesión al abrir (`GET /api/auth/me`); si no hay red, usa el `SessionSummary` cacheado en SwiftData para entrar en modo offline.
- Logout: limpia carro, cookies y datos locales de esa cuenta.

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
- Sesión actual (nombre · código).
- **Estado offline**: conectividad, pendientes, fallidos, última sincronización por dataset, botón "Sincronizar ahora", lista de mutaciones fallidas con reintentar/descartar.
- **Salida de inventario**: FIFO ("sale primero el lote más antiguo") / LIFO.
- **Sincronización Natura**: código cliente + contraseña Natura (`SecureField`, **no se guarda**), "Cargar pedidos entregados", spinner con "Conectando con Natura…".
- **Historial de importaciones**: fecha, pedidos, líneas.

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

Equivalencia con los stores de IndexedDB (`frontend/src/shared/offline/db.ts`):

| IndexedDB store | Modelo SwiftData |
|---|---|
| `session_summary` | `SessionSummary` (sellerId, customerCode, displayName) |
| `seller_settings` | `SellerSettings` (issueStrategy) |
| `seller_catalog` | `CatalogProduct` (+ `[String] barcodes`) |
| `inventory_stock_summary` | `StockItem` |
| `natura_orders` / `natura_order_lines` | `NaturaOrder` ↔ `NaturaOrderLine` (relación) |
| `customers` | `Customer` |
| `customer_orders` | `CustomerOrder` ↔ `CustomerOrderLine` |
| `sync_metadata` | `DatasetSyncState` (dataset, lastSyncedAt, status, error) |
| `pending_mutations` | `PendingMutation` |
| (carro persistido) | `CartDraft` / `CartDraftLine` |
| — nuevo — | `LocalSale` (ventas creadas offline, visibles en historial antes de sincronizar) |

```swift
@Model final class CatalogProduct {
    @Attribute(.unique) var id: String        // sellerProductId
    var sellerId: String
    var naturaSku: String
    var name: String
    var source: ProductSource                 // .manual / .catalog / .orderImport
    var isSellable: Bool
    var lastPurchasePesos: Int
    var lastSuggestedSalePesos: Int?
    var barcodes: [String]
    var syncState: EntitySyncState            // .synced / .pending / .failed
}

@Model final class PendingMutation {
    @Attribute(.unique) var id: UUID           // = clientMutationId (idempotencia)
    var type: MutationType
    var sellerId: String
    var entityKey: String
    var payload: Data                         // JSON del DTO de entrada
    var status: MutationStatus                // .pending / .syncing / .failed
    var retryCount: Int
    var createdAt: Date
    var lastErrorMessage: String?
}
```
Todo se filtra por `sellerId` (multi‑sesión segura en el mismo dispositivo). Archivo SwiftData con `FileProtectionType.completeUntilFirstUserAuthentication`.

---

## 7. Motor de sincronización (paquete `Sync`)

### 7.1 Tipos de mutación (mismos que la PWA)
`sale.create`, `inventory.reconciliation.create`, `receiving.line.confirm`, `catalog.barcode.add`, `customer.create`, `customer.update`, `customer-order.create`, `customer-order.update`.

### 7.2 Escritura (siempre local primero)
1. Aplicar el cambio al modelo SwiftData (UI se actualiza al instante).
2. Insertar `PendingMutation` en la **misma transacción** (`modelContext.save()`).
3. Marcar la entidad `.pending`.
4. Si hay red → `SyncEngine.pushNow()`.

### 7.3 Push — orden determinista
`customer → customer-order → barcode → receiving → reconciliation → sale` (inventario al final), luego FIFO por `createdAt` dentro de cada grupo.
Reintento con backoff exponencial (1s, 2s, 4s… tope 5 min). Errores **4xx de regla de negocio** ⇒ `.failed` (no reintenta solo, requiere revisión); **red/5xx** ⇒ sigue `.pending`.
Tras cada lote: `POST /api/sync/events` para auditoría (igual que hoy).

### 7.4 Pull — refresco de datasets
`catalog`, `stock`, `natura orders (+lines)`, `customers`, `customer orders`, `settings`, `pricing reasons`.
Se hace: al iniciar sesión, al volver a foreground, tras un push exitoso, con pull‑to‑refresh y en `BGAppRefreshTask`.
Regla de merge: **no sobrescribir entidades con mutaciones pendientes** (se re‑aplican los cambios locales encima del snapshot remoto).

### 7.5 Conflictos (por operación, según `offline-strategy.md`)
| Operación | Política |
|---|---|
| Venta | Si el backend rechaza (stock insuficiente, lotes) → `failed`, pantalla "Revisar venta" (editar cantidades / descartar). Nunca se pisa. |
| Conciliación | Nunca se fusiona; fallida → reintentar o reemplazar con nuevo conteo. |
| Recepción | Last‑write‑wins si el pedido sigue en borrador; si ya está cerrado → `failed` + aviso "reabre el pedido". |
| EAN | EAN ya usado por otro producto → `failed` con resolución manual. |
| Clientes / pedidos | LWW en campos de perfil; reglas de negocio rechazadas → `failed` con reintento manual. |

### 7.6 Mapeo de IDs locales
Clientes y pedidos creados offline usan UUID local. Al sincronizar, si el backend devuelve otro `id`, el engine reescribe referencias en mutaciones pendientes posteriores (p. ej. un `customer-order.create` que apunta a un `customer.create` local). Recomendado: que el backend **acepte el UUID del cliente** como `id` para evitar el remapeo (§9).

---

## 8. Capa de red (paquete `APIClient`)

```swift
protocol APIClient: Sendable {
    func send<R: Decodable>(_ endpoint: Endpoint<R>) async throws(APIError) -> R
}

enum APIError: Error {
    case offline, unauthorized, validation(message: String), conflict(message: String), server(status: Int), decoding
}
```
Endpoints a cubrir (verificados contra `backend/src/modules/*/http/*-routes.ts`, prefijo `/api`):

| Módulo | Endpoints |
|---|---|
| auth | `POST /auth/login`, `GET /auth/me`, `POST /auth/logout` |
| seller / settings | `GET /seller/profile`, `GET /settings`, `PUT /settings` |
| catalog | `GET /catalog/products`, `GET /catalog/master-products/lookup`, `POST /catalog/products/quick`, `POST /catalog/products/:sellerProductId/barcodes` |
| inventory | `GET /inventory/stock-summary`, `GET /inventory/receipts`, `GET /inventory/activity`, `POST /inventory/reconciliations` |
| sales | `GET /sales`, `POST /sales`, `GET /sales/pricing-reasons` |
| natura | `POST /natura/import-runs/delivered-orders`, `GET /natura/import-runs`, `GET /natura/orders`, `GET /natura/orders/:orderId`, `PATCH /natura/orders/:orderId/lines/:lineId`, `PATCH …/line-prices`, `PATCH …/receiving`, `POST …/receiving-scan`, `PATCH …/receiving-review`, `POST …/receipt-ocr` (multipart) |
| customers | `GET /customers?q=`, `POST /customers`, `GET /customers/:customerId`, `PATCH /customers/:customerId` |
| customer-orders | `GET /customer-orders`, `POST /customer-orders`, `GET /customer-orders/:orderId`, `PATCH /customer-orders/:orderId` |
| sync | `GET /sync/status`, `POST /sync/events` |

Ideal: generar el cliente desde el OpenAPI que ya expone `@fastify/swagger` con **swift-openapi-generator**.

DTOs: `struct`s `Codable, Sendable` espejo de `contracts/*.ts`, con `JSONDecoder.dateDecodingStrategy = .iso8601`.

---

## 9. Ajustes necesarios en el backend

Hallazgos del análisis que conviene resolver antes (o en paralelo) para que la app nativa sincronice sin fricción:

1. **Idempotencia de ventas**: `createSale` lanza error *"La venta ya fue registrada previamente"* si el `clientMutationId` existe. Si la respuesta se pierde en la red y el teléfono reintenta, la venta quedaría como *fallida* aunque esté guardada. → Devolver **200 con la venta existente**.
2. **Clave de idempotencia en el resto de mutaciones** (conciliación, recepción, EAN, clientes, pedidos): aceptar `clientMutationId` / header `Idempotency-Key`. Hoy solo ventas la tienen.
3. **IDs generados por el cliente** para `customers` y `customer_orders` (aceptar `id` UUID opcional) → elimina el remapeo de IDs.
4. **Autenticación móvil**: la sesión es por cookie. Funciona con `HTTPCookieStorage`, pero se recomienda emitir también un token opaco revocable (Bearer) guardado en **Keychain** con `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`.
5. **Import asíncrono**: `POST delivered-orders` es síncrono (Playwright + scraping + revista puede tardar mucho). En móvil conviene `202 + runId` y polling de `GET /natura/imports/:runId` para no depender de una conexión abierta minutos.
6. **Validación de precio**: el backend valida contra `product.lastSuggestedSaleUnitPriceCents` pero guarda el sugerido del lote. Unificar criterio para que la validación offline en `Core` coincida 100 %.
7. **Pull incremental** (opcional): `?updatedSince=` en catálogo, clientes y pedidos para no bajar todo en cada sync.

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
| Validación en iPhone | ⏳ Pendiente: ninguna etapa se ha probado aún en el dispositivo (solo CI: tests de `Core`/`APIClient` en Linux + IPA). |
| Backend §9 | ✅ (2026‑11‑24, repo `mynatura`, rama local `feat/ios-idempotency` sin push): §9.1 una venta con `clientMutationId` repetido devuelve la venta existente (también si dos envíos chocan en la restricción única); §9.2 cabecera `Idempotency-Key` + tabla `client_mutations` (RLS) en conciliaciones, clientes, pedidos de clientes, EAN, creación rápida y recepción de línea — la app envía el id de la mutación. Verificado con Postgres temporal + HTTP. §9.3 descartado: lo cubre el remapeo de IDs (§7.6). §9.5 mitigado en la app con timeout de 10 min para importar y 3 min para OCR. Pendiente: aplicar la migración (`npm run db:migrate`). |

---

## 12. Riesgos

| Riesgo | Control |
|---|---|
| Natura cambia su web (scraping HTML `#order-items-list`, revista digital) | Sigue aislado en backend; la app no se entera. Mantener los errores de import visibles en Ajustes. |
| Divergencia entre validación offline y backend | Reglas en `Core` con tests espejo de los casos del backend; backend sigue siendo autoridad. |
| Ventas duplicadas por reintentos | `clientMutationId` = id de `PendingMutation` + backend idempotente (§9.1). |
| Pérdida de datos locales | SwiftData con protección de archivo; nunca borrar `PendingMutation` hasta confirmación 2xx. |
| Credenciales Natura | Solo en memoria durante la llamada de import; nunca persistidas en el dispositivo. |

---

## 13. Flujo de desarrollo: Windows + GitHub Actions + Sideloadly

Sin Mac y sin cuenta de pago de Apple:

```text
 PC Windows (editor + backend Docker)
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

- **Opción simple (misma Wi‑Fi):** backend Docker en el PC, la app apunta a `http://<IP-LAN-del-PC>:<puerto>`. Requiere en `Info.plist`: `NSAppTransportSecurity › NSAllowsLocalNetworking = YES` y `NSLocalNetworkUsageDescription`; abrir el puerto en el firewall de Windows y configurar CORS/cookies del backend para ese origen.
- **Opción túnel (fuera de casa):** `cloudflared tunnel` o similar → URL HTTPS pública temporal; sin excepciones de ATS.
- La URL del backend se elige en la pantalla **Diagnóstico** (Dev / Túnel / Producción), guardada en `UserDefaults`.

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
