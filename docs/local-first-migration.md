# Plan — App iOS local primero, sin backend propio

> **Estado:** decisión tomada (2026-11-26). **M1, M2, M3, M5 y M6 implementadas** (sin probar en iPhone); **M4 descartada** (el Excel del pedido la reemplaza); M7–M8 pendientes.
> **Decisión:** la app iOS guarda **todos los datos de la consultora en el iPhone** (fuente de verdad, offline first) y habla **directo con Natura** cuando hay conexión. Se deja de usar el backend propio (Fastify + PostgreSQL) y la PWA.
> Al terminar, actualizar `CLAUDE.md` y `ios-app-design.md` (§7 sync y §8 endpoints quedan obsoletos).

---

## 1. Por qué

Respuestas que definen la decisión:

| Pregunta | Respuesta | Consecuencia |
|---|---|---|
| ¿Se usa la PWA o el PC? | No | El backend no tiene otro cliente que lo justifique |
| ¿Otro dispositivo u otra persona? | No | No hace falta sincronizar entre dispositivos |
| ¿Datos reales en el backend? | Solo pedidos y productos importados de Natura; nada ingresado a mano | Se **vuelven a importar desde Natura** en la app; no hay nada que rescatar (§7) |

Además:
- **Natura se alcanza por HTTP simple**, sin navegador: minegocio y GSP se verificaron el 2026-11-26 (`unified-assistant-proposal.md` §6.2).
- Las reglas de negocio ya están en `Core`.
- El backend hoy corre en un PC, sin acceso desde internet. Publicarlo implicaría hosting, seguridad y respaldos.

---

## 2. Necesidades y dónde viven

| Necesidad | Dato | Dónde vive | Red |
|---|---|---|---|
| Llevar mi stock | Lotes, movimientos, conciliaciones | iPhone (SwiftData) | No |
| Mis precios | **Costo real** por lote (de la línea del pedido entregado); **precio de venta** mío; precio del ciclo según ofertas y nivel (GSP) | Costo y venta: iPhone. Ofertas y precio del ciclo: caché de Natura | Solo para refrescar Natura |
| Mis ganancias | Venta − costo de los lotes consumidos (FIFO/LIFO) | Calculado en `Core` | No |
| Clientes y sus pedidos | Clientes, pedidos por ciclo | iPhone | No |
| Pedidos Natura, ciclo, cuenta, ofertas, carro | De Natura | Caché en el iPhone con fecha de lectura | Sí, bajo demanda |

**Online u offline first:** offline first para todo lo propio; online bajo demanda para lo de Natura. Las acciones que necesitan Natura muestran "requiere conexión".

---

## 3. Arquitectura objetivo

```
App iOS
  Features (SwiftUI)  — mismas pantallas; sin pastilla de sync con el backend
  Persistence (SwiftData) — fuente de verdad: productos, lotes, movimientos, ventas, clientes, pedidos, caché Natura
  Natura (paquete nuevo, reemplaza APIClient)
      NaturaAuth       signin (Cognito API) → sso_token → minegocio (wcmn_session) / GSP (recover-session → xAppToken)
      MinegocioClient  pedidos (JSON) + líneas (HTML) · mis-cuentas · home (query_cycle)
      GspClient        consultantSection (ciclo) · authCommercialInfo (crédito) · cardSection (ofertas) · carro (futuro)
      MagazineClient   revista pública (páginas, índice de precios sugeridos)
  Core (Foundation)   reglas: lotes y costo, ganancia, precios, recepción, voz, foto… (tests en Linux)
  Backup              exportar / importar respaldo JSON
```

- **Se elimina:**
  - `SyncEngine` (cola de mutaciones, push/pull, idempotencia, reasignación de IDs);
  - `APIClient` hacia el backend y el login a la app (`SessionStore` con el backend);
  - el repo `mynatura` queda **archivado** como referencia.
- **Se mantiene:** `Core`, `Persistence`, `DesignSystem` y las pantallas. Las acciones de `SyncEngine` (vender, recibir, conciliar…) pasan a un `Store` local que escribe directo en SwiftData, sin encolar.
- **Credenciales de Natura: en el Keychain, protegidas con Touch ID** (decisión del 2026-11-26).
  - Se guardan con `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` y `SecAccessControl(.biometryCurrentSet)` (con código del iPhone como alternativa): no van al respaldo de iCloud ni a otro equipo.
  - Se usan solo al llamar a Natura, y siempre se pueden borrar desde Ajustes.
  - **Reemplaza la regla "Credenciales de Natura nunca se persisten"** de `CLAUDE.md` y `ios-app-design.md`; se actualizan en M7.
  - El Keychain del iPhone funciona con Apple ID gratis, sin entitlements.

