# Diseño — Armar y enviar un pedido a Natura (producto a producto)

> **Estado:** propuesta, **no probada**. Se dedujo de lo que el backend (`mynatura`, módulo `natura-integration`) ya **lee** de Natura y del flujo que describió la consultora.
> Los endpoints y DTOs de compra se completarán con una captura real (§4): un pedido armado en la web y **cancelado antes de cerrarlo**.
> Enviar un pedido gasta **dinero real**. Ninguna prueba automática confirma pedidos.

Documento relacionado: `ios-app-design.md` (§5 reglas de dominio, §8 endpoints, §9 cambios en el backend).

---

## 1. Flujo habitual de la consultora (hoy, a mano)

1. **Ofrece la revista del ciclo vigente** a sus clientes, en papel o con el link de la revista digital.
2. **El cliente elige** productos de la revista.
3. La consultora entra a `minegocio.natura.cl`, **abre un pedido nuevo** y va **digitando los códigos** de lo que eligió cada cliente, con su cantidad.
4. **Agrega productos para ella** (reposición, ofertas que le convienen). Natura muestra **ofertas** que conviene ver rápido.
5. **Al final es obligatorio elegir regalos y productos gratis** que el pedido habilita.
6. **Tope de puntos:** cada producto suma puntos y el total no puede pasar el **máximo permitido por el nivel** de la consultora. Si se pasa, Natura **no deja cerrar** el pedido.
7. Cierra (confirma) el pedido.

Lo que MyNatura puede aportar en cada paso:

| Paso | Hoy | Con MyNatura |
|---|---|---|
| 1 | Revista en papel o link | **Revista del ciclo en la app** + **catálogo digital** para compartir por WhatsApp (§6) |
| 2 | El cliente dicta o escribe códigos | Se registra como **pedido de cliente** del ciclo (ya existe), eligiendo desde la revista |
| 3 | Digitar código por código | **Borrador** armado solo desde los pedidos de clientes; se envía al carro **producto a producto** (§5.4) |
| 4 | Buscar ofertas en la web | **Ofertas del ciclo** en la app, para agregarlas con un toque (§5.6) |
| 5 | Elegir regalos en la web | Pantalla **Regalos** con las opciones que devuelve Natura (§5.7) |
| 6 | Se entera al intentar cerrar | **Barra de puntos en vivo** contra el tope del nivel; bloquea antes de llegar a Natura (§5.5) |
| 7 | Botón en la web | **Enviar** con doble confirmación y verificación (§5.8) |

---

## 2. Lo que ya sabemos (hechos de las lecturas actuales)

### 2.1 Sesión
- El login por HTTP (`natura-http-auth.ts`) llega a una sesión de minegocio:
  - lee la configuración pública del bundle de login (`VITE_APP_API_DOMAIN`, `VITE_APP_API_TOKEN`), en vivo y sin versionar;
  - hace `POST {apiDomain}/signin` con la contraseña cifrada como `CryptoJS.AES.encrypt(password, username)`;
  - sigue `natura-callback` hasta la cookie **`wcmn_session`**.
- Si Akamai bloquea, se usa Playwright como respaldo. Si Natura rechaza las credenciales, no se reintenta.
- La sesión dura 15 min (`NATURA_IMPORT_SESSION_TTL_MINUTES`) y las credenciales **no se guardan**.
- La misma sesión que hoy sirve para *leer* pedidos debería servir para *crearlos* (falta confirmar si hay token CSRF).

### 2.2 Cómo habla minegocio
- Web server-rendered con XHR bajo `/pedidos/ajax/...`. Se llama con `x-requested-with: XMLHttpRequest`, `referer: https://minegocio.natura.cl/pedidos` y user-agent de escritorio.
- `GET /pedidos/ajax/orders/{codigoConsultora}/{isOrderGroup}?page=&pageSize=&orderId=` devuelve JSON con `id`, `orderNumber`, `cycle`, `subCycle`, `orderingDate`, `deliveryDate`, `totalValue`, `itemsQuantity` y `status { id, name }`.
  - Trae **todos los estados** (hoy filtramos "Entregado"), así que sirve para verificar un pedido recién enviado.
