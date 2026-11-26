# Propuesta — Foto de un producto → reconocerlo → elegir acción → ejecutar

> **Estado:** propuesta, sin implementar (2026-11-26).
> Respeta los principios de `ios-app-design.md`: offline primero, `Core` solo Foundation y Apple ID gratis (sin extensiones). Considera el equipo de uso: **iPhone SE 3.ª gen.**, A15, pantalla de 4,7" y sin Apple Intelligence.
> Relacionados: `voice-interaction-proposal.md` (comparte la resolución de productos, los chips y la regla "la app propone, la pantalla confirma") y `natura-order-placement.md` (revista del ciclo).

---

## 1. Idea

La consultora tiene un producto en la mano y quiere hacer algo con él sin buscarlo en listas:

1. **Toma una foto** (o apunta la cámara).
2. La app **reconoce el producto**: por código de barras, por el código Natura impreso, por el nombre de la etiqueta o por cómo se ve.
3. Muestra una **ficha con botones de acción**: tomar inventario, asociar el código de barras, agregar a la venta, agregar a un pedido de cliente, recibir en un pedido Natura…
4. Al tocar un botón se **ejecuta** con las mismas acciones de siempre (`SyncEngine`): funciona sin conexión y se sincroniza después.

Casos típicos:

| Situación | Lo que resuelve la foto |
|---|---|
| Contar el stock de la repisa | Foto → "Tomar inventario" con el conteo listo para ajustar → guardar conciliación |
| Producto nuevo sin EAN asociado | Foto del envase → reconoce por nombre o código Natura → "Asociar EAN 7908…" con un toque |
| Venta en persona | Foto → "Agregar a la venta" (respeta stock y precio sugerido) |
| La clienta muestra un producto que quiere | Foto → "Agregar al pedido de María" |
| Abriendo la caja de Natura | Foto → "Recibir +1 en pedido 123456" si está pendiente en un pedido abierto |
| Producto que no está en el catálogo | Foto → nombre y código leídos de la etiqueta → "Crear producto" ya prellenado |

---

## 2. Reconocimiento: señales y dónde se calculan

Se combinan varias señales, de la más segura a la más difusa. Las tres primeras corren **en el iPhone, sin red**, con Vision, que funciona en el A15.

| # | Señal | Cómo | Confianza |
|---|---|---|---|
| 1 | **Código de barras** en la foto | `VNDetectBarcodesRequest` (EAN-13/8, UPC-E, Code128), mismo set que el escáner actual | Exacta, si el EAN está asociado |
| 2 | **Código Natura** impreso ("Cód. 12345", "(12345)", 5–7 dígitos) | `VNRecognizeTextRequest` (OCR local en español) + reglas de `Core` | Muy alta, si existe en el catálogo o en la revista |
| 3 | **Nombre en la etiqueta** ("KAIAK", "EKOS castaña") | El mismo OCR + `ProductMatcher` de la voz: fonético, alias, nombre corto | Media; ambiguo entre variantes |
| 4 | **Aspecto visual** | `VNGenerateImageFeaturePrintRequest` (huella de imagen local) comparada con **fotos de referencia** guardadas por producto | Media; mejora con el uso |
| 5 | **Servidor** (opcional, con conexión) | `POST /api/catalog/recognize` (multipart, como el OCR de boletas). El backend compara con las imágenes de la revista del ciclo y su API de productos (`natura-order-placement.md` §2.3), o usa OCR de mejor calidad | Respaldo cuando 1–4 no alcanzan |

**Por qué local primero:**
- funciona sin conexión;
- es inmediato;
- la foto no sale del iPhone;
- cubre la mayoría de los casos, porque los envases Natura traen código de barras y nombre legibles.

La señal 5 es la que cumple el "subirla" del pedido original. Queda **opcional**: se usa si la persona la activa y hay red. Las fotos de producto no tienen datos personales, pero igual consumen datos y dependen del backend.