---

## 4. Costo, ganancia, regalos de Natura y obsequios a terceros

### 4.1 Lo que hace hoy el backend (y hay que corregir)

En la importación (`import-delivered-orders.ts`):
1. Una línea **gratis de Natura** (precio "-") crea el lote con **costo `null`**. Al vender ese producto, `create-sale.ts` falla con *"No fue posible determinar el costo del lote"*.
2. El producto guarda `lastPurchaseUnitPriceCents = purchase ?? 0`: una unidad gratis **pisa con 0 el último costo** de un producto que antes se compró.
3. Las líneas gratis (muestras, bolsas, otra copia de revista) quedan **vendibles** por defecto, aunque en la práctica no se venden.
4. El costeo solo admite FIFO y LIFO.

### 4.2 Dos cosas distintas que se llaman "regalo"

| Concepto | Qué es | Precio de venta | Costo | Efecto en la ganancia |
|---|---|---|---|---|
| **Gratis de Natura** | Llega en el pedido a costo 0: muestras, bolsas, otra copia de la revista, regalos por promoción | — (no se vende; el precio de venta **nunca** es 0) | 0 en el lote; ver §4.4 al consumirlo | Ninguno al recibirlo |
| **Obsequio a terceros** | Algo que la consultora regala a un cliente o a otra persona | **0** (por eso no es venta) | El de los lotes consumidos, según el método de costeo | **Pérdida** igual a su costo |

### 4.3 Reglas de entrada (recepción e import)

- **Se clasifica por el valor unitario, no por el `Tipo`:**
  - **valor > 0:** lote `purchased`, con costo = valor pagado;
  - **valor 0 o "-":** lote `free`, con costo 0 conocido.
  
  Una **muestra** puede llegar gratis o comprarse: se rige por esta misma regla.
- **Producto nuevo creado por el import:** si su primera línea es `free`, queda **no vendible** por defecto (se puede regalar, no vender). Si es `purchased`, queda vendible. La consultora puede cambiarlo en la ficha.
- **Material que no se controla** (revista, catálogo, bolsas): queda en el pedido para que la recepción cuadre. Entra al stock solo si la consultora lo quiere llevar; por defecto se controla, como no vendible, para poder registrar su entrega.
- **El último costo de compra** del producto se actualiza **solo con lotes `purchased`** (o `manual`). Una unidad gratis nunca lo pisa.
- **Costo desconocido ≠ costo cero.** `costSource` ∈ `purchased` · `free` · `manual` · `unknown`. `unknown` es una línea pagada cuyo valor no se pudo leer; se completa a mano.

### 4.4 Método de costeo y costo de lo que sale

- **Método** (ajuste global, como hoy, con un caso nuevo): **FIFO** (el lote más antiguo), **LIFO** (el más reciente) o **Mayor precio** (el lote de mayor costo).
- **Orden de consumo:** el método decide qué lotes se consumen. Los lotes `free` participan como cualquier otro: son unidades reales del stock. Con "Mayor precio" quedan naturalmente al final.
- **Si una unidad sale de un lote `free` (costo 0), no se usa 0 como costo.** Se usa un **precio conocido según el método**, tomado de los lotes `purchased` y `manual` del producto, **aunque ya estén agotados** (historial de compras):

| Método | Precio conocido que reemplaza al 0 |
|---|---|
| FIFO | El costo de compra **más antiguo** conocido |
| LIFO | El costo de compra **más reciente** conocido |
| Mayor precio | El **mayor** costo de compra conocido |

  La línea queda **marcada** como "costo de referencia: unidad gratis de Natura", y se muestra así en la venta, el obsequio y el reporte.
- **Si el producto nunca se compró** (una bolsa, una muestra que siempre llega gratis), no hay precio conocido: el costo queda en **0 y marcado** "sin costo conocido (gratis de Natura)".
- **Lote `unknown`:** la línea queda con **costo pendiente** y la ganancia se marca **incompleta** (no se asume 0). Al completar el costo del lote, se recalcula.
- El **costo efectivo y su origen** se guardan en cada línea de venta u obsequio al registrarla. El reporte no cambia si después se cambia el método.