- `GET /pedidos/items/{id}/{orderNumber}?from=pedidos` devuelve HTML (`<tbody id="order-items-list">`) con, por línea: `Código`, `Puntos` (por unidad), nombre, `Cantidad`, `Tipo` (p. ej. `Regalo`), `Valor unitario`, `Total Puntos` y `Total Neto`.
  - **Un pedido es una lista de código + cantidad.** Natura calcula precio y puntos. Los regalos aparecen como líneas de otro `Tipo`.
  - El historial de `natura_order_lines` ya tiene **puntos por unidad** de todo lo comprado antes: sirve para estimar puntos sin conexión.

### 2.3 Revista del ciclo
- URL: `https://cl.natura.digital-catalogue.com/consultoria/cl/{AAAA}/{CC}/revista/ciclo-{CC}/view/index.html?id_consultora=…`.
- `INIT_DATA` trae la lista de páginas, y `common/data/{NNNN}.json` trae por página los párrafos (`text`, `x`, `y`).
- Hoy extraemos los **SKU entre paréntesis (5–7 dígitos)** y el **precio sugerido de venta**. Además tenemos **página** y **posición** de cada SKU, lo que permite ubicarlo en la revista.
- Es el **índice de productos del ciclo vigente**, sin tocar minegocio.

**Confirmado en una revisión pública (2026-11-26)**, sin código de consultora:
- Natura publica pocas revistas a la vez: estaban en línea **2026/17, 2026/18, 2026/19 y 2027/01**. Las anteriores responden 404; la próxima se publica antes de empezar su ciclo.
- `INIT_DATA.config.template` trae `cycle`, `year` y `name`, y `pages` trae `pagesNumber`, tamaño (1080×1600) y la lista de páginas.
  - **No trae fechas de vigencia.** No se puede saber cuál es el ciclo *vigente* solo con la revista.
- Recursos públicos por página, bajo `…/view/common/data/`:
  - `NNNN.webp` (imagen, ~160 KB)
  - `NNNN.pdf` (PDF de la página)
  - `NNNN.json` (textos con posición, lo que usamos hoy)
  - `cover.jpg` (portada)
  - **`catalogue.pdf`** (revista completa, ~46 MB)
- El visor trae **búsqueda, listados de productos (PLP), "en oferta" (`plp_on_sale`), stock por consultora y un checkout por WhatsApp hacia la consultora** (`/checkouts/whatsapp/`, `/api/consultoria/orders/`).
  - Usa un API estructurado: `api.smg.natura.digital-catalogue.com/search/consultoria/products/{mrkt}/?campaign_id=&brochure_id=&agent={id_consultora}`, `…/api/stocks/{id_consultora}/`, `smg…/api/v2/products/{feed_id}/plp` e imágenes en `media.smg.natura.digital-catalogue.com/{mrkt}/{campaignId}/`.
  - Los valores de `campaign_id`, `brochure_id` y `feed_id` **no** son el `AAAACC` ni el `uid` de la revista (se probó). Salen de los scripts del visor y se obtienen con la captura (§4.2).
- **Ciclo vigente:** lo muestra el **home de minegocio** (`https://minegocio.natura.cl/`, con sesión) en una tarjeta: **"Ciclo Actual: 19 · 26/11 a 09/12"** (observado el 2026-11-26).
  - Trae número de ciclo y **fechas de inicio y fin**. El año no aparece; se deduce de las fechas (un ciclo que cruza de año toma el año de la fecha de inicio, a confirmar con el ciclo 01).
  - Ese ciclo coincide con la revista `{AAAA}/{CC}`: 19 → `2026/19`, ya publicada.
  - **Fuente en el HTML** (captura del 2026-11-26): el home trae `var query_cycle = [202619]` (AAAACC). El backend puede leerlo con la sesión de minegocio que ya obtiene, sin GSP. Las fechas no están ahí: vienen de GSP (`unified-assistant-proposal.md` §6.3).
  - La tarjeta tiene un ícono ⓘ con más información (¿hora de cierre?).
  - Falta saber si el dato viene en el **HTML** del home (se parsea como hoy `#order-items-list`) o en un **XHR** (JSON). Ver paso 0 de §4.2.
  - Uso: el backend lo lee en cada login (import o pedido) y lo guarda como `current_cycle` (`AAAACC`, inicio, fin, `fetched_at`) por consultora. La app lo muestra, elige sola la revista y el borrador del ciclo, y avisa cuando quedan pocos días para el fin.
  - Sin sesión reciente: se usa el último guardado si `fin` no pasó. Si pasó, se toma el siguiente publicado y se marca "por confirmar".