**Fotos de referencia (señal 4):**
- cada vez que la persona **confirma** qué producto era, se puede guardar la huella de esa foto (`ProductPhoto`, unos KB; la foto en sí es opcional);
- con el tiempo, el reconocimiento por aspecto aprende **tus** productos, sin entrenar modelos;
- cuando exista la revista del ciclo en la app, sus imágenes pueden sembrar estas referencias.

### 2.1 Combinación (`Core`, probada en Linux)

```swift
public enum PhotoSignal: Equatable, Sendable {
    case barcode(String)                      // EAN leído
    case naturaCode(String)                   // código Natura leído por OCR
    case labelText([String])                  // líneas de texto de la etiqueta
    case visual(productId: String, distance: Double)
}

public enum ProductRecognizer {
    /// Candidatos ordenados: EAN asociado (1.0) > código Natura en catálogo (0.97) > nombre (ProductMatcher)
    /// > aspecto (según distancia). Varias señales que apuntan al mismo producto suman confianza.
    public static func rank(_ signals: [PhotoSignal], catalog: [RecognizableProduct]) -> [RecognitionCandidate]
    public static func resolve(...) -> VoiceMatch   // .found / .ambiguous / .notFound (mismo tipo que la voz)
    /// Códigos Natura en el texto OCR: "(12345)", "Cód. 12345", "Código: 12345"; descarta EAN, precios y fechas.
    public static func naturaCodes(in lines: [String]) -> [String]
}
```

- **Un candidato claro:** se muestra su ficha directamente.
- **Ambiguo:** se muestran 2 a 5 candidatos con miniatura y stock, y la persona toca el correcto. Eso además **enseña** la foto de referencia.
- **Ninguno:** se ofrece "Crear producto" con el código y el nombre leídos.

---

## 3. Acciones: botones según el contexto

Después del reconocimiento, una ficha con nombre, SKU, stock operativo, precio sugerido y la foto. Debajo, **solo los botones que aplican** (reglas puras en `Core`, `ProductActions.available(...)`):

| Botón | Aparece si… | Qué ejecuta (acción existente) |
|---|---|---|
| **Tomar inventario** | siempre | Stepper con el operativo + observación → `createReconciliation` |
| **Asociar EAN 7908…** | la foto trae un EAN que el producto no tiene y que no es de otro producto | `addBarcode` |
| **Agregar a la venta** | vendible y con stock > 0 | `Cart.add` (máx. stock); opción "ir al carro" |
| **Agregar a pedido de cliente** | siempre | Elegir pedido en borrador (o nuevo, eligiendo cliente) → `saveCustomerOrder` |
| **Recibir +1 en pedido N** | está en un pedido Natura abierto con pendiente | `confirmReceivingLine` (+1, sin pasar de lo pedido) |
| **Ver ficha y kardex** | siempre | Navega a `ProductDetailScreen` |
| **Crear producto** | no se reconoció | `quickCreateProduct` con código y nombre leídos, editables |
| **Agregar al borrador Natura** | cuando exista el borrador (`natura-order-placement.md`) | Línea del borrador, con sus puntos |

- **Confirmación:** las acciones que cambian datos llevan un paso visible (stepper, selector de pedido) antes de guardar, igual que la voz: la app propone, la pantalla confirma. "Agregar a la venta" solo carga el carro; **Registrar venta** sigue siendo un toque aparte.
- **Ráfaga:** un modo "siguiente foto" para inventario de repisa. Cada foto agrega una fila a una lista de conteo y se guarda todo junto al final.
- **Voz:** combinable con lo hecho. En la ficha, "conté siete" o "agrégalo a la venta" eligen el botón; la frase pasa por la gramática y el botón sigue mostrando qué se va a hacer.

---

## 4. Experiencia de uso

- **Entrada:** un botón de cámara (`camera.viewfinder`) en la toolbar de Productos y de Vender, y como Atajo de Siri ("Foto de producto en MyNatura", sumando un App Intent a V7).
- **Captura:**
  - vista de cámara (`AVCaptureSession` o `DataScannerViewController` con texto y códigos) con disparador grande;
  - en pantalla de 4,7", la ficha sube como hoja media y deja la cámara visible arriba.
  - También se puede **elegir una foto** de la fototeca (`PhotosPicker`), como la boleta.
