# Plan — App iOS local primero, sin backend propio

> **Estado:** decisión tomada y plan propuesto (2026-11-26). Sin implementar.
> **Decisión:** la app iOS guarda **todos los datos de la consultora en el iPhone** (fuente de verdad, offline first) y habla **directo con Natura** cuando hay conexión. Se deja de usar el backend propio (Fastify + PostgreSQL) y la PWA.
> Al terminar, actualizar `CLAUDE.md` y `ios-app-design.md` (§7 sync y §8 endpoints quedan obsoletos).

---

## 1. Por qué

Respuestas que definen la decisión:

| Pregunta | Respuesta | Consecuencia |
|---|---|---|
| ¿Se usa la PWA o el PC? | No | El backend no tiene otro cliente que lo justifique |
| ¿Otro dispositivo u otra persona? | No | No hace falta sincronizar entre dispositivos |
| ¿Datos reales en el backend? | Solo pedidos y productos importados de Natura | Se pueden **volver a importar desde Natura**; no hay datos manuales que migrar (ver §7) |

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
- **Credenciales de Natura:** igual que hoy, se piden al importar o consultar y viven solo en memoria. Opcional, a decidir: guardarlas en el Keychain con Face ID / Touch ID para no escribirlas cada vez.

---

## 4. Costo, ganancia y **productos a costo cero (regalos)**

### 4.1 Lo que hace hoy el backend (y hay que corregir)

En la importación (`import-delivered-orders.ts`):
1. Una línea de tipo **"Regalo"** se marca **vendible** (salvo revista o catálogo), pero su precio unitario suele venir como "-" → `purchaseUnitPriceCents = null`.
2. El lote se crea con **costo `null`**. Al vender ese producto, `create-sale.ts` falla con *"No fue posible determinar el costo del lote"* cuando le toca ese lote: **un regalo no se puede vender**.
3. El producto guarda `lastPurchaseUnitPriceCents = purchase ?? 0`: un regalo **pisa con 0 el último costo** de un producto que antes se compró pagando.

### 4.2 Reglas nuevas (`Core`, con tests)

- **Costo desconocido ≠ costo cero.** Cada lote tiene `unitCost: Money?` y `costSource`:

| `costSource` | Cuándo | `unitCost` |
|---|---|---|
| `purchased` | Línea con valor unitario > 0 | El valor pagado |
| `free` | Línea de tipo regalo, gratis o promoción con valor 0 o "-" | **0** (conocido) |
| `unknown` | No se pudo leer el valor de una línea pagada | `nil`; se puede completar a mano |
| `manual` | Producto creado o ajustado a mano con costo ingresado | El ingresado |

- **Clasificación de la línea** (`NaturaLineClassifier`) según `Tipo` y valor unitario:
  - **producto pagado:** vendible, costo = valor;
  - **regalo o gratis** (`Tipo` = Regalo, Gratis o Promoción, con valor 0 o "-"): **entra al stock con costo 0**. Es vendible y también se puede regalar a un cliente;
  - **material de apoyo** (revista, catálogo, folleto, bolsas): **no entra al stock vendible**, pero queda en el pedido para que la recepción cuadre.
- **El último costo de compra** del producto se actualiza **solo con lotes `purchased`**. Un regalo no lo pisa.
- **Consumo de lotes (FIFO/LIFO)** igual para todos los lotes. Un lote `free` aporta costo 0 a la venta, así que esa venta tiene **ganancia = precio de venta**.
- **Venta con lote `unknown`:** se permite. La línea queda con "costo pendiente", la ganancia se marca **incompleta** (no 0) y se puede corregir después ingresando el costo.
- **Salida por obsequio** (nuevo movimiento `giftOut`): entregar un producto gratis a un cliente o usarlo como muestra. Descuenta stock y consume lotes, **sin ingreso**. Su costo cuenta como **gasto de obsequios** en el reporte de ganancias.
- **Reporte de ganancias**, separado en:
  - ventas;
  - costo de lo vendido (`purchased` + `manual`);
  - **ganancia por regalos vendidos** (lotes `free`);
  - **gasto en obsequios** (`giftOut`, al costo del lote);
  - ventas con **costo pendiente**.
  
  Así se ve cuánto de la ganancia viene de los regalos de Natura.

### 4.3 Otros precios
- **Precio de venta sugerido:** de la revista del ciclo, como hoy; editable por producto.
- **Precio del ciclo según ofertas y nivel** (GSP `cardSection`: `purchasePrice`, `resalePrice`, `points`, `promotionSummary`): **para planificar** el pedido y comparar. **No** cambia el costo de lo ya comprado: ese sale siempre de la línea del pedido entregado.

---

## 5. Integración directa con Natura (portar del backend)