- **Implicancia para §6:** si el API de productos responde, la revista en la app puede ser un **catálogo estructurado** (foto, nombre, código, precio, oferta, stock) en vez de solo páginas. Además, el checkout por WhatsApp de Natura ya resuelve "el cliente elige y le avisa a la consultora".

### 2.4 Datos propios
- `customer_orders` por ciclo (`AAAACC`) con líneas `sellerProductId → naturaSku`, cantidad y estado.
- `seller_products`, stock por lotes e historial de compras.

---

## 3. Hipótesis del flujo de compra en minegocio

**No observado**; se confirma con la captura de §4.

1. *Pedido nuevo* crea o abre un **pedido en curso** del lado Natura, ligado a la consultora y al ciclo o subciclo abierto. Tendría un id de pedido o carro y quizás un token CSRF.
2. *Agregar producto* es un XHR con **código + cantidad**. La respuesta trae la línea, o el carro, con precio y **puntos**, o un error: código inválido, sin stock, sustituido, cantidad máxima.
3. El pedido en curso expone **totales**: monto, **puntos acumulados** y **tope de puntos del nivel**.
4. Existe un listado de **ofertas** del ciclo (promociones, kits, "compra X lleva Y").
5. Antes de cerrar hay un paso de **regalos / productos gratis** con opciones según lo que se compró. La selección es obligatoria.
6. *Cerrar* valida el tope de puntos, los regalos elegidos y otras reglas (mínimo, crédito, cierre del ciclo), y devuelve el número de pedido.
7. *Cancelar* o *abandonar* descarta el pedido en curso.

---

## 4. Captura de endpoints (sesión manual en la web)

Objetivo: obtener URLs, métodos, cuerpos y respuestas de cada paso **sin cerrar el pedido**.

### 4.1 Cómo capturar
**Opción A, Chrome DevTools** (lo más simple):
1. Abrir DevTools (F12) → pestaña **Network**. Marcar **Preserve log** y **Disable cache**. Filtro **Fetch/XHR**, pero revisar también *Doc* en las navegaciones.
2. Hacer el recorrido de §4.2.
3. Clic derecho en la lista → **Save all as HAR (sanitized)**. Esta opción omite cookies y `authorization`.
4. Guardar el HAR **fuera del repo**. Aunque esté sanitizado, trae datos personales: nombre, código de consultora, dirección, pedidos.

**Opción B, script del backend:** un `inspect-natura-order-flow.ts` basado en `captureNaturaSessionFromManualLogin`. Abre Chromium visible, la persona navega a mano y el script graba método, URL, status, nombres de campos (JSON y `form-urlencoded`) y forma de las respuestas, redactando valores. El resultado va a `backend/tmp/` (no versionado).

De la captura solo se pasan a este documento **formas** (rutas con placeholders, nombres de campos, tipos), nunca valores reales.

### 4.2 Recorrido a capturar (en orden)