- **Lectura en vivo:** `DataScannerViewController` ya reconoce código de barras **y texto** en vivo. Si se encuentra un EAN asociado o un código Natura del catálogo, se puede mostrar la ficha **sin disparar** la foto.
- **Feedback:** háptico al reconocer; "Leí: EAN 7908…, “KAIAK”" para que se entienda por qué eligió ese producto.

---

## 5. Arquitectura

```
Features (SwiftUI)
  ProductCameraScreen · RecognitionSheet (ficha + candidatos + botones) · acciones (reusa SyncEngine)
        │
Features/Shared/Photo (iOS)
  PhotoAnalyzer      Vision: barcodes + OCR (es) + feature print, en un solo paso
  PhotoReferenceStore  huellas por producto (SwiftData: ProductPhoto)
  RecognitionUploader  (opcional) multipart → POST /api/catalog/recognize
        │  señales
Core (solo Foundation)
  ProductRecognizer  naturaCodes(in:) · rank · resolve (reusa ProductMatcher / VoiceMatch)
  ProductActions     available(product, stock, openOrders, cart, draft) → [ProductAction]
```

- **Persistencia nueva:** `ProductPhoto { id, sellerId, productId, featurePrint: Data, createdAt, thumbnail?: Data }` (local, se puede borrar).
- **Backend (opcional, etapa P5):** `POST /api/catalog/recognize` (multipart JPEG) devuelve `{ candidates: [{ sellerProductId?, naturaSku, name, score, source }] }`. Reusa sharp y Tesseract del OCR de boletas y el índice de la revista del ciclo.
- **Permisos:** la cámara ya está en `project.yml` (`NSCameraUsageDescription`, conviene ampliar el texto: "…y reconocer productos"). La fototeca también.

---

## 6. Plan por etapas

| # | Etapa | Entregable |
|---|---|---|
| P1 | Núcleo | `ProductRecognizer` (`naturaCodes`, `rank`, `resolve`) y `ProductActions` en `Core`, con tests |
| P2 | Foto → ficha → acciones | `PhotoAnalyzer` (código de barras + OCR), hoja con candidatos y botones: inventario, asociar EAN, venta, pedido de cliente, recibir, ficha |
| P3 | Aspecto visual | Huellas `VNGenerateImageFeaturePrintRequest`, `ProductPhoto` y "aprender" al confirmar |
| P4 | Ráfaga y voz | Inventario de repisa foto a foto; comandos de voz en la ficha; Atajo "Foto de producto" |
| P5 | Servidor (opcional) | Endpoint de reconocimiento en el backend con la revista del ciclo; subir solo con conexión y permiso |

P1–P4 funcionan sin conexión y sin backend nuevo.

---

## 7. Riesgos

| Riesgo | Mitigación |
|---|---|
| Variantes casi iguales (Humor masculino/femenino, tamaños) | Código de barras y código Natura primero; ambigüedad explícita con selector; aprender por foto confirmada |
| OCR lee precios o fechas como códigos | Reglas en `naturaCodes` (paréntesis, "Cód.", largo 5–7, no EAN) y verificación contra catálogo y revista |
| Fotos con poca luz o reflejos (envases brillantes) | Lectura en vivo antes de disparar, flash/linterna, elegir otra foto |
| Pantalla chica | Ficha como hoja media, botones grandes en una columna, máx. 4 visibles y "Más…" |
| Acciones por error | Paso de confirmación, nada destructivo sin diálogo, "Registrar venta" separado |
| Espacio por fotos de referencia | Guardar solo la huella (KB); miniatura opcional y borrable |

---

## 8. Preguntas abiertas

1. ¿Los envases Natura muestran el código Natura (5–7 dígitos) en forma legible, o solo el EAN? Define cuánto pesan las señales 2 y 3.
2. ¿Cuántos productos del catálogo ya tienen EAN asociado? Si son la mayoría, P2 resuelve casi todo.
3. ¿Se quiere la señal 5 (subir la foto) desde el inicio, o basta con lo local?
4. Para "Agregar a pedido de cliente": ¿por defecto el último pedido en borrador o siempre elegir?
