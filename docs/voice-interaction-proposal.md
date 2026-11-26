# Propuesta — Interacción por voz en MyNatura iOS

> **Estado:** V1 (núcleo) implementada en `Packages/Core/Sources/Core/Voice/`; el resto es propuesta. Complementa `ios-app-design.md`; respeta sus principios: offline primero, `Core` solo Foundation y Apple ID gratis (sin extensiones).

---

## 1. Por qué

La consultora trabaja **con las manos ocupadas y hablando con gente**: anota encargos mientras el cliente dicta, cuenta cajas al recibir y vende en persona. Hoy todo pasa por teclado y búsqueda. La voz sirve como **acelerador de entrada**, no como reemplazo de la pantalla:

- *"María Pérez: dos del 12345, un Kaiak clásico y tres jabones Ekos castaña."* → pedido de cliente con 3 líneas.
- *"Llegaron cuatro del 87654."* → recepción por línea.
- *"¿Cuánto me queda de Kaiak?"* → respuesta hablada y en pantalla.

## 2. Principios

1. **La voz propone, la pantalla confirma.** Todo comando que **escribe datos** termina en una vista previa editable y un toque en *Aplicar*. Nada se registra sin que la persona lo vea.
2. **Nunca por voz:** registrar una venta sin tocar *Registrar*, cerrar pedidos, **enviar el pedido a Natura**, borrar datos o tocar credenciales.
3. **Offline y en el dispositivo:** se prefiere el reconocimiento local. El audio **no se guarda** ni se envía al backend.
4. **Contextual:** cada pantalla declara qué comandos acepta. "Agrega dos del 12345" significa algo distinto en el carro, en un pedido de cliente o en el borrador Natura.
5. **Tolerante:** si algo no se entiende, se muestra como *chip* con "?" para corregirlo a mano. No se descarta en silencio.

---

## 3. Casos de uso (por prioridad)

| # | Pantalla | Ejemplos | Resultado |
|---|---|---|---|
| 1 | **Editor de pedido de cliente** (§4.7) | "Para Juan Soto, ciclo actual: dos 12345 y un desodorante Humor" · "quita el Humor" · "nota: entregar el viernes" | Cliente (existente o nuevo), líneas, nota |
| 2 | **Borrador pedido Natura** (`natura-order-placement.md`) | "agrega cinco del 87654" · "sube a tres el Ekos" · "¿cuántos puntos llevo?" | Líneas; respuesta con puntos vs tope |
| 3 | **Recepción** (por línea / por código) | "llegaron cuatro del 87654" · "del Kaiak llegaron dos, falta uno" | Cantidad a recibir por línea, faltantes |
| 4 | **Conciliación** (detalle de producto) | "conté siete" | Conteo físico |
| 5 | **Vender / Carro** | "dos Kaiak a nueve mil novecientos noventa" · "para la señora Ana" | Carro precargado; si el precio es menor al sugerido, se pide el motivo en pantalla |
| 6 | **Consultas** (cualquier pantalla) | "¿cuánto stock de Kaiak?" · "¿qué me encargó Juan?" · "¿cuánto vendí esta semana?" · "¿cuándo cierra el ciclo?" | Respuesta hablada (`AVSpeechSynthesizer`) + tarjeta |
| 7 | **Navegación** | "ir a recepción" · "abre el pedido de María" | Cambio de tab / ruta |

---

## 4. Experiencia de uso

- **Botón de micrófono** en la toolbar de las pantallas con voz y en la barra inferior de los editores.
  - **Mantener presionado para hablar** es el modo por defecto: evita activaciones accidentales y deja claro cuándo escucha.
  - **Toque** activa el modo continuo (solo en Recepción y en el editor de pedido de cliente). Termina con "listo" o tras 8 s de silencio.
- **Transcripción en vivo** arriba. Debajo, **chips** con lo interpretado: `👤 Juan Soto` · `2 × Kaiak Clásico 100 ml (12345)` · `? "desodorante umor"`.
  - Cada chip se toca para corregir: elegir entre candidatos, cambiar la cantidad o quitarlo.
- **Aplicar** agrega los chips al formulario. **Deshacer** queda disponible hasta el siguiente cambio.
- **Hápticos:** éxito al reconocer cada línea y advertencia ante una ambigüedad.
- **Respuestas habladas** solo para *consultas*. Los comandos de escritura se confirman en pantalla, sin voz, para no molestar en una conversación con clientes.

---

## 5. Arquitectura