| # | Acción en la web | Qué buscamos |
|---|---|---|
| 0 | En el **home**, con DevTools abierto, recargar y buscar "Ciclo Actual" (Ctrl+F en el panel Network busca en las respuestas). Abrir el ⓘ | Si el ciclo y sus fechas vienen en el HTML del home o en un XHR; qué agrega el ⓘ |
| 1 | Entrar a pedidos → **Pedido nuevo** | Request que crea o abre el pedido; id de pedido/carro; token CSRF; ciclo y subciclo |
| 2 | Agregar **un código válido**, cantidad 1 | Endpoint *agregar*: método, cuerpo, respuesta (precio, puntos, totales) |
| 3 | Agregar **el mismo código** otra vez | ¿Suma cantidad o reemplaza? ¿Crea otra línea? |
| 4 | **Cambiar cantidad** de una línea | Endpoint *modificar* |
| 5 | **Eliminar** una línea | Endpoint *eliminar* |
| 6 | Agregar un **código inválido** | Formato del error |
| 7 | Agregar un producto **agotado** o sustituido (si aparece alguno) | Formato del error o de la sustitución |
| 8 | Ver el **indicador de puntos** | De dónde salen *puntos actuales* y *tope del nivel* (¿en la misma respuesta del carro? ¿otro endpoint?) |
| 9 | Agregar cantidad hasta **pasar el tope** de puntos | ¿Lo bloquea al agregar o recién al cerrar? Mensaje |
| 10 | Abrir **ofertas** / promociones | Endpoint del listado: código, nombre, precio, puntos, condiciones, vigencia |
| 11 | Agregar **una oferta / kit** | ¿Se agrega por código igual que un producto? |
| 12 | Avanzar al paso de **regalos / gratis** | Endpoint de opciones (grupos, cuántos elegir, condiciones) y de selección |
| 13 | Elegir regalos | Cuerpo de la selección |
| 14 | Llegar a la pantalla **previa a cerrar** y ver el resumen | Totales finales, validaciones; **identificar el request de cerrar sin ejecutarlo** (botón, `action` del form o handler JS) |
| 15 | **Cancelar** el pedido | Endpoint de cancelar o descartar |
| 16 | Volver a la lista de pedidos | ¿El pedido cancelado aparece? ¿Con qué `status`? |
| 17 | Desde minegocio, abrir **la revista del ciclo** (el link que Natura da a la consultora) | URL con `id_consultora`; si enlaza directo a `{AAAA}/{CC}` |
| 18 | En la revista: **buscar** un producto, abrir uno, ver **"en oferta"** | Valores de `campaign_id`, `brochure_id` y `feed_id`; forma de la respuesta del API de productos (código, precio, puntos?, oferta, imagen) |
| 19 | En la revista: agregar 2 productos al **carrito** y abrir "enviar por WhatsApp" **sin enviar** | Cómo arma el mensaje o link; si `/api/consultoria/orders/` registra algo que la consultora pueda leer después |

El request de **cerrar** no se ejecuta. Se deduce del botón o formulario (paso 14) y se valida más adelante en un pedido real autorizado (§9, etapa 5).

---

## 5. Diseño propuesto

### 5.1 Modelo (backend, `natura-integration`)

```
natura_magazine_items                      -- revista del ciclo, indexada (§6)
  seller_id, cycle (AAAACC), natura_sku, name?, suggested_price_cents?,
  page_number, page_x, page_y, is_offer, offer_label?, fetched_at
  UNIQUE (seller_id, cycle, natura_sku)

natura_order_drafts
  id, seller_id, cycle, sub_cycle?, status, note,
  points_limit?, points_total?, net_total_cents?,
  external_cart_id?, external_order_id?, external_order_number?,
  last_cart_snapshot (jsonb), last_error?,
  created_at, updated_at, synced_at?, submitted_at?
  status: draft → syncing → cart_ready → gifts_pending → ready_to_submit
          → submitting → submitted | cancelled | failed

natura_order_draft_lines
  id, draft_id, natura_sku, seller_product_id?, quantity,
  source: customer_orders | offer | restock | manual,
  estimated_points_per_unit?, estimated_unit_price_cents?,
  result: pending | accepted | adjusted | substituted | out_of_stock | invalid_code | rejected,
  accepted_quantity?, substitute_sku?, unit_price_cents?, points_per_unit?, message?
  UNIQUE (draft_id, natura_sku)

natura_order_draft_gifts
  id, draft_id, group_key, option_code, quantity, label
```

Todas las tablas con RLS por `seller_id`.

### 5.2 Cliente Natura (`natura-order-client.ts`, se completa con §4)

| Operación | Paso §4.2 | Uso |
|---|---|---|
| `openOrder(cycle)` | 1 | Abrir o crear el pedido en curso; id y token |
| `readOrder()` | 2, 8 | Líneas, totales, **puntos y tope** |
| `addLine(sku, qty)` / `setQuantity` / `removeLine` | 2–5 | Producto a producto |
| `listOffers(cycle)` | 10 | Ofertas del ciclo |
| `listGiftOptions()` / `selectGifts(sel)` | 12–13 | Regalos obligatorios |
| `cancelOrder()` | 15 | Descartar |
| `submitOrder()` | 14 | **Cerrar** (dinero real) |

- Headers como en `buildNaturaHeaders`; manejo de Akamai como en `throwIfBlocked`.
- Si una llamada XHR no es reproducible, el respaldo es Playwright (clics en la pantalla real).

### 5.3 Armado del borrador (en MyNatura, sin conexión)

