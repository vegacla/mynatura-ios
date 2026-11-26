# Propuesta — Asistente unificado: cámara + voz → menú de acciones contextual

> **Estado:** propuesta, sin implementar (2026-11-26).
> Reúne en **una sola interfaz** lo que hoy está repartido: dictado por voz (`voice-interaction-proposal.md`), foto y escaneo de producto (`product-photo-proposal.md`), consultas y Atajos. Agrega las acciones que existen en Natura pero aún no en la app (vencimientos de pago, crédito, ciclo actual, ofertas, revista, carro de pedido).
> Considera el equipo de uso: iPhone SE 3.ª gen., pantalla de 4,7", sin Apple Intelligence.
> Se apoya en las capturas de `docs/har/`. Esa carpeta **no se versiona** (`.gitignore`): aquí solo hay rutas y nombres de campos, nunca valores.

---

## 1. Idea

Un único **Asistente** que acepta cualquier entrada y responde siempre igual:

```
  ENTRADA                    →   QUÉ ES (entidad)           →   ACCIONES (botones + voz)   →   EJECUCIÓN
  escanear código de barras      Producto                       tomar inventario                acción local (offline)
  foto de etiqueta               Cliente                        agregar a la venta              o consulta online
  voz ("¿qué me encargó Ana?")   Pedido de cliente              enviar revista                  con confirmación
  texto (teclado)                Pedido Natura                  ver vencimientos…               cuando cambia datos
  pantalla actual (contexto)     Ciclo · Cuenta · Revista · …
```

- **Entrar es siempre igual:** un botón fijo (micrófono + cámara) en todas las pantallas y un Atajo de Siri ("Asistente de MyNatura").
- **Lo reconocido** (un producto escaneado, un cliente nombrado, "el ciclo") se muestra como una **tarjeta de entidad**.
- Debajo, **solo las acciones que aplican**: como botones grandes y, a la vez, como frases que se pueden decir ("a la venta", "¿cuándo vence?").
- **Ejemplo:** escaneo un Kaiak → tarjeta del producto → [Tomar inventario] [Agregar a la venta] [Agregar a pedido] [Más…]. Digo "¿en qué pedido viene?" → responde y ofrece [Recibir +1 en pedido 123456].
- **Contexto conversacional:** la última entidad queda activa. "¿Y cuánto queda?" o "agrégalo al pedido de Ana" se refieren a ella hasta que aparezca otra.

---

## 2. Principios

1. **Un solo lugar, cualquier entrada.** Cámara, voz y texto llevan a la misma tarjeta y al mismo menú.
2. **Propone, la pantalla confirma.** Lo que cambia datos (stock, ventas, pedidos, Natura) muestra un paso visible antes de guardar. La voz elige o prepara el botón; ejecutarlo es un toque.
3. **Nunca por voz sola:** registrar venta, **enviar o confirmar el pedido a Natura**, borrar, ni tocar credenciales.
4. **Offline primero.** Lo local siempre responde. Lo que necesita a Natura (vencimientos, crédito, ofertas, carro GSP) se marca **"requiere conexión"** y se deshabilita con explicación si no hay red.
5. **Credenciales de Natura solo en memoria** (regla del proyecto). Las acciones online de Natura piden la contraseña **una vez por sesión del Asistente** y no la guardan.
6. **Pantalla chica.** Hoja a media altura: tarjeta, 4 botones principales y "Más…" agrupado. La cámara o la transcripción quedan arriba.

---

## 3. Entradas y cómo se resuelven

| Entrada | Tecnología (ya en la app o en Vision) | Resuelve a |
|---|---|---|
| **Escáner en vivo** | `DataScannerViewController`, como en recepción | EAN → **Producto** (exacto). Código 5–7 dígitos → Producto por código Natura |
| **Foto de etiqueta** | `PhotoAnalyzer` (OCR + códigos) + `ProductRecognizer` | **Producto** (código impreso / nombre) o "Crear producto" |
| **Voz** | `SpeechCaptureService` + `CommandGrammar` (contexto `.assistant`, nuevo) + vocabulario propio (V6) | **Intención + entidades**: producto, cliente, periodo, pedido, ciclo |
| **Texto** | Campo de búsqueda/comando con la misma gramática | Igual que voz (para ruido o silencio) |
| **Pantalla actual** | `AppRouter` sabe dónde estás | Entidad implícita: en un producto, "conté siete" va a ese producto; en un pedido, "agrega dos del 12345" va a ese pedido |