### 4.5 Ventas y obsequios

- **Venta:** el precio de venta debe ser **> 0**. No se puede vender a 0.
- **Obsequio a terceros:** se registra con el mismo flujo del carro, eligiendo **"Regalar"** (o con una línea a precio 0 y motivo *Regalo*, que hoy ya existe en `PricingRules`). Se guarda como **documento de obsequio**, no como venta:
  - descuenta stock;
  - consume lotes con el método de costeo (§4.4);
  - no suma ingreso;
  - su costo es **pérdida**.
  
  Puede tener cliente o destinatario y una nota ("muestra para Ana").
- Se pueden regalar productos vendibles y no vendibles. Los gratis de Natura suelen terminar aquí.
- **Mismo cálculo de costo que la venta (§4.4):** el método de costeo decide qué lote sale y, si es un lote gratis, qué precio conocido se usa. Ejemplo con un producto comprado a $3.000 (enero) y $3.500 (marzo), y 1 unidad gratis (febrero) en stock junto a las compradas:
  - **FIFO:** sale primero lo más antiguo. Si la gratis es la más antigua en stock, la pérdida es $3.000 (compra más antigua conocida).
  - **LIFO:** sale primero lo más reciente. Si sale la gratis, la pérdida es $3.500 (compra más reciente conocida).
  - **Mayor precio:** sale primero el lote de $3.500. La gratis sale solo cuando no queda stock comprado, y en ese caso la pérdida es $3.500 (mayor costo conocido).

### 4.6 Reporte de ganancias

```
  Ventas (ingresos)
− Costo de lo vendido            (lotes purchased/manual + costo de referencia de unidades gratis)
= Margen bruto de ventas
− Obsequios a terceros (pérdida) (costo de lo regalado, mismo cálculo)
= Ganancia

  Detalle informativo:
  · unidades vendidas con costo de referencia (gratis de Natura)  ← cuántas y por cuánto
  · obsequios sin costo conocido (gratis de Natura nunca comprados)
  · ventas u obsequios con costo pendiente (lote unknown)          ← ganancia incompleta
```

Por periodo y por producto, como el reporte de margen actual.

### 4.7 Otros precios
- **Precio de venta sugerido:** de la revista del ciclo, como hoy; editable por producto.
- **Precio del ciclo según ofertas y nivel** (GSP `cardSection`: `purchasePrice`, `resalePrice`, `points`, `promotionSummary`): **para planificar** el pedido y comparar. **No** cambia el costo de lo ya comprado: ese sale siempre de la línea del pedido entregado.

### 4.8 Tests mínimos (M1)

- Muestra comprada y después recibida gratis: el último costo no cambia, y la salida usa el costo conocido según el método.
- FIFO, LIFO y Mayor precio con lotes mixtos `purchased` + `free`: qué lote se consume y con qué costo.
- Producto solo gratis (bolsa) regalado: pérdida 0 y marcada "sin costo conocido".
- Venta a precio 0: rechazada como venta y ofrecida como obsequio.
- Obsequio de un producto pagado: pérdida = costo según el método.
- Lote `unknown`: costo pendiente; al completarlo se recalcula.
- Reporte: ventas − costo − obsequios = ganancia, con el detalle informativo.

## 5. Integración directa con Natura (portar del backend)

| Hoy en el backend (TypeScript) | Pasa a (Swift, paquete `Natura`) | Notas |
|---|---|---|
| `natura-http-auth.ts` (signin, CryptoJS AES, callback) | `NaturaAuth` | AES-256-CBC + EVP_BytesToKey(MD5) con CommonCrypto; config leída del bundle en vivo |
| `natura-gsp-auth.ts` (recover-session, xAppToken) | `NaturaAuth` / `GspClient` | Verificado con `natura:probe-gsp-login` |
| `natura-http-client.ts` (pedidos JSON, líneas HTML `#order-items-list`) | `MinegocioClient` | Mismo parseo; tests con HTML de ejemplo **sin datos personales** |
| `natura-magazine-pricing.ts` (precios de la revista) | `MagazineClient` | Mismas heurísticas; tests en `Core` |
| OCR de boleta (Tesseract + sharp) | — | Se descarta (M4): la boleta trae lo mismo que el Excel del pedido, que se baja solo. El código queda en el repo `mynatura` por si se necesita |
| `playwright-natura-client.ts` | — | Se elimina. Si Akamai bloquea, se informa y se reintenta más tarde |
| Nuevo | `MinegocioClient.accounts` (`mis-cuentas`), `query_cycle`; `GspClient.consultantSection`, crédito, ofertas | Del catálogo del Asistente (U5–U6) |