Para el ciclo C:

```
encargos(sku)  = Σ cantidad en customer_orders del ciclo C con status confirmed
                 (los draft se muestran aparte y no suman por defecto)
stock_libre(sku) = stock actual − unidades comprometidas en pedidos de cliente pendientes
sugerido(sku)  = max(0, encargos(sku) − stock_libre(sku))
```

- La línea muestra **quién la encargó** ("María ×2, Juan ×1").
- Se agregan líneas de **reposición** u **ofertas** (§5.6), o por código / escáner / búsqueda en la revista.
- Un código que no está en el catálogo restringido pero sí en la revista del ciclo **se permite**. El producto se crea al importarlo entregado, igual que hoy.

### 5.4 Envío al carro de Natura, producto a producto

`POST /api/natura/order-drafts/:id/sync` (online; credenciales en el body, solo en memoria):

1. Login, `openOrder` y `readOrder`. Las líneas que ya están en el pedido de Natura y no en el borrador **no se tocan**; se muestran como "ya en tu pedido de Natura".
2. Por cada línea, **una a la vez** y con una pausa corta:
   - si Natura ya tiene ese SKU con la cantidad pedida, queda `accepted` sin llamar;
   - si no, se usa `addLine` o `setQuantity` según lo que muestre el paso 3 de §4.2 (para no duplicar si *agregar* suma);
   - se guarda `result`, cantidad aceptada, sustituto, precio y **puntos reales**;
   - si una línea falla, el resto continúa.
3. `readOrder` final: snapshot de totales, **puntos vs tope** y estado de regalos.
4. Es seguro reintentar: comparar contra el pedido antes de cada llamada evita duplicados.

### 5.5 Tope de puntos

- **Sin conexión (estimado):** puntos = Σ cantidad × `estimated_points_per_unit`.
  - Los puntos salen del historial de compras (`natura_order_lines.points_per_unit`) o de la última sincronización.
  - Si un producto no tiene puntos conocidos, se marca "puntos desconocidos" y la estimación se muestra como "≥".
- **Tope:** `points_limit` viene de Natura (paso 8 de §4.2). Se guarda en el borrador y en ajustes, con fecha de lectura. Hasta la primera lectura, la consultora puede ingresarlo a mano.
- **UI:** barra "Puntos: 1.240 / 1.500", que pasa a ámbar al 90 % y a rojo al superar el tope.
  - Si se supera, se bloquean **sincronizar** y **enviar**, con el mensaje "Quita productos: te pasas por N puntos".
  - Se sugiere qué líneas propias (reposición u ofertas) bajar primero, **antes** que los encargos de clientes.
- **Después de sincronizar** manda el valor de Natura. Si difiere de la estimación, se muestra la diferencia y se actualizan los puntos por unidad.

### 5.6 Ofertas del ciclo

- **Fuente principal:** el listado de ofertas de minegocio (paso 10 de §4.2). Se lee **al sincronizar**, porque requiere sesión, y se guarda para el resto del ciclo.
- **Fuente secundaria sin sesión:** las páginas de la revista con señales de oferta (`/oferta|promo|lleva|%|a solo/`) marcan `is_offer` en `natura_magazine_items`.
- **UI:** sección "Ofertas" en el borrador con tarjetas (nombre, precio, puntos, condición) y botón **+**, que agrega una línea con `source = offer`. Muestra cuántos puntos consume cada oferta.

### 5.7 Regalos y productos gratis (obligatorio)

- Tras sincronizar, si Natura informa regalos pendientes, el borrador pasa a `gifts_pending`.
- La pantalla **Regalos** lista los grupos que devuelve `listGiftOptions()`, por ejemplo "Elige 1 de 3", cada uno con su condición.
- La consultora elige, se envía `selectGifts` y el estado pasa a `ready_to_submit`.
- Si cambian las líneas después, los regalos **se vuelven a validar**, porque pueden depender del total.
- Se recuerda la elección por ciclo como sugerencia la próxima vez.

### 5.8 Cerrar (enviar)

`POST /api/natura/order-drafts/:id/submit`:

- Solo desde `ready_to_submit` y con un `confirmationToken`: un hash de líneas, regalos, total y puntos, que entrega el último `sync` y vence en pocos minutos.
- `readOrder` justo antes. Si difiere del snapshot, o los puntos superan el tope, se aborta.
- **Nunca se reintenta solo.** Ante un timeout, el estado queda `submitting` y se **verifica** en `/pedidos/ajax/orders` del ciclo, sin reenviar.
- Si se confirma, se guarda `orderNumber`. Cuando Natura lo entregue, el **import actual** lo trae y se enlaza por `external_order_id`.
- Salvaguardas en el backend:
  - `NATURA_ORDER_SUBMIT_ENABLED=false` por defecto;
  - **modo simulación** (todo menos cerrar);
  - tope de monto opcional `NATURA_ORDER_MAX_TOTAL_CLP`.
- **Cancelar:** `POST /api/natura/order-drafts/:id/cancel` usa `cancelOrder()` en Natura y deja el borrador `cancelled`. Se puede duplicar después.

### 5.9 Endpoints MyNatura

| Método | Ruta | Notas |
|---|---|---|
| `GET` | `/api/natura/magazine?cycle=` | Ítems indexados de la revista del ciclo (§6) |
| `GET` | `/api/natura/offers?cycle=` | Ofertas guardadas del ciclo |
| `GET` | `/api/natura/order-drafts?cycle=` | Borrador del ciclo |
| `POST` | `/api/natura/order-drafts` | Crea desde la sugerencia (§5.3) o vacío |
| `PUT` | `/api/natura/order-drafts/:id/lines` | Reemplaza las líneas (`Idempotency-Key`) |
| `POST` | `/api/natura/order-drafts/:id/sync` | Online, con credenciales; resultado por línea, puntos, ofertas, regalos y `confirmationToken` |
| `PUT` | `/api/natura/order-drafts/:id/gifts` | Online, con credenciales; selección de regalos |
| `POST` | `/api/natura/order-drafts/:id/submit` | Online, con credenciales + token |
| `POST` | `/api/natura/order-drafts/:id/cancel` | Online, con credenciales |

Las operaciones online largas responden `202 + runId` con polling, igual que lo propuesto para el import (§9.5 del diseño iOS).

---

## 6. Revista y catálogo digital para clientes

### 6.1 Revista en la app
- El backend indexa la revista del ciclo vigente en `natura_magazine_items` y guarda las **imágenes de página** si la revista las publica junto a `common/data/{NNNN}.json` (confirmar la ruta exacta).
- La app la muestra en **Clientes → Revista**:
  - visor por páginas;
  - búsqueda por nombre o código;
  - al tocar un producto, "Agregar a pedido de cliente…".
- Funciona **sin conexión** una vez descargada (imágenes en caché; los ítems en SwiftData, entidad `MagazineItem`).

### 6.2 Catálogo para compartir (WhatsApp)
Hay dos niveles, de menor a mayor esfuerzo:

1. **Compartir la revista oficial:** `ShareLink` con la URL de la revista del ciclo. Ya incluye el `id_consultora` y es lo que Natura espera que se comparta. Costo casi cero.
2. **Mi selección del ciclo:** la consultora marca productos (todos los del ciclo o una selección, p. ej. ofertas y lo más vendido) y la app genera un **PDF o imagen** con foto, nombre, **código**, precio de venta (el suyo o el sugerido) y una línea final "Responde con los códigos que quieres".
   - Se comparte con `ShareLink` / `UIActivityViewController` (WhatsApp, etc.).
   - Sin servidor público ni extensiones (compatible con Apple ID gratis).
   - Solo productos de la **revista actual**, nunca el catálogo completo.

Opción futura (no en esta etapa): una página web pública por ciclo, de solo lectura y con link de token, donde el cliente marque productos y se cree solo un `customer_order` en borrador. Exige exponer una ruta pública del backend y moderar abuso.

### 6.3 Del cliente al pedido
- La respuesta del cliente (códigos) se carga en **Pedido de cliente** con el autocompletado por código contra la revista del ciclo.
- Así el borrador del pedido Natura (§5.3) se arma solo a partir de los encargos confirmados.

---

## 7. App iOS — pantallas nuevas