**Entidades** (`AssistantEntity`, en `Core`):
`product(id)` · `customer(id)` · `customerOrder(id)` · `naturaOrder(id)` · `sale(id)` · `cycle` · `account` (pagos/crédito) · `magazine(cycle)` · `offer(code)` · `naturaCart` · `app` (sincronización, ajustes).

Si la resolución es ambigua (dos Humor, dos Juan), la tarjeta muestra los candidatos para elegir, igual que hoy en la voz y la foto.

---

## 4. Catálogo completo de acciones

Leyenda de estado:
- ✅ ya existe en la app (se reutiliza);
- 🟡 existe en Natura o en el backend, pero no en la app (ver §6);
- 🆕 nuevo y local;
- ⛔ bloqueado por una decisión o una captura.

Columna **Red**: 🔌 requiere conexión; vacío = funciona offline.

### 4.1 Producto (tras escanear, fotografiar o nombrar)

| Acción | Frases de ejemplo | Estado | Red |
|---|---|---|---|
| Ver stock operativo y teórico | "¿cuánto queda?" | ✅ consulta V4 | |
| Tomar inventario (conciliación) | "conté siete", "inventario" | ✅ | |
| Inventario de repisa (escaneo continuo, +1 por lectura) | "inventario de repisa" | ✅ P3 | |
| Asociar el EAN leído | "asocia el código" | ✅ | |
| Agregar a la venta (carro) | "a la venta", "véndelo" | ✅ | |
| Agregar a pedido de cliente (abierto o nuevo) | "al pedido de Ana" | ✅ | |
| Recibir +1 en pedido Natura abierto | "recíbelo", "¿en qué pedido viene?" | ✅ | |
| Ver ficha y kardex | "ver ficha", "movimientos" | ✅ | |
| Último precio de compra y sugerido; margen | "¿a cuánto lo compré?", "¿cuánto le gano?" | 🆕 (datos locales: compra, sugerido, ventas) | |
| ¿Quién lo encargó? (pedidos de clientes abiertos con este producto) | "¿quién lo pidió?" | 🆕 local | |
| Historial de ventas del producto | "¿cuántos vendí este mes?" | 🆕 local | |
| ¿Está en la revista del ciclo? Precio revista y página | "¿está en la revista?" | 🟡 revista (§6.4) | 🔌 la 1.ª vez |
| Puntos y precio de compra del ciclo; ofertas que lo incluyen | "¿cuántos puntos?", "¿tiene oferta?" | 🟡 `cardSection` (GSP) | 🔌 |
| Compartir producto con un cliente (foto/nombre/precio por WhatsApp) | "mándaselo a Ana" | 🆕 (`ShareLink` / `wa.me`) | 🔌 al enviar |
| Agregar al carro del pedido Natura | "pídelo a Natura", "agrega tres al pedido Natura" | ⛔ `addProductsToCart` (§6.3), con borrador y confirmación | 🔌 |
| Crear producto (si no existe) | "créalo" | ✅ (prellenado con lo leído) | |

### 4.2 Cliente

| Acción | Frases | Estado | Red |
|---|---|---|---|
| Ver ficha (RUT, teléfono, notas) | "ficha de Ana" | ✅ | |
| Encargos pendientes | "¿qué me encargó Ana?" | ✅ V4 | |
| **Último pedido** del cliente | "trae el último pedido de Ana" | 🆕 local (`CustomerOrder` más reciente) → abre el editor | |
| Nuevo pedido para el cliente (con dictado) | "nuevo pedido para Ana" | ✅ V2/V7 | |
| Convertir su pedido en venta | "véndele su pedido" | ✅ (carga el carro; registrar es un toque) | |
| Historial de compras y total del periodo | "¿cuánto me ha comprado Ana?" | 🆕 local (`LocalSale.customerId`) | |
| **Enviar revista** del ciclo por WhatsApp | "envíale la revista a Ana" | 🆕 (link oficial con `id_consultora`; `wa.me` con su teléfono) | 🔌 |
| Llamar / escribir por WhatsApp | "llama a Ana" | 🆕 (`tel:` / `wa.me`) | |
| Recordatorio de cobro o de entrega (texto armado para WhatsApp) | "recuérdale a Ana que me debe" | 🆕 (requiere registrar deudas de clientes: hoy no existe) | |