- **Cookies:** `URLSession` con `HTTPCookieStorage` propio y efímero por sesión de import. Nada persiste tras usarse.
- **Akamai:** el iPhone navega con IP residencial o móvil, así que es probable que bloquee menos que un servidor. Ante un bloqueo, mensaje claro y reintento manual.
- **Idempotencia del import:** como hoy, por `(externalOrderId)` y `(línea)`. Reimportar no duplica.

---

## 6. Respaldo (reemplaza al servidor)

- **Exportar respaldo:** un archivo JSON versionado con todo (productos, lotes, movimientos, ventas, clientes, pedidos, ajustes). Se comparte a Archivos, Drive o correo con `ShareLink`. Sin credenciales.
- **Importar respaldo:** reemplaza los datos locales, con confirmación y vista previa de conteos.
- **Recordatorio semanal** en la app ("Último respaldo: hace 9 días").
- **Respaldo de iCloud del iPhone:** incluye los datos de la app aunque el Apple ID de firma sea gratis. Dejarlo activado.
- **Reinstalar con Sideloadly** cada 7 días sobre la misma app (mismo Bundle ID `cl.mynatura.app`) **conserva los datos**.

---

## 7. Migración de datos

El backend solo tiene pedidos y productos importados de Natura, sin nada ingresado a mano. Entonces la migración es:

1. **Reimportar desde Natura en la app** (M3): pedidos entregados, líneas, costos y lotes, ya con las reglas de §4.
2. Comparar conteos (pedidos, líneas, productos) con el backend una vez, y apagarlo.

Sin script de exportación.

**Nota sobre vender la app a otras consultoras** (idea mencionada, no en curso): el modelo local primero **no lo impide**, porque cada usuaria tendría sus datos en su iPhone, sin servidor que mantener. Requeriría cuenta de desarrollador de pago (App Store) y revisar los términos de uso de Natura sobre automatizar su sitio. El backend multiusuario que existía era la otra vía; queda archivado como referencia.

## 7.1 Catálogo, historial y stock inicial (decisiones 2026-11-27)

**Sin backend como fuente:** todo lo que tenía salió de Natura, y la app lo trae directo (M3).

**Catálogo: los pedidos mandan.**
- **No se crean productos a mano.** Se quitan:
  - el "+" de Productos;
  - "Crear producto" en la foto;
  - la creación rápida en el pedido de cliente.
- El catálogo se arma de dos fuentes, **sin repetir** (clave: código Natura):
  1. **Mis pedidos** (todos los entregados, históricos y nuevos): producto, costo pagado y lotes.
  2. **El catálogo del ciclo actual** (GSP `cardSection`): lo que la plataforma muestra este ciclo, con **categoría**, precio de compra y de venta del ciclo, puntos e imagen. Se **trae siempre** al refrescar y se actualiza cada ciclo.
- **Categorías:** vienen del ciclo actual (`cardSection.categories` y el filtro por categoría). Un producto de mis pedidos que no está en el ciclo actual conserva la última categoría conocida, o "Sin categoría".
- **Producto del ciclo que nunca pedí:** está en el catálogo (para buscarlo, ofrecerlo y agregarlo a pedidos de clientes) pero **sin stock**, y no se puede vender hasta que llegue en un pedido.

**Stock inicial: "Agregar inventario actual".**
1. Al importar el historial, cada línea entregada entra como lote **recibido** con su costo pagado. El stock teórico queda en **todo lo comprado**.
2. Opción **"Agregar inventario actual"**: la consultora ingresa (o escanea) cuánto tiene hoy de cada producto.
3. **La diferencia** (comprado − contado) se registra como **ventas previas**: salidas que consumen lotes **con FIFO** (la primera vez, sin importar el método elegido). Así lo que queda en stock son los lotes más recientes, con su costo real.
4. Las ventas previas se valorizan con el **precio sugerido de cada lote** (Excel del pedido, ver abajo) como ingreso **estimado**. Quedan como un documento propio ("Ventas previas al uso de la app"), en un bloque aparte del reporte de Ganancias, y visibles en el kardex.
5. Después de esa primera vez, los conteos son conciliaciones normales (merma según el método).

