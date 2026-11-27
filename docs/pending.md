# Pendientes

> Lista viva de lo que quedó abierto. Al cerrar algo, se borra de aquí y se marca en su documento
> (`voice-interaction-proposal.md` §9, `natura-order-placement.md` §9, `ios-app-design.md` §11).
> Última revisión: 2026-11-27.

---

## 0. Arquitectura: app local primero (`local-first-migration.md`)

Hecho: M1 reglas de costo · M2 store local · M3 Natura directo · M5 respaldo y Keychain · M6 cuenta, ciclo y ofertas · M7 retiro del backend. M4 (OCR de boleta) descartada. M8 (pedido Natura) queda para después (§2 de este archivo).
El repo `mynatura` queda tal cual: no se modifica, no se archiva y no se comparan datos con él.

### Pendiente de M7 (retiro)
- **Limpiar el esquema de SwiftData** con un `VersionedSchema` + `SchemaMigrationPlan`, probándolo en el iPhone sobre una instalación con datos. Hoy quedan sin uso, para no forzar una migración:
  - modelos `PendingMutation` y `DatasetSyncState`;
  - campos `syncStateRaw` (productos, clientes, pedidos, ventas, líneas), `LocalSale.serverId` y `errorMessage`, `InventoryEventRecord.isLocal`;
  - campos de OCR: `NaturaOrder.ocrStatusRaw` y `ocrProcessedAt`, `NaturaOrderLine.proposedSuggestedPesos` y `proposedReceivedQuantity`;
  - `SellerSettings.issueStrategyRaw` y `localInventoryAdoptedAt`.
- **Core:** quitar junto con lo anterior `MutationType`, `MutationStatus`, `SyncQueue`, `LocalID.references/rewrite` y `Dataset`/`DatasetSyncStatus`, con sus tests (`SalesAndSyncTests`).
- **`SessionSummary`** hace de perfil local: renombrarlo (p. ej. `LocalProfile`) en la misma migración.
- **Documentos:** `ios-app-design.md` ya está reducido a lo vigente (las secciones de sync, `APIClient` y backend quedaron como una nota) y el Asistente pasó a "directo desde la app". Quedan menciones históricas al backend en `natura-order-placement.md` §5 (diseño original), cubiertas por la nota de §9.
- **CI:** cuando termine la regla temporal de CI mínimo, volver a activar los tests (Core en Linux; Natura y Persistence en macOS). Varios tests escritos en M5–M6 no han corrido nunca.
- **Verificar en el iPhone:**
  - instalar sobre la versión anterior: los datos se conservan (mismo `sellerId`), la cola antigua se descarta y no quedan íconos de "sin sincronizar";
  - instalación nueva: abre directo, sin login, y crea un perfil local;
  - el código de consultora aparece en Ajustes después de importar;
  - "Borrar datos del iPhone" deja la app como recién instalada y borra la contraseña guardada.

## 1. Voz (`voice-interaction-proposal.md`)

Hecho: V1 núcleo · V2 pedido de cliente · V3 recepción, conciliación y modo continuo · V4 consultas con respuesta hablada · V5 carro de venta · V6 vocabulario propio · V7 Atajos de Siri.

### V5 — Borrador Natura
- El carro de venta ya está hecho (§5.9 del documento de voz).
- **Borrador del pedido Natura (bloqueado):** depende de que exista el borrador de `natura-order-placement.md`, cuyas etapas 1–2 requieren primero la captura de endpoints (§2 de este archivo).
  - Cuando exista: contexto `.naturaDraft` con "agrega cinco del 87654", "sube a tres el Ekos" y "¿cuántos puntos llevo?" contra el tope del nivel.

### V6 — Vocabulario del negocio (hecho, §5.10 del documento de voz)
- Pendiente: sumar los productos de la **revista del ciclo** cuando la app la tenga (etapa 1 del pedido Natura).
- Pendiente: pronunciaciones propias (`insert(term:)`, X-SAMPA), solo si las pruebas muestran marcas mal reconocidas.

### V7 — Atajos (hecho, §5.11 del documento de voz)
- Verificar en el iPhone que los Atajos funcionan con la firma de Apple ID gratis (Sideloadly).
- ~~Respaldo con `FoundationModels`~~: **descartado por ahora**. El iPhone de uso es un **SE 3.ª generación** (A15, sin Apple Intelligence), así que el modelo local de Apple no está disponible. Si se quiere interpretación libre, la única vía es un modelo en la nube vía backend: opcional, solo con conexión y enviando el texto dictado (decisión pendiente).

### Sin etapa asignada
- ~~Navegación por voz~~: **hecha** ("ir a recepción", "abre la revista", "muéstrame las ofertas", "abre el pedido de María", "abre el pedido del ciclo").
- ~~Ajustes → Voz~~: **hecho** (servidores de Apple, respuestas habladas, recepción sin manos al abrir, registro local opcional de frases no entendidas y ejemplos).
- ~~Fecha de cierre del ciclo~~: **hecha** con el ciclo vigente guardado. También "¿cuánto crédito tengo?" y "¿cuándo vence mi pago?".