### 4.3 Pedidos de clientes

| Acción | Frases | Estado | Red |
|---|---|---|---|
| Listar abiertos del ciclo | "pedidos pendientes" | ✅ | |
| Abrir, editar y dictar | "abre el pedido de Ana", "agrega dos del 12345" | ✅ V2 | |
| Cambiar estado (confirmar, cumplir, cancelar) | "confirma el pedido de Ana" | ✅ (con confirmación) | |
| Sumar encargos del ciclo por producto (base del pedido Natura) | "¿qué tengo que pedir?" | 🆕 local (`natura-order-placement.md` §5.3) | |

### 4.4 Pedidos Natura (los míos)

| Acción | Frases | Estado | Red |
|---|---|---|---|
| **Último pedido Natura** (número, estado, total, puntos) | "trae el último pedido", "¿cómo va mi pedido?" | ✅ local (importados) + 🟡 estados en vivo (`/pedidos/ajax/orders` con `statusIds[]`) | 🔌 para estado en vivo |
| Recepción: progreso, por línea o por código, dictada | "recibir pedido", "llegaron cuatro del…" | ✅ V3 | |
| Comprobante (foto → OCR) | "foto de la boleta" | ✅ | 🔌 |
| Aplicar faltantes, cerrar o reabrir | "cerrar pedido" | ✅ (con confirmación) | 🔌 cerrar/reabrir |
| Importar pedidos entregados | "carga mis pedidos" | ✅ (pide contraseña Natura) | 🔌 |
| N.º de factura y fecha de aprobación | "¿cuál es la factura?" | 🟡 campos `invoiceNumber` / `approvalDueDate` | 🔌 |

### 4.5 Cuenta con Natura: pagos y crédito

| Acción | Frases | Estado | Red |
|---|---|---|---|
| **Vencimientos de pago** (próximo vencimiento, saldo, atrasos) | "¿cuándo vence mi pago?", "¿debo algo?" | 🟡 `/pedidos/ajax/mis-cuentas` (§6.1) | 🔌 |
| Documentos vencidos y días de atraso | "¿tengo atrasos?" | 🟡 `isOverdue`, `overdueDays` | 🔌 |
| **Crédito disponible** y límite | "¿cuánto crédito tengo?" | 🟡 `profileGetRefreshToken.payload.credit` (§6.3) | 🔌 |
| Aviso de cuenta bloqueada | (automático en la tarjeta) | 🟡 `isBlocked`, `blockReason` | 🔌 |

### 4.6 Ciclo y revista

| Acción | Frases | Estado | Red |
|---|---|---|---|
| **Ciclo actual** con fechas y días para el cierre | "¿qué ciclo es?", "¿cuándo cierra?" | 🟡 `summary.orderCycle` del carro GSP (§6.3) o home; hoy ✅ solo el último ciclo registrado | 🔌 1 vez por ciclo |
| **Enviar revista** (link oficial) a un cliente o a varios | "envía la revista", "mándala a mis clientes" | 🆕 (link de la revista del ciclo; `ShareLink`) | 🔌 |
| Abrir la revista (visor / PDF completo) | "abre la revista" | 🟡 `catalogue.pdf`, páginas `.webp` (`natura-order-placement.md` §2.3) | 🔌 |
| Buscar en la revista (código, nombre, página) | "¿en qué página está el Ekos?" | 🟡 índice de revista ya usado por el backend | 🔌 |
| **Ofertas del ciclo** | "¿qué ofertas hay?" | 🟡 `cardSection` / `getPromotion` (§6.3) | 🔌 |

### 4.7 Ventas