```
Features (SwiftUI)
  VoiceButton · VoiceOverlay (transcripción + chips) · VoiceContext por pantalla
        │
Features/Shared/Voice (iOS)
  SpeechCaptureService   AVAudioEngine + SFSpeechRecognizer (es-CL)
  SpeechVocabulary       contextualStrings / modelo de lenguaje personalizado (§5.3)
  VoiceSpeaker           AVSpeechSynthesizer (respuestas)
        │  texto
Core/Voice (solo Foundation, testeado en Linux)
  SpanishNumberParser    "doce mil novecientos noventa" → 12990 · "uno dos tres cuatro cinco" → "12345"
  UtteranceSegmenter     separa líneas por "y", ",", "más", "también"
  CommandGrammar         texto → [VoiceCommand] según VoiceContext
  ProductMatcher         referencia → candidatos con puntaje (SKU exacto, alias, nombre difuso)
  CustomerMatcher        reutiliza Normalize.customerName
```

### 5.1 Comandos (`Core`)

> Implementado en V1 (`VoiceCommand.swift`): `setCustomer(name:)`, `setCycle`, `addLine(quantity:product:price:)` con `ParsedPrice` (marca los precios abreviados), `repeatLast`, `setQuantity`, `removeLine`, `note`, `undo`, `done` y `unrecognized`. `receive`, `physicalCount`, `query` y `navigate` llegan con sus etapas (V3–V4). El bloque de abajo es el diseño original.
```swift
public enum VoiceCommand: Equatable, Sendable {
    case setCustomer(CustomerRef)                    // existente o nuevo por nombre
    case addLine(qty: Int, product: ProductRef, price: Money?)
    case setQuantity(product: ProductRef, qty: Int)
    case removeLine(ProductRef)
    case receive(product: ProductRef, qty: Int, missing: Int?)
    case physicalCount(Int)
    case note(String)
    case query(VoiceQuery)                           // stock, encargos, ventas, ciclo, puntos
    case navigate(VoiceDestination)
    case undo, done
}
public enum ProductRef: Equatable, Sendable { case sku(String), text(String) }
```
- `VoiceContext` (`.customerOrder`, `.naturaDraft`, `.receiving(orderId)`, `.reconciliation`, `.cart`, `.global`) limita qué comandos son válidos y cómo se lee un número suelto: en Recepción, "12345 cuatro" es código + cantidad; en Conciliación, "siete" es un conteo.
- La resolución de `ProductRef.text` se hace fuera de `Core`, con los datos de SwiftData, pero el **algoritmo** de puntaje vive en `Core` (`ProductMatcher`) y se testea con listas fijas.

### 5.2 Números, códigos y precios (es-CL)
- **Códigos Natura** (5–7 dígitos):
  - se aceptan dictados dígito a dígito ("uno dos tres cuatro cinco") o por grupos ("ciento veintitrés cuarenta y cinco");
  - un número se trata como **código** si existe en el catálogo o en la revista del ciclo, y como **cantidad** si es ≤ 99 y está antes del producto.
- **Cantidades:** "un/una/uno", "dos"… "una docena"; "otro más" suma 1 a la última línea.
- **Precios:**
  - "nueve mil novecientos noventa" → 9.990;
  - "luca" / "lucas" → ×1.000 ("diez lucas" → 10.000);
  - "nueve noventa" en contexto de precio → 9.990 si el sugerido está entre 5.000 y 20.000; si no, se pide confirmar.
- Todo con tests de tabla: frase → resultado esperado.

### 5.3 Reconocimiento de voz
- **iOS 17+ (target actual):** `SFSpeechRecognizer(locale: es-CL)`.
  - Si `supportsOnDeviceRecognition`, se usa `requiresOnDeviceRecognition = true`: sin red y sin límite de 1 minuto.
  - Si `es-CL` no tiene modelo local en el equipo, se prueba `es-419` / `es-MX` local antes de caer al servidor de Apple. El servidor requiere red y envía audio a Apple: se avisa una vez y se puede desactivar en Ajustes ("Reconocimiento solo en el dispositivo").
- **Vocabulario del negocio:**
  - **Nivel 1:** `contextualStrings` con nombres de productos del catálogo, líneas Natura (Ekos, Kaiak, Chronos, Tododia, Una, Humor, Essencial, Luna, Mamãe e Bebê…) y nombres de clientes. Cambia por pantalla.
  - **Nivel 2:** modelo de lenguaje personalizado (`SFCustomLanguageModelData`, iOS 17). Plantillas tipo `<cantidad> <producto>`, `llegaron <cantidad> del <código>` y pronunciaciones propias ("Ekos" = /ˈekos/). Se genera en el dispositivo al sincronizar el catálogo y la revista del ciclo, y solo funciona con reconocimiento local.
- **iOS 26 (opcional, con `#available`):** `SpeechAnalyzer` / `SpeechTranscriber` si da mejor precisión local en español. Se mide antes de adoptarlo.