**Pedidos nuevos** (desde el import siguiente): entran pendientes de recepción, como hoy.

**Fuente de cada línea: el Excel del pedido** (verificado el 2026-11-27, disponible en **todos** los pedidos).
- `GET https://minegocio.natura.cl/pedidos/order-report/{number}` (botón "Descarga información de tu pedido"; `{number}` es el número largo del pedido) devuelve un XLSX.
- **Encabezado:** consultora (nombre y código), pedido, ciclo (`CC/AAAA`) y fecha.
- **Una fila por línea:** `Cant.`, `Código`, `Descriptions`, `Marca`, **`Precio revista (uni.)`** (precio sugerido de venta), `Precio revista (total)`, **`Precio CB (total)`** (costo de la línea), `Ganancia (total)`.
- **Al final:** totales por marca (AVON / C&E, NATURA) y `TOTALES`.
- **Reglas:**
  - costo unitario = `Precio CB (total)` / `Cant.`; precio sugerido = `Precio revista (uni.)`;
  - **excluir `TASA DE SERVICIO`** (código `1`, todo en 0): no es producto y se confundiría con un gratis;
  - las **promociones** traen costo = sugerido (ganancia 0): son compras normales;
  - una línea con costo 0 y sugerido > 0 es **gratis de Natura** con su precio sugerido conocido.
- **Lectura en iOS:** el XLSX es un ZIP con CRC inválidos (`unzip` los marca): un lector mínimo propio que **no valida CRC**, descompresión con el framework `Compression` (deflate) y `XMLParser` para `xl/worksheets/sheet1.xml` (celdas `t="str"`, sin `sharedStrings`). Sin librerías externas.
- **Prioridad de fuentes:**
  1. Excel del pedido (costo + sugerido; también para el historial);
  2. HTML de líneas (`/pedidos/items/…`, lo que usa hoy el backend), como respaldo del costo;
  3. revista del ciclo, solo si sigue en línea.

  El OCR de la boleta impresa se descartó: trae lo mismo que el Excel (ver M4).
- **Ventas previas** ("Agregar inventario actual"): cada lote guarda el sugerido de su línea, y las unidades que salen con FIFO toman **ese** precio como **ingreso estimado**. Se muestran en un bloque aparte de Ganancias ("Ventas previas, estimadas al precio sugerido"), sin mezclarse con las ventas reales.
- Los archivos descargados para análisis van en `docs/xlsx/` (en `.gitignore`: traen datos personales).

**Consecuencia para M2:** el "saldo inicial" que convertía en lotes el stock bajado del backend queda **desactivado** y se reemplaza por esto en M3.

## 8. Etapas

Cada etapa deja la app usable. Mientras dure la transición, el backend sigue funcionando hasta M7.

