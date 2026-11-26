# Pendientes

> Lista viva de lo que quedó abierto. Al cerrar algo, se borra de aquí y se marca en su documento
> (`voice-interaction-proposal.md` §9, `natura-order-placement.md` §9, `ios-app-design.md` §11).
> Última revisión: 2026-11-26.

---

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
- **Navegación por voz** ("ir a recepción", "abre el pedido de María"): está en §3, caso 7, del documento de voz, pero no en el plan.
- **Ajustes → Voz** (§6 del documento de voz): reunir en una sección los interruptores que hoy están repartidos en las hojas:
  - permitir servidores de Apple;
  - leer respuestas en voz alta;
  - modo continuo en Recepción.
  
  Sumar ahí el registro **local** y opcional de frases no entendidas.
- **Fecha de cierre del ciclo** en "¿Cuándo cierra el ciclo?": hoy se responde con el último ciclo registrado. Se resuelve con el punto "Ciclo vigente" de §2.

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
- Vocabulario propio: que aparezca el ícono del libro tras abrir una hoja de voz (con reconocimiento local), cuánto tarda en armarse la primera vez y si mejora "Ekos", "Kaiak", "Tododia" y los nombres de clientes.
- Pantalla chica: que las hojas de dictado a media altura (`.medium`) dejen ver transcripción, chips y botón. Si no, abrirlas a pantalla completa.

---

## 2. Pedido a Natura (`natura-order-placement.md`)

- **Captura de endpoints (la hace la consultora):** recorrido de §4.2 en minegocio con DevTools, guardando **Save all as HAR (sanitized)** fuera del repo, y **cancelar el pedido antes de cerrarlo**. De ahí salen rutas y DTOs para §5.2 (solo formas, sin valores). Incluye:
  - paso 0: de dónde sale "Ciclo Actual" en el home (HTML o XHR) y qué muestra el ⓘ;
  - pasos 17–19: ids del API de productos de la revista (`campaign_id`, `brochure_id`, `feed_id`), si trae puntos y ofertas, y el checkout por WhatsApp.
- **Ciclo vigente:** que el backend lea número y fechas del ciclo desde el home en cada login y los guarde por consultora. Lo usan la revista, el borrador y la respuesta de voz del ciclo.
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

- La tabla de estado de `ios-app-design.md` §11 tiene sus propios pendientes (p. ej. la base y las migraciones del backend en el PostgreSQL de Windows). Revisarlos allí antes de las pruebas en el iPhone.
- **Pruebas en el iPhone:** se hacen al terminar todas las etapas, siguiendo el plan acordado. Los puntos de "Verificar en el iPhone" de arriba se suman a esa pasada.