| Pantalla | Conexión | Contenido |
|---|---|---|
| Clientes → **Revista** | Offline tras descargar | Visor, búsqueda, agregar a pedido de cliente, **Compartir** (§6.2) |
| Pedidos Natura → **Armar pedido del ciclo** | Offline | Secciones *Encargos*, *Ofertas*, *Reposición*; stepper por línea; **barra de puntos**; total estimado |
| **Revisar en Natura** | Online | Credenciales en `SecureField` (no se guardan); progreso "k / N"; badge por línea; puntos reales vs tope |
| **Regalos** | Online | Grupos "Elige N de M"; obligatorio para continuar |
| **Enviar** | Online | Resumen (líneas, regalos, total, puntos), diálogo destructivo; nunca se encola offline; "Verificar" si quedó en `submitting` |

- Mutaciones offline nuevas: `natura.order-draft.create` y `natura.order-draft.lines.put`.
- `sync`, `gifts`, `submit` y `cancel` son acciones online directas, **fuera de la cola**.

---

## 8. Riesgos

| Riesgo | Mitigación |
|---|---|
| Pedido duplicado o no deseado (dinero real) | Token de confirmación, `readOrder` previo, sin reintento automático, verificación por lista, interruptor y simulación |
| Superar el tope de puntos | Estimación offline + bloqueo; Natura valida igual al cerrar |
| Regalos mal elegidos o que quedan inválidos | Se revalidan tras cada cambio de líneas; el estado no avanza sin selección |
| Natura cambia URLs o HTML | Aislado en `natura-order-client.ts`; errores por línea; el borrador nunca se pierde |
| Akamai / automatización | Una línea a la vez con pausa; headers de navegador; respaldo Playwright |
| Bloqueo de cuenta | No reintentar credenciales rechazadas |
| HAR con datos personales | Se guarda fuera del repo; al documento solo pasan formas, no valores |
| Términos de uso de Natura | Lo hace la consultora sobre su cuenta, a su pedido; revisar antes de habilitar el envío |

---

## 9. Plan por etapas

| # | Etapa | Entregable | Toca Natura |
|---|---|---|---|
| 0 | Captura | HAR o script de §4; tabla §5.2 con rutas y DTOs reales (en este documento, sin valores) | Pedido manual **cancelado** |
| 1 | Revista y catálogo | `natura_magazine_items`, visor en iOS, compartir link oficial y PDF de selección | Solo revista pública |
| 2 | Borrador local | Tablas y endpoints de borrador; sugerencia desde encargos; ofertas de la revista; barra de puntos estimada | No |
| 3 | Sync producto a producto | `openOrder / addLine / readOrder / removeLine / cancelOrder`; puntos y tope reales; ofertas de minegocio; todo en **simulación** | Pedido en curso, se **cancela** |
| 4 | Regalos | `listGiftOptions / selectGifts` y pantalla Regalos | Pedido en curso, se **cancela** |
| 5 | Cerrar | `submitOrder` con token y verificación; interruptor apagado por defecto; primera vez con un pedido real autorizado | **Sí** |
| 6 | Cierre de ciclo | Enlace borrador ↔ pedido importado al entregarse; comparar pedido vs recibido vs encargos | Solo lectura |

---

## 10. Preguntas abiertas (se responden con la captura)

1. Rutas, métodos y formato (JSON o form) de abrir, agregar, modificar, eliminar, cancelar y cerrar.
2. ¿*Agregar* suma o fija la cantidad?
3. ¿Token CSRF o id de carro? ¿Dónde se obtiene?
4. ¿De dónde salen los puntos actuales y el **tope del nivel**? ¿Se bloquea al agregar o al cerrar?
5. Estructura de **ofertas** y si se agregan por código.
6. Estructura de **regalos**: grupos, cantidad a elegir, condiciones, si dependen del total.
7. ¿Qué son `isOrderGroup` y `subCycle`? ¿Afectan al pedido nuevo?
8. ¿Qué `status` tiene un pedido en curso, cancelado o recién cerrado en `/pedidos/ajax/orders`?
9. ~~¿La revista publica imágenes de página?~~ Sí: `common/data/NNNN.webp`, `NNNN.pdf` y `catalogue.pdf` (§2.3). Pendiente: ids del API de productos y si trae puntos.
10. Ciclo vigente y fechas: **sí**, en el home ("Ciclo Actual: 19 · 26/11 a 09/12"). Pendiente: si viene en HTML o XHR, la hora exacta de cierre (¿en el ⓘ?) y el año en ciclos que cruzan de año.