| Acción | Frases | Estado | Red |
|---|---|---|---|
| Dictar venta (carro) | "nueva venta", "dos Kaiak a nueve noventa" | ✅ V5 | |
| ¿Cuánto vendí? (hoy, semana, mes…) | "¿cuánto vendí esta semana?" | ✅ V4 | |
| Margen del periodo y por producto | "¿cuánto gané este mes?" | ✅ reporte + 🆕 respuesta hablada | |
| Última venta, repetir venta | "repite la última venta" | 🆕 (carga el carro) | |

### 4.8 Pedido Natura del ciclo (borrador → carro GSP)

| Acción | Frases | Estado | Red |
|---|---|---|---|
| Armar borrador desde encargos + reposición | "arma el pedido del ciclo" | ⛔ `natura-order-placement.md` etapas 1–2 | |
| Puntos vs. tope del nivel | "¿cuántos puntos llevo?" | ⛔ `getCart`: `totalPoints`, `availablePoints`, `minimumPointsOrder` | 🔌 |
| Enviar líneas al carro GSP, producto a producto | "pásalo a Natura" | ⛔ `addProductsToCart`, `CartRemoveItem` | 🔌 |
| Regalos y promociones del carro | "¿qué regalos me tocan?" | ⛔ `giftItems`, `promotions` | 🔌 |
| **Confirmar el pedido en Natura** | — (solo botón, nunca voz) | ⛔ checkout no capturado | 🔌 |

### 4.9 App

| Acción | Frases | Estado |
|---|---|---|
| Estado de sincronización, sincronizar ahora, ver fallidos | "¿está todo sincronizado?", "sincroniza" | ✅ |
| Ir a una pantalla | "ir a recepción", "abre ventas" | 🆕 (navegación por voz, pendiente en `pending.md`) |
| Ayuda: "¿qué puedo decir aquí?" | "ayuda" | 🆕 (lista de frases del contexto actual) |

---

## 5. Interfaz

```
┌──────────────────────────────┐
│  [cámara en vivo / foto]     │  ← modo Escanear (por defecto) · Foto · Voz · Texto
│   o transcripción en vivo    │
├──────────────────────────────┤
│  ◉ Kaiak Clásico · SKU 12345 │  ← tarjeta de entidad (con "¿no es este?")
│  Stock 3 · $12.990 · 25 pts  │
│  [Inventario] [A la venta]   │  ← 4 acciones principales según contexto
│  [A pedido]   [Recibir +1]   │
│  Más…  (agrupadas por tema)  │
│  🎤 mantén para hablar        │  ← siempre visible; respuesta en texto + voz
└──────────────────────────────┘
```

- **Acceso:** el botón "Preguntar" actual se convierte en el **Asistente**, junto a la pastilla de sincronización, en todas las pantallas. También desde el Atajo "Asistente de MyNatura".
- **Modo por defecto:** Escanear, porque es el más rápido. Se cambia con un toque (Foto, Voz, Texto) y se recuerda el último.
- **Acciones principales:** las elige `Core` según la entidad y el contexto: stock, si hay pedido Natura abierto, si es vendible, la pantalla de origen.
- **"Más…":** el resto, agrupado como en §4.
- **Respuestas:** las consultas responden en la tarjeta (y en voz, si está activado). Las acciones abren su paso de confirmación dentro de la misma hoja; no se navega fuera salvo "ver ficha".
- **Encadenar:** después de una acción la entidad sigue activa. "Siguiente" vuelve a escanear sin cerrar.
- **Ayuda contextual:** "¿qué puedo decir?" lista las frases de las acciones visibles.

---

## 6. Datos que faltan (de las capturas `docs/har/`)

Solo formas; sin valores. Todo se consume **vía backend**: la app nunca habla con Natura directo. El backend inicia sesión con la contraseña en memoria, como el import.

### 6.1 minegocio — cuentas y pedidos
- `GET /pedidos/ajax/mis-cuentas?order=…&state=…` → `[{ number, orderingNumber, isOpen, isOverdue, issueDate, dueDate, originalValue, currentBalance, overdueDays, orderStatus }]`. Es la fuente de **vencimientos de pago**.
- `GET /pedidos/ajax/orders/{codigoConsultora}/0?page&pageSize&orderId&statusIds[]` agrega a lo conocido:
  - `statusIds[]` (filtrar por estado);
  - `totalPoints`, `invoiceNumber`, `approvalDueDate`, `orderDueDate`, `orderPaymentStatus`, `orderCycleDay`, `channelId`, `structureCode`.