| Hoy en el backend (TypeScript) | Pasa a (Swift, paquete `Natura`) | Notas |
|---|---|---|
| `natura-http-auth.ts` (signin, CryptoJS AES, callback) | `NaturaAuth` | AES-256-CBC + EVP_BytesToKey(MD5) con CommonCrypto; config leída del bundle en vivo |
| `natura-gsp-auth.ts` (recover-session, xAppToken) | `NaturaAuth` / `GspClient` | Verificado con `natura:probe-gsp-login` |
| `natura-http-client.ts` (pedidos JSON, líneas HTML `#order-items-list`) | `MinegocioClient` | Mismo parseo; tests con HTML de ejemplo **sin datos personales** |
| `natura-magazine-pricing.ts` (precios de la revista) | `MagazineClient` | Mismas heurísticas; tests en `Core` |
| OCR de boleta (Tesseract + sharp) | Vision (`VNRecognizeTextRequest`) | Igual que la foto de producto; sin red |
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

Los datos reales del backend son **pedidos y productos importados de Natura**, así que lo más simple y limpio es:

1. **Reimportar desde Natura en la app** (M3): pedidos entregados, líneas, costos y lotes. Ya con las reglas nuevas de §4, sin el problema de los regalos.
2. **Rescatar lo agregado a mano**, si existe:
   - EAN asociados;
   - precios de venta editados;
   - cantidades recibidas y cierres de recepción;
   - conciliaciones;
   - productos creados a mano.
   
   Un script de una sola vez en el backend (`export-for-ios`) genera un JSON con eso, y la app lo importa con el mismo formato del respaldo (§6).
3. Verificar conteos (pedidos, líneas, productos, stock por producto) contra el backend antes de apagarlo.

---

## 8. Etapas

Cada etapa deja la app usable. Mientras dure la transición, el backend sigue funcionando hasta M7.

| # | Etapa | Entregable |
|---|---|---|
| M1 | Reglas de costo | `Core`: lotes con `costSource`, clasificador de líneas Natura (regalo, gratis, material), FIFO/LIFO con costo desconocido, `giftOut`, reporte de ganancias separado; tests |
| M2 | Store local | Acciones (vender, recibir, conciliar, EAN, clientes, pedidos, foto, voz) escriben directo en SwiftData con lotes y costos locales; `SyncEngine` en modo solo lectura (todavía puede bajar datos) |
| M3 | Natura directo | Paquete `Natura`: login minegocio + import de pedidos entregados (JSON + HTML) + revista; reimportar todo en el iPhone |
| M4 | OCR local | Boleta con Vision; propuestas de cantidad y precio como hoy |
| M5 | Respaldo | Exportar / importar JSON, recordatorio; importar el JSON de `export-for-ios` (§7) |
| M6 | Cuenta, ciclo, ofertas | `MinegocioClient.accounts`, `query_cycle`, `GspClient` (ciclo con fechas, crédito, ofertas): etapas U5–U6 del Asistente sin backend |
| M7 | Retiro | Se quitan `SyncEngine`, `APIClient` al backend, login a la app y pastilla de sync; se archiva el repo `mynatura`; se actualizan `CLAUDE.md` y `ios-app-design.md` |
| M8 | Pedido Natura (después) | `natura-order-placement.md` con el flujo GSP, directo desde la app |

---

## 9. Riesgos

| Riesgo | Mitigación |
|---|---|
| Pérdida del iPhone o borrado de la app | Respaldo JSON + respaldo de iCloud del iPhone; recordatorio semanal |
| Natura cambia HTML o API | Parseo aislado en `Natura` con tests de ejemplo; errores visibles; los datos propios no dependen de eso |
| Akamai bloquea desde el iPhone | Mensaje y reintento; sin Playwright. Si fuera frecuente, reevaluar un proxy mínimo |
| Regalos mal clasificados | Clasificador con tests y `Tipo` visible en la línea; cambiar la clasificación a mano en la recepción |
| Firma de 7 días con Apple ID gratis | Reinstalar conserva datos; el respaldo cubre el peor caso |
| Lógica del backend que no estaba en `Core` (lotes, asignación de costos) | M1 la porta con tests antes de tocar las pantallas |

---

## 10. Preguntas abiertas

1. ¿Qué valores de **`Tipo`** aparecen en tus pedidos además de "Regalo"? (Por ejemplo "Gratis", "Muestra", "Promoción", "Material".) Define el clasificador de §4.2.
2. Los regalos que recibes, ¿los **vendes**, los **regalas** a clientes, o ambas cosas? Las dos quedan soportadas; define el valor por defecto.
3. ¿Guardar la contraseña de Natura en el **Keychain con Face ID / Touch ID**, o seguir pidiéndola cada vez?
4. ¿Hay algo ingresado a mano en el backend que valga la pena rescatar (EAN, precios editados, recepciones)? Si no, la migración es solo reimportar.