### Límites conocidos (a revisar con frases reales)
- "Kaiak completo y Ekos completo" dicho de corrido queda como un solo producto. Con una coma o una pausa se separa.
- "nueve noventa" se lee como $9.990 y "nueve cincuenta" como $9.950. Siempre se marca para confirmar.
- Seis o más dígitos dictados seguidos sin "del" ("dos uno dos tres cuatro cinco") se toman como un solo código.
- En recepción, "llegó todo" sin producto se aplica a la última línea mencionada.

### Verificar en el iPhone (SE 3.ª generación, pantalla de 4,7")
- Si `es-CL` tiene modelo local. Si no, qué variante toma o si aparece el aviso del servidor de Apple.
- Que "mantener presionado" funcione dentro de las hojas, porque el gesto podría competir con el arrastre de la hoja.
- Modo sin manos:
  - que el toque corto no se active sin querer;
  - que el corte por pausa de 1,5 s funcione;
  - que no haya cortes de audio al reiniciar el reconocimiento entre frases.
- Respuestas habladas:
  - que la voz en español suene bien;
  - que la música vuelva a su volumen;
  - que el micrófono funcione otra vez después de una respuesta leída.
- Carro por voz: que al aplicar se abra el carro (tras cerrarse la hoja) y que el motivo aparezca cuando el precio dictado queda bajo el sugerido.
- Precisión con nombres reales de clientes y productos, y con ruido de fondo.
- Foto de producto (`product-photo-proposal.md`, P1–P3): lectura de EAN y código Natura en envases reales, con luz y reflejos; nombre de la etiqueta en español o portugués; botones de la ficha; inventario de repisa; Atajo "Foto de producto en MyNatura".
- Vocabulario propio: que aparezca el ícono del libro tras abrir una hoja de voz (con reconocimiento local), cuánto tarda en armarse la primera vez y si mejora "Ekos", "Kaiak", "Tododia" y los nombres de clientes.
- Pantalla chica: que las hojas de dictado a media altura (`.medium`) dejen ver transcripción, chips y botón. Si no, abrirlas a pantalla completa.

---

## 2. Pedido a Natura (`natura-order-placement.md`)

- **M8, etapas 1 y 2 hechas en la app (2026-11-27), sin backend:**
  - **Clientes › Revista:** abrir y compartir el link oficial del ciclo (con el código de consultora), PDF completo, envío por WhatsApp a cada cliente con teléfono y **"Mi selección del ciclo"** en PDF (foto, nombre, código, precio de venta y oferta);
  - **Recepción › Armar pedido:** borrador por ciclo con encargos confirmados − stock (y quién los pidió), ofertas y reposición, barra de puntos con tope a mano (ámbar al 90 %, rojo al pasarse, qué bajar primero), compra estimada y **compartir la lista** para cargarla en GSP.
  - **Falta:** etapa 3 en adelante (enviar al carro de GSP, regalos, cerrar), que requiere capturar el checkout; leer el **tope de puntos** de Natura (hoy a mano); **verificar en el iPhone** la URL de la revista con `id_consultora`, los enlaces `wa.me` y el PDF (fotos de GSP y tamaño).
- **Voz:** "¿cuándo cierra el ciclo?" ya usa el ciclo vigente con fecha; nuevas "¿cuánto crédito tengo?" y "¿cuándo vence mi pago?".

- **Captura de endpoints (la hace la consultora):** recorrido de §4.2 en minegocio con DevTools, guardando **Save all as HAR (sanitized)** fuera del repo, y **cancelar el pedido antes de cerrarlo**. De ahí salen rutas y DTOs para §5.2 (solo formas, sin valores). Incluye:
  - paso 0: de dónde sale "Ciclo Actual" en el home (HTML o XHR) y qué muestra el ⓘ;
  - pasos 17–19: ids del API de productos de la revista (`campaign_id`, `brochure_id`, `feed_id`), si trae puntos y ofertas, y el checkout por WhatsApp.
- ~~Login de GSP sin navegador, ciclo vigente, cuenta y ofertas~~: **hechos en la app** (M3 y M6), sin backend.
- **Etapas 1–6 de §9:**
  1. revista y catálogo para compartir;
  2. borrador local con barra de puntos;
  3. envío al carro producto a producto en simulación;
  4. regalos;
  5. cerrar el pedido, con interruptor apagado y primera vez con un pedido real autorizado;
  6. cierre de ciclo.
- Preguntas abiertas de §10 (suma vs. reemplazo al agregar, CSRF, tope de puntos, regalos, `isOrderGroup` / `subCycle`, año en ciclos que cruzan de año).

---

## 3. Otros

- **Pruebas en el iPhone:** se hacen al terminar todas las etapas, siguiendo el plan acordado. Los puntos de "Verificar en el iPhone" de arriba se suman a esa pasada.