- `GET /cards` → tarjetas informativas del home (`category`, `dateStart`, `dateEnd`, `metadata`…). Posibles avisos para mostrar en la tarjeta de Cuenta.
- **"Ciclo Actual":** el texto no está en el HTML del home (se arma en el navegador), pero el HTML trae `var query_cycle = [AAAACC]`, que en la captura vale el ciclo vigente (202619). Es el **número de ciclo sin GSP**, con la sesión de minegocio que el backend ya tiene. Las **fechas** de inicio y fin están en `summary.orderCycle { cycleCode, dateStart, dateEnd }` del carro GSP (§6.3).

### 6.2 Login
- `POST authenticator-cognito-apigw…/authentication-api/signin` → `{ sso_token, challengeRequired, daysExpirePassword, authToken }`. Ya implementado en el backend (`natura-http-auth.ts`): usa **solo `sso_token`** → `natura-callback` → cookie `wcmn_session` (minegocio). El `authToken` (36 caracteres, opaco) **no se usa** en ninguna parte del backend.
- **GSP usa otra credencial:** encabezados `x-app-token` / `xapptoken` (JWT HS256 de unos 3400 caracteres, vigencia de 24 h, claims `compressed`, `filePath`, `iat`, `exp`), `sessionidentifier`, `http_username`, `application` y `country`. No usa `Authorization` ni cookies. Se renueva con `profileGetRefreshToken`, que devuelve `xAppToken`.
- **Cómo entra GSP** (captura `popup-gsp`, 2026-11-26). "Nuevo Pedido" abre `gsp.natura.com/login?country=CL` en otra pestaña, sin token, y sigue esta cadena:
  1. `natura-auth.prd.naturacloud.com/?company&client_id&redirect_uri&country&language`, con el **client_id de GSP** (público, en la URL, distinto al de minegocio) y `redirect_uri=https://gsp.natura.com/`. No usa cookies de sesión (solo Akamai/GA): la página reutiliza un **token de 36 caracteres guardado en el navegador** del login anterior.
  2. `POST authenticator-cognito-apigw…/authentication-api/recover-session` (encabezado `x-api-key`, la misma del signin) con `{ token, redirectUrl, clientId }` → `{ accessToken, idToken, expiresIn }`. Son JWT de **Cognito**, de 6 h. El `idToken` trae, entre otros, `natura_code`, `personId`, `gsp_profiles` y `country`.
  3. Redirige a `gsp.natura.com/?sso_token=<ese mismo token>`, y GSP repite `recover-session` con `{ token }`.
  4. GraphQL con `Authorization: Bearer <accessToken>` y `x-app-token` **vacío**: `authPersonData` → `profileOtherCycles` → `authCommercialInfo`. Cada respuesta trae un `xAppToken` (crece de ~200 a ~3400 caracteres), que se reenvía en la siguiente. Después ya funcionan `consultantSection`, `syncBasket`, `cardSection`, `getCart`, etc. (con `http_username` y `application`).
- **Verificado (2026-11-26, `natura:probe-gsp-login` en el backend):** el token que sirve es el **`sso_token`** del signin, el mismo que va a `natura-callback` de minegocio. El `authToken` **no** sirve.
  Cadena completa sin navegador, con la misma contraseña en memoria: signin → `recover-session(sso_token, clientId GSP)` → GraphQL `authPersonData` / `profileOtherCycles` / `authCommercialInfo` → `xAppToken` → `consultantSection`.
  Devolvió ciclo 19/2026, del 26-11 al 09-12, 13 días restantes, estado `CURRENT`. **Playwright no hace falta para GSP.**
  Implementado en `backend/src/modules/natura-integration/infrastructure/natura-gsp-auth.ts` (repo `mynatura`).
- **`consultantSection.actualCycle`** trae `{ number, label, startDate, endDate, year, status, remainingDays, orderDate }`: el **ciclo actual con fechas y días restantes** sin abrir el carro. `authCommercialInfo` trae `credit` e `isBlocked`. El backend no tiene ningún conocimiento de GSP: ni el login por HTTP ni el respaldo con Playwright pasan por ahí.