### 5.4 Interpretación libre (opcional)
- La gramática (§5.1) cubre lo frecuente y es predecible.
- Si un equipo tiene **Apple Intelligence** (iOS 26+, `FoundationModels`), se puede usar el modelo local como **respaldo** para frases que la gramática no entiende. Se le pide una salida estructurada (`@Generable` con los mismos `VoiceCommand`), validada después contra el catálogo. Es local y funciona sin red.
- **Descartado:** enviar el texto a un LLM en la nube. Saca nombres de clientes del dispositivo y rompe el modo offline.

### 5.5 Siri y Atajos (etapa opcional)
- **App Intents** dentro del target principal (no requieren extensión). Ejemplos:
  - "Nuevo pedido en MyNatura"
  - "Stock de Kaiak en MyNatura"
  - "¿Cuándo cierra el ciclo en MyNatura?"
- `AppShortcutsProvider` con frases en español. Los intents que escriben datos **abren la app** en la pantalla con el overlay de voz; no escriben en segundo plano.
- **Verificar en el iPhone** que los App Shortcuts funcionan con la firma de Apple ID gratis (no usan el entitlement de SiriKit, pero hay que comprobarlo con Sideloadly).

---

## 6. Permisos y configuración

En `project.yml` (`info.properties`):
```yaml
NSMicrophoneUsageDescription: "MyNatura usa el micrófono para que puedas dictar pedidos, recepciones y consultas."
NSSpeechRecognitionUsageDescription: "MyNatura transcribe tu voz para completar pedidos y responder consultas. El audio no se guarda."
```
- Los permisos se piden **la primera vez que se toca el micrófono**, no al abrir la app.
- **Ajustes → Voz:**
  - activar o desactivar la voz;
  - solo en el dispositivo;
  - respuestas habladas sí/no;
  - modo continuo en Recepción;
  - "Frases no entendidas": registro **local** opcional que la consultora puede revisar o borrar, para ajustar la gramática. Nunca se envía.

---

## 7. Privacidad y seguridad

- El audio vive solo en memoria mientras se reconoce. No se guarda ni se sube al backend.
- Con reconocimiento local, nada sale del iPhone. Con el servidor de Apple, aplica su política de privacidad, y la app lo indica con un ícono de nube en el overlay.
- La voz no puede ejecutar acciones de dinero ni envíos a Natura (§2.2).
- Los nombres de clientes en `contextualStrings` y en el modelo personalizado quedan en el dispositivo.

---

## 8. Pruebas

- **Core (Linux, Swift Testing):** corpus de frases por contexto.
  - Números y precios en es-CL, códigos dictados de varias formas, segmentación de varias líneas, ambigüedades.
  - `ProductMatcher` con catálogo fijo: errores típicos de transcripción ("umor" → Humor, "e cos" → Ekos).
- **Features:** previews del overlay con transcripciones simuladas (sin micrófono), para revisar el UI en CI.
- **En el iPhone (al final, como el resto de etapas):** precisión con ruido de fondo, acento, y nombres de clientes y productos reales.

---

## 9. Plan por etapas

| # | Etapa | Entregable | Estado |
|---|---|---|---|
| V1 | Núcleo | `Core/Voice`: números, segmentación, gramática de pedido de cliente, `ProductMatcher` + tests | ✅ 2026-11-26 |
| V2 | Pedido de cliente por voz | `SpeechCaptureService` (local preferido), overlay con chips, botón en el editor, permisos | — |
| V3 | Recepción y conciliación | Contextos `.receiving` y `.reconciliation`, modo continuo | — |
| V4 | Consultas + respuestas habladas | `VoiceQuery` (stock, encargos, ventas, ciclo); `AVSpeechSynthesizer` | — |
| V5 | Borrador Natura y carro | Contextos `.naturaDraft` (con puntos) y `.cart` (precio y motivo en pantalla) | — |
| V6 | Vocabulario | Modelo de lenguaje personalizado generado del catálogo y la revista del ciclo | — |
| V7 | Opcionales | App Intents / Atajos; respaldo con `FoundationModels` en equipos compatibles | — |

---

## 10. Riesgos

| Riesgo | Mitigación |
|---|---|
| `es-CL` sin modelo local en el equipo | Variantes locales `es-419`/`es-MX`; servidor solo con permiso; la gramática no depende del acento |
| Nombres de marca mal transcritos | `contextualStrings`, alias por producto, modelo personalizado (V6), chips corregibles |
| Número leído como cantidad en vez de código (o al revés) | Reglas por contexto + verificación contra catálogo y revista; ante duda, chip "?" |
| Ruido (ferias, casas) | Mantener presionado por defecto; modo continuo solo donde aporta |
| Activación accidental en medio de una venta | Nada se registra sin *Aplicar* / *Registrar* |
| Restricciones de Apple ID gratis | Todo funciona sin extensiones; App Intents se valida antes de prometerlo |
| Batería | Micrófono solo mientras se mantiene el botón o en modo continuo con corte por silencio |