| # | Etapa | Entregable |
|---|---|---|
| M1 ✅ | Reglas de costo | `Core`: lotes con `costSource` (clasificación por valor), FIFO/LIFO/**Mayor precio**, costo de referencia para unidades gratis, costo pendiente, obsequios a terceros como pérdida, reporte de ganancias (§4.6); tests de §4.8 |
| M2 ✅ | Store local | Acciones (vender, recibir, conciliar, EAN, clientes, pedidos, foto, voz) escriben directo en SwiftData con lotes y costos locales; `SyncEngine` en modo solo lectura (todavía puede bajar datos) |
| M3 ✅ | Natura directo | Paquete `Natura`: login (minegocio + GSP) + import de **todos** los pedidos entregados (JSON + HTML) como lotes recibidos + catálogo del ciclo actual (`cardSection`, categorías) sin repetir + revista; "Agregar inventario actual" (diferencia = ventas previas, FIFO); sin productos manuales; sin leer el backend |
| M4 ✖ | OCR local | **Descartada** (2026-11-27): la boleta trae lo mismo que el Excel del pedido, que la app baja sola al importar. Ver §8.3 |
| M5 ✅ | Respaldo y credenciales | Exportar / importar JSON con recordatorio; contraseña de Natura en el Keychain con Touch ID |
| M6 ✅ | Cuenta, ciclo, ofertas | `MinegocioClient.accounts`, `query_cycle`, `GspClient` (ciclo con fechas, crédito, ofertas): etapas U5–U6 del Asistente sin backend |
| M7 | Retiro | Se quitan `SyncEngine`, `APIClient` al backend, login a la app y pastilla de sync; se archiva el repo `mynatura`; se actualizan `CLAUDE.md` y `ios-app-design.md` |
| M8 | Pedido Natura (después) | `natura-order-placement.md` con el flujo GSP, directo desde la app |

---

## 8.1 Implementación M2

- **Lotes en SwiftData** (`InventoryLotRecord`: cantidad, saldo, costo, `CostSource`, origen y línea Natura). **El stock = suma de los saldos** (`StockItem` se recalcula desde los lotes).
- **Paso a modo local (una vez, automático):** cuando el stock ya se bajó bien del backend, cada producto con stock queda con un **lote de saldo inicial** (costo = último costo de compra; si es 0, gratis).
  - Las mutaciones pendientes se descartan, porque su efecto ya está en el stock local.
  - Se marca `SellerSettings.localInventoryAdoptedAt`.
  - Si el primer pull falla, no se adopta (evita un inventario vacío).
- **Acciones locales**, sin cola ni envío:
  - **venta:** consume lotes según el método y guarda las asignaciones y el costo por línea;
  - **líneas a precio 0** (motivo Regalo): **obsequio** aparte (`LocalSale.kind = .gift`), permitido también para productos no vendibles;
  - **conciliación:** si sobra, lote nuevo al último costo (o pendiente); si falta, merma según el método;
  - **recepción:** lote por línea Natura, clasificado por valor (sin valor o 0 ⇒ gratis); al bajar la cantidad se descuenta primero de ese lote;
  - **EAN, producto rápido, clientes, pedidos de clientes:** locales;
  - **cerrar/reabrir recepción:** local, sin conexión;
  - **método de costeo:** local (FIFO, LIFO, Mayor precio).
- **Pull en modo local:** solo productos nuevos (sumando EAN, sin pisar precios ni "vendible"), motivos de precio y pedidos Natura (sin pisar recepción, cierre ni totales locales). **Import y OCR siguen en el backend** hasta M3 y M4.
- **Pantallas:**
  - reporte **Ganancias** (ventas − costo − obsequios, con unidades a precio de referencia, sin costo conocido y pendientes);
  - sección **Lotes** en la ficha del producto, con "Completar costo" para lotes sin costo, que revaloriza las salidas;
  - badge "Obsequio" en el historial;
  - método de costeo en Ajustes;
  - las consultas por voz cuentan solo ventas.
- **Sin tests de `Sync` en CI** (solo compilación): las reglas están en `Core` (M1, con tests); la integración se verifica en el iPhone.

## 8.2 Implementación M3

- **Paquete `Natura`** (iOS/macOS, tests en macOS en CI):
  - `CryptoJSAES` (CommonCrypto + MD5, vector verificado contra el algoritmo del backend);
  - `ZipReader` (sin validar CRC, deflate con `Compression`);
  - `NaturaClient` (actor):
    - login: la URL de login con su `client_id` sale de la redirección de `/ingreso/cl`, y la API y la clave del bundle, ambas en vivo;
    - signin y `natura-callback` con redirecciones a mano hasta `wcmn_session`;
    - pedidos (todas las páginas);
    - Excel del pedido (prueba con `orderNumber` y luego con `id`; si no llega un XLSX, HTML de líneas);
    - ciclo del home;
    - GSP: `recover-session`, cadena del `xAppToken`, `consultantSection`, categorías y `cardSection` por categoría.
- **Core:** parsers de usuario y errores de credenciales, bundle de GSP, pedidos, líneas HTML, Excel del pedido (excluye la tasa de servicio) y `query_cycle`; `OutflowKind.priorSales` y su bloque aparte en el reporte. Tests en Linux.
- **Importación** (`SyncEngine.importFromNatura`):
  - la primera vez **borra lo bajado del backend** (pedidos, líneas, lotes, stock, kardex, cola) y conserva productos (por SKU), clientes, pedidos de clientes y ventas;
  - trae solo los pedidos entregados nuevos;
  - antes del inventario inicial, cada línea entra **recibida** con su lote (costo y sugerido del Excel), con el pedido cerrado; después, los pedidos nuevos quedan pendientes de recepción;
  - guarda el ciclo vigente con sus fechas y el catálogo del ciclo (categoría = pestaña de GSP, precio de compra y venta del ciclo, puntos, imagen); lo que nunca se pidió entra al catálogo sin stock;
  - si GSP falla, los pedidos igual quedan importados.
- **"Agregar inventario actual"** (Ajustes › Natura, una vez): conteo por escáner (+1 por lectura) o a mano. La diferencia sale con FIFO como **ventas previas** (`LocalSale.kind = .priorSales`, ingreso estimado al sugerido de cada lote) y lo contado de más entra al último costo. Desde ahí, recepción normal.
- **Sin backend:** el pull no lee nada, el saldo inicial de M2 quedó desactivado y el OCR del servidor muestra un aviso hasta M4. La sesión de la app (login) sigue hasta M7.
- **Sin productos manuales:** se quitaron el "+" de Productos, "Crear producto" en la foto y la creación rápida en el pedido de cliente.
- **Por verificar en el iPhone:** el login directo (Akamai desde la red móvil), el parámetro de la ruta del Excel, el número de categorías y páginas del ciclo y los tiempos de la primera importación.

## 8.3 M4 descartada (2026-11-27)

- La boleta impresa trae lo mismo que el **Excel del pedido** (cantidad, código, precio revista, precio CB), y el Excel se baja solo en cada importación, para todos los pedidos.
- Lo que proponía el OCR ya está cubierto: el **precio sugerido** y el **costo** vienen del Excel (de respaldo, el HTML de líneas da el costo). La **cantidad** de la boleta es lo facturado, no lo que llegó: la recepción se cuenta o escanea igual.
- Se llegó a implementar con Vision y se quitó: tarjeta "Comprobante", badges de OCR y "Aceptar propuestas". Los campos de OCR del modelo (`ocrStatusRaw`, `proposed…`) quedan sin uso hasta M7, para no forzar una migración.
- Si alguna vez hiciera falta, el OCR con Tesseract sigue en el repo `mynatura` (`natura-order-receipt-ocr.ts`).

## 8.4 Implementación M5

- **Respaldo** (`Persistence/Backup.swift`, tests en macOS en CI):
  - JSON versionado (`format: "mynatura-backup"`, `version: 1`, fechas ISO 8601) con ajustes, productos, stock, lotes, kardex, ventas y obsequios, clientes, pedidos de clientes, pedidos y líneas Natura, y motivos de precio;
  - **no incluye** credenciales, la sesión de la app, la cola de sincronización ni el carro en curso;
  - **exportar** (Ajustes › Respaldo): archivo `MyNatura-respaldo-AAAA-MM-DD.json` en la hoja de compartir (Archivos, Drive, correo). Al completarse, se marca la fecha del respaldo;
  - **importar**: se elige el archivo, se ve la vista previa con conteos y se confirma. Reemplaza todos los datos locales con el `sellerId` de la sesión actual, que se conserva. Si algo falla a mitad de camino, vuelve a dejar lo que había;
  - un respaldo de una versión más nueva de la app se rechaza con un mensaje claro.
- **Recordatorio** (`Core.BackupReminder`, tests en Linux): "Último respaldo: hoy / ayer / hace N días / nunca". Pasados 7 días (o nunca, si hay datos), aparece un aviso en Ajustes y un badge en la pestaña.
- **Credenciales de Natura** (`Natura.NaturaCredentialStore`):
  - el código de consultora se guarda sin biometría, para prellenar el campo;
  - la contraseña se guarda con `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` + `SecAccessControl([.biometryCurrentSet, .or, .devicePasscode])`. No va al respaldo de iCloud y se invalida si cambian las huellas;
  - en Ajustes › Natura: interruptor "Guardar en este iPhone (Touch ID)", que se guarda solo si el login funcionó; "Olvidar contraseña". Con contraseña guardada, "Actualizar desde Natura" pide Touch ID;
  - si Natura rechaza la contraseña guardada, se borra y se pide de nuevo. Cerrar sesión también la borra.
- **Por verificar en el iPhone:** la hoja de compartir con Drive y correo, restaurar un respaldo real, y el Touch ID (incluido el caso sin código del iPhone, que impide guardar la contraseña).

## 8.5 Implementación M6

- **Natura (`NaturaClient`):**
  - `accounts()`: `GET /pedidos/ajax/mis-cuentas?order=0&state=`. Con `state` vacío llegan todos los documentos, abiertos y cerrados; la app filtra lo pendiente;
  - al abrir GSP se guarda el **crédito** y el **bloqueo** de `authCommercialInfo` (`credit { available limit additional }`, `isBlocked`);
  - **ofertas** en `cardSection`: `discountTag` (lista, p. ej. "37%"), `percentageDiscount`, `promotionSummary { description details { label } }`, `gifts { name }` y el precio normal (`from`) cuando es mayor al vigente (`to`);
  - **corrección del catálogo del ciclo (M3):** en las tarjetas simples el precio, los puntos y la imagen vienen en la tarjeta (`products[0]` los trae en `null`). Antes quedaban sin precio.
- **Core (tests en Linux, hoy sin correr en CI):** `NaturaAccounts.decode` (montos como texto, fechas ISO), `NaturaAccountSummary` (saldo pendiente, próximo vencimiento no vencido, atrasos con monto y días máximos), `NaturaCredit` y `CycleOffer` (texto y regla de oferta).
- **Persistence:** `NaturaAccountSnapshot` (caché por cuenta: crédito, bloqueo, documentos y fechas de lectura; no va en el respaldo). `CatalogProduct` suma precio normal, % y texto de la oferta del ciclo (sí van en el respaldo).
- **Sync:**
  - la importación lee también la cuenta y el crédito. Si fallan, queda una nota y los pedidos se importan igual;
  - `refreshNaturaAccount`: actualización liviana, solo cuenta, crédito y ciclo.
- **Pantallas** (Ajustes › Natura):
  - **Cuenta Natura:** ciclo vigente con inicio, cierre y días que quedan; aviso de cuenta bloqueada; crédito disponible, límite y adicional; pagos con saldo pendiente, próximo vencimiento, aviso de atrasos y documentos pendientes. "Actualizar" usa la contraseña guardada (Touch ID); sin red, muestra la última lectura con su fecha;
  - **Ofertas del ciclo:** productos del ciclo vigente con descuento, promoción o regalo, por categoría, con buscador, precio de compra (y el normal), de venta y puntos.
- **Fuera de M6** (quedan para el Asistente, U5–U6): respuestas por voz ("¿cuánto crédito tengo?", "¿cuándo vence mi pago?") y búsqueda en la revista.
- **Por verificar en el iPhone:** los valores reales de `mis-cuentas` (si `isOverdue` y `overdueDays` coinciden), el crédito en `authCommercialInfo` y que la consulta de `cardSection` con los campos de oferta no sea rechazada.

## 9. Riesgos

| Riesgo | Mitigación |
|---|---|
| Pérdida del iPhone o borrado de la app | Respaldo JSON + respaldo de iCloud del iPhone; recordatorio semanal |
| Natura cambia HTML o API | Parseo aislado en `Natura` con tests de ejemplo; errores visibles; los datos propios no dependen de eso |
| Akamai bloquea desde el iPhone | Mensaje y reintento; sin Playwright. Si fuera frecuente, reevaluar un proxy mínimo |
| Costo de referencia discutible (unidad gratis valorizada) | Siempre marcado y visible por separado en el reporte; regla en `Core` con tests |
| Firma de 7 días con Apple ID gratis | Reinstalar conserva datos; el respaldo cubre el peor caso |
| Lógica del backend que no estaba en `Core` (lotes, asignación de costos) | M1 la porta con tests antes de tocar las pantallas |

---

## 10. Decisiones (2026-11-26)

1. **Gratis de Natura:** llegan a costo 0, no se venden (muestras, bolsas, otra copia de la revista); el precio de venta de un producto nunca es 0.
2. **Obsequios a terceros:** salen a precio 0 y son **pérdida** en la ganancia, al costo según el método.
3. **Costo de ventas:** FIFO, LIFO o **Mayor precio**. Si la unidad viene de un lote gratis, se indica y se usa el precio conocido según el método (§4.4).
4. **Muestras:** normalmente gratis, pero se pueden comprar; se clasifican por el valor de la línea.
5. **Contraseña de Natura en el Keychain** con Touch ID.
6. **Backend sin datos manuales:** la migración es reimportar desde Natura.

7. **Obsequio de una unidad gratis de un producto que alguna vez se compró:** se aplica la **misma regla que en la venta**, según el método. El método decide qué lote sale; si sale un lote gratis, se usa el precio conocido de ese método (§4.4). No hay caso especial para obsequios.