### 6.3 GSP — pedido nuevo (`gsp-apigw-mfe.prd.naturacloud.com/graphql/frontend/graphql`)
El pedido **no se arma en minegocio**: se arma en la app GSP, sobre GraphQL. Operaciones observadas:

| Operación | Variables (forma) | Respuesta útil |
|---|---|---|
| `profileGetRefreshToken` (GET) | — | `payload.credit { available, limit, additional }`, `isBlocked`, `blockReason`, **`xAppToken`** |
| `syncBasket` | `{ cycle }` | `{ total, cartId, shouldRedirectToCart }` |
| `cardSection` | `{ context, cycle, category, page, filterOptions, lastPromotionCodes }` | productos y ofertas: `code, name, image, points, purchasePrice, resalePrice, promotionSummary, gifts, discountTag, stockStatus` |
| `addProductsToCart` | `{ products: [{ code, quantity, itemTypeId }], context, cycle, cartId, version, tags, origin }` | errores por producto (`extensions.errorMessage`) |
| `getCart` | `{ cycle, version }` | `availablePoints, totalPoints, totalPrice, totalProfitability`; por carro: `minimumPointsOrder, pointsStatus, pointsMessage, products` |
| `sendBasketOrder` | `{ context, cycle, version, cycleType }` | `status`. Pasa la **canasta** al **carro**; después `orderNumber` sigue `null`, así que **no confirma** el pedido |
| `CartGet` | `{ cartUid, checkAvailability, recoverDraftItems }` | `purchasedItems, giftItems, promotions, shipping.deliveryMode.deliveryDate, summary.orderCycle, summary.profitability, paymentDueDate` |
| `CartRemoveItem` (persisted query) | `{ cartUid, cartItensUids[], … }` | carro actualizado |
| `CartStatus` | `{ cartUid }` | `statusId` |
| `getPromotion`, `getPendingAcceptanceTerm`, `parametersGetParams`, `parametersMinimumSplitValueCN`, `getSuperTip` | — | promociones, términos pendientes, parámetros (incluye `interactiveMagazineLink`) |

**Corrige y amplía `natura-order-placement.md`:**
- el flujo real es **canasta (`addProductsToCart`, `getCart`) → `sendBasketOrder` → carro (`CartGet`, `CartRemoveItem`) → checkout**;
- **los puntos y el tope** salen de `getCart`;
- el **paso de confirmar** (checkout) **no está capturado**, así que sigue ⛔.

### 6.4 Revista
Ya documentada en `natura-order-placement.md` §2.3 (páginas, PDF, link con `id_consultora`). `parametersGetParams.interactiveMagazineLink` puede dar el link oficial del ciclo sin adivinar la URL.

### 6.5 Endpoints nuevos del backend (propuestos)

| Endpoint MyNatura | Fuente Natura | Para |
|---|---|---|
| `POST /api/natura/account` (credenciales en el body) | `mis-cuentas` + `profileGetRefreshToken` | vencimientos, saldo, atrasos, crédito, bloqueo |
| `POST /api/natura/cycle/current` | `CartGet.summary.orderCycle` (o home) | ciclo actual y fechas; se guarda y sirve offline hasta `dateEnd` |
| `POST /api/natura/offers?cycle=` | `cardSection` / `getPromotion` | ofertas, puntos y precio de compra por código |
| `GET /api/natura/magazine?cycle=` | revista pública | link, páginas e índice (sin credenciales) |
| `POST /api/natura/cart/*` | GSP canasta/carro | etapa ⛔ del pedido Natura |

Respuestas cacheadas en SwiftData con fecha de lectura. La tarjeta muestra "actualizado hace X" y se puede refrescar.

---

## 7. Arquitectura

```
Features
  AssistantSheet      modos Escanear / Foto / Voz / Texto · tarjeta de entidad · acciones · respuestas
  AssistantExecutor   ejecuta acciones con SyncEngine (local) o APIClient (online), con paso de confirmación
  (reusa) BarcodeScannerView · PhotoAnalyzer · SpeechCaptureService · VoiceSpeaker · VoiceModelWarmup
Core (solo Foundation, tests en Linux)
  AssistantEntity     product · customer · customerOrder · naturaOrder · sale · cycle · account · magazine · offer · naturaCart · app
  AssistantIntent     gramática .assistant: une las de V1–V5 + consultas + nuevas frases de §4, con slots de entidad
  AssistantResolver   entrada (código, OCR, texto) + contexto de pantalla + entidad activa → entidad(es)
  AssistantActions    catálogo de §4: id, título, frases, requiere red, requiere confirmación, disponible(entidad, contexto)
  AssistantAnswers    respuestas texto/voz (extiende VoiceAnswers)
```

- **Un registro de acciones** (`AssistantActions`), con una entrada por acción de §4: título, ícono, frases de voz, entidad, `requiresNetwork`, `requiresConfirmation`, `isAvailable(context)`. La UI de botones, la gramática de voz y la ayuda contextual salen del **mismo registro**: agregar una acción la publica en los tres lados.
- **Contexto activo:** `AssistantSession { activeEntity, screen, lastResults }` para "¿y cuánto queda?" o "agrégalo".
- **Lo existente se reutiliza, no se duplica:** las hojas actuales (dictado de pedido, de recepción, de carro, foto de producto) pasan a ser **acciones** del Asistente o siguen como atajos dentro de su pantalla.
- **Sin dependencias nuevas** ni extensiones (compatible con Apple ID gratis).

---

## 8. Plan por etapas

| # | Etapa | Entregable | Red |
|---|---|---|---|
| U1 | Núcleo | `AssistantEntity`, `AssistantActions` (registro de §4 con disponibilidad), `AssistantResolver` y gramática `.assistant` sobre lo existente; tests | — |
| U2 | Hoja unificada | `AssistantSheet` reemplaza "Preguntar": modos Escanear/Foto/Voz/Texto, tarjeta, 4 principales + "Más…"; acciones ✅ ya existentes | offline |
| U3 | Acciones locales nuevas | 🆕 de §4: último pedido del cliente, quién lo pidió, historial y margen hablados, repetir venta, ¿qué tengo que pedir?, navegación, ayuda | offline |
| U4 | Compartir | Enviar revista y producto por WhatsApp (`ShareLink` / `wa.me`), llamar | al enviar |
| U5 | Cuenta y ciclo (backend) | Endpoints §6.5 de cuenta y ciclo; tarjetas de vencimientos, crédito, bloqueo y ciclo con fechas; respuestas de voz | 🔌 |
| U6 | Ofertas y revista (backend) | Ofertas y puntos por producto, búsqueda en revista | 🔌 |
| U7 | Pedido Natura | Integra `natura-order-placement.md` con el flujo GSP de §6.3; confirmar el pedido sigue siendo solo un botón y requiere capturar el checkout | 🔌 ⛔ |

---

## 9. Riesgos

| Riesgo | Mitigación |
|---|---|
| Demasiadas acciones en 4,7" | 4 principales por contexto + "Más…" agrupado; la ayuda dice qué se puede decir |
| Ambigüedad de entidad ("Juan", "Humor") | Candidatos en la tarjeta; la entidad activa evita repetir |
| Acciones online sin red o sin credenciales | Marcadas 🔌; caché con fecha; contraseña Natura solo en memoria por sesión |
| Cambios en GSP/minegocio | Todo pasa por el backend; errores visibles en la tarjeta |
| Errores de voz que ejecutan algo indebido | La voz solo elige o prepara; ejecutar es un toque; dinero y Natura nunca por voz |
| HAR con datos personales | `docs/har/` en `.gitignore`; a los documentos solo pasan formas |

---

## 10. Preguntas abiertas

1. ~~¿Se puede entrar a GSP sin navegador?~~ **Sí** (§6.2): con el `sso_token`. Crédito, ciclo con fechas, ofertas y carro quedan al alcance del backend.
2. ¿`mis-cuentas` con qué `state` muestra solo lo pendiente? (Se vio el parámetro, no sus valores posibles.)
3. ¿Se quiere registrar **deudas de clientes** (fiado) en la app? Habilita "recordatorio de cobro" (§4.2).
4. ¿El Asistente reemplaza a las hojas actuales, o conviven como atajos dentro de cada pantalla?
