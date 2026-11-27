# Referencia técnica — Integración con Natura

> **Para qué:** portar a la app (M3, `local-first-migration.md`) todo lo que hoy hace el backend con Natura, sin tener que leer su código. Recoge lo implementado en el repo `mynatura` (`backend/src/modules/natura-integration/`) y lo verificado con las capturas de `docs/har/` y `docs/xlsx/`. Esas carpetas son locales y no se versionan.
> **Reglas:** aquí van rutas, encabezados, nombres de campos y reglas de lectura. **Nunca** valores: ni claves, ni `client_id`, ni tokens, ni datos personales. Las claves públicas se **leen en vivo** de los bundles de Natura, como ya hace el backend.
> Verificado el 2026-11-26/27. Natura puede cambiar todo esto sin aviso.

---

## 0. Panorama

| Sistema | Host | Para qué | Autenticación |
|---|---|---|---|
| **natura-auth** (Cognito) | `natura-auth.prd.naturacloud.com` (página) · `authenticator-cognito-apigw.prd.naturacloud.com` (API) | Login | `x-api-key` pública (del bundle) |
| **minegocio** | `minegocio.natura.cl` | Pedidos, líneas, Excel del pedido, cuentas, home | Cookie `wcmn_session` |
| **GSP** | `gsp.natura.com` (app) · `gsp-apigw-mfe.prd.naturacloud.com/graphql/frontend/graphql` | Pedido nuevo: catálogo del ciclo, canasta, carro, ciclo, crédito | `Authorization: Bearer <accessToken>` + `x-app-token` |
| **Revista digital** | `cl.natura.digital-catalogue.com` · `api.smg.natura.digital-catalogue.com` | Revista del ciclo (páginas, textos, PDF), precio sugerido | Pública |

- **Akamai** protege minegocio y la API de login. Si responde **403 o 429** con `server: AkamaiGHost` o un cuerpo con "Access Denied" / "Reference&#32;#" / `errors.edgesuite.net`, es un bloqueo: informar y reintentar más tarde. Sin Playwright.
- **User-Agent** de escritorio en todas las llamadas (el backend usa un Chrome de macOS).

---

## 1. Login (natura-auth → minegocio)

### 1.1 Configuración (en vivo)
1. `GET <URL de login>`: la página de natura-auth con `?client_id=…&country=cl&language=es&company=natura&redirect_uri=https://minegocio.natura.cl/natura-callback?return_url=`. El `client_id` de minegocio es público, pero no se versiona aquí; está en la configuración del backend (`NATURA_LOGIN_URL`).
2. Del HTML se toma el bundle `src="/assets/index-<hash>.js"` y del bundle:
   - `VITE_APP_API_DOMAIN:"…"` → `apiDomain` (incluye `/authentication-api`);
   - `VITE_APP_API_TOKEN:"…"` → `x-api-key`.
   
   Caché de 30 min.

### 1.2 `POST {apiDomain}/signin`
- **Encabezados:** `content-type: application/json`, `accept: application/json`, `x-api-key`, `origin` y `referer` = la página de login, `user-agent`.
- **Cuerpo:**
```json
{ "clientId": "<client_id de la URL>", "country": "cl", "company": "natura",
  "username": "<usuario normalizado>", "password": "<cifrada>",
  "recaptchaToken": "disabled", "redirectUrl": "https://minegocio.natura.cl/natura-callback?return_url=",
  "document": "personCode" }
```
- **Usuario normalizado:** si es un email, `trim`; si es un código o documento, quitar puntos, guiones y espacios.
- **Cifrado de la contraseña** = `CryptoJS.AES.encrypt(password, username)`, que equivale a:
  - salt aleatorio de 8 bytes;
  - `EVP_BytesToKey` con **MD5**: concatenar `MD5(prev ‖ passphrase ‖ salt)` hasta tener 48 bytes, de los que key = 32 e IV = 16;
  - **AES-256-CBC** con relleno PKCS7;
  - salida = base64(`"Salted__"` ‖ salt ‖ cifrado).
  
  En iOS: CommonCrypto (`CCCrypt` + `CC_MD5`, o `Insecure.MD5` de CryptoKit).
- **Respuesta 200:** `{ sso_token, authToken, challengeRequired, daysExpirePassword, … }`. A veces viene `code`/`state` en lugar de `sso_token`.
  - Si `challengeRequired: true`, Natura pide un paso adicional: mostrar "Ingresa una vez en minegocio y vuelve a intentar".
  - **El `sso_token` es el que sirve** para minegocio y para GSP. El `authToken` **no** sirve para GSP (verificado).
- **Errores 4xx:**
  - 401, o un mensaje que coincide con `/password|contrase|senha|incorrect|not ?authorized|unauthori[sz]ed|user.*(not|no).*(found|exist)|usuario|usu[aá]rio|attempt|intento|tentativa|bloque|locked|disabled/i` → **credenciales rechazadas**. No reintentar, para no bloquear la cuenta.
  - Otro 4xx → probable cambio de API.

### 1.3 Sesión de minegocio
- `GET https://minegocio.natura.cl/natura-callback?return_url=&sso_token=<sso_token>` (o `code`/`state`).
- Seguir las redirecciones **a mano** (máx. 8, `redirect: manual`), juntando `Set-Cookie`: se descartan las vencidas (`max-age=0` / `expires=Thu, 01-Jan-1970`) y las vacías.
- Al final debe existir la cookie **`wcmn_session`**. Las llamadas siguientes llevan `cookie: nombre=valor; …`.
- En iOS: `URLSession` efímera, con `HTTPCookieStorage` propio por sesión y delegado que no siga redirecciones solo.

---

## 2. minegocio (con `wcmn_session`)

Encabezados XHR: `accept: */*`, `referer: https://minegocio.natura.cl/pedidos`, `x-requested-with: XMLHttpRequest`, `cookie`, `user-agent`.

### 2.1 Lista de pedidos
- `GET /pedidos/ajax/orders/{codigoConsultora}/{isOrderGroup=0}?page={n}&pageSize=25&orderId=` (opcional `statusIds[]`).
- **Respuesta:** array de `{ id, orderNumber, cycle, subCycle, orderingDate, deliveryDate, totalValue, totalPoints, itemsQuantity, invoiceNumber, approvalDueDate, orderDueDate, orderPaymentStatus, orderCycleDay, channelId, structureCode, user, status { id, name }, … }`.
- **Paginación:** si la página trae menos de `pageSize`, es la última.
- **Entregados:** `status.name` en minúsculas == `"entregado"`.
- **Idempotencia:** por `id` (`externalOrderId`).
- **Ciclo:** si `cycle ≥ 10000` viene como `AAAACC`; si no, el año sale de `deliveryDate` (o `orderingDate`).
- `totalValue` es texto ("$123.456"): quitar puntos y todo lo que no sea dígito.

### 2.2 Excel del pedido (fuente principal de cada línea)
- `GET /pedidos/order-report/{number}` → **XLSX**. `{number}` es el número largo del pedido (en la plantilla de la página, `{{:number}}`; en la lista, el campo correspondiente, a confirmar al implementar). Disponible en **todos** los pedidos.
- **Formato** (una hoja, celdas `t="str"`, sin `sharedStrings`, con celdas combinadas):
  - **Fila 2:** `CONSULTOR/A` · nombre (código) · `PEDIDO` · n.º · `CICLO` · `CC/AAAA` · `FECHA` · `DD-MM-AAAA`.
  - **Encabezado:** `Cant.` · `Código` · `Descriptions` · (2 vacías) · `Marca` · `Precio revista (uni.)` · `Precio revista (total)` · `Precio CB (total)` · `Ganancia (total)`.
  - **Una fila por línea;** al final `Total por marca`, `AVON / C&E`, `NATURA` y `TOTALES`.
- **Reglas:**
  - costo unitario = `Precio CB (total)` / `Cant.`; precio sugerido = `Precio revista (uni.)`;
  - **excluir** `TASA DE SERVICIO` (`Código` = `1`, todo en 0);
  - las promociones traen costo = sugerido;
  - costo 0 con sugerido > 0 = gratis de Natura.
- **ZIP con CRC inválidos:** leerlo con un lector propio que **no valide CRC**. Central directory → entradas → deflate crudo con `Compression` (`COMPRESSION_ZLIB`). Luego `XMLParser` sobre `xl/worksheets/sheet1.xml`.

### 2.3 Líneas en HTML (respaldo del costo)
- `GET /pedidos/items/{id}/{orderNumber}?from=pedidos` (`accept` de HTML, sin XHR).
- **Tabla:** `<tbody id="order-items-list">…</tbody>` → filas `<tr>` → celdas `<td>`. Texto sin etiquetas, con `&nbsp;` → espacio y espacios colapsados.
- **Celdas por posición:**

| Celda | Contenido | Uso |
|---|---|---|
| 0 | `Código: …` | SKU (quitar "#") |
| 1 | `Puntos: …` | Puntos |
| 2 | — | Nombre |
| 3 | `Cantidad: …` | Cantidad |
| 4 | `Tipo: …` | Tipo (p. ej. "Regalo") |
| 5 | `Valor unitario: …` | Costo unitario; "-" = gratis |
| 6 | `Total Puntos: …` | Puntos totales |
| 7 | `Total Neto: …` | Total neto |

- Números: quitar puntos y todo lo que no sea dígito o signo; "-" = nulo.
- Si no está la tabla, el formato cambió: error `missing_order_items_table`.

### 2.4 Otros
- **Cuentas y vencimientos:** `GET /pedidos/ajax/mis-cuentas?order=…&state=…` → `[{ number, orderingNumber, isOpen, isOverdue, issueDate, dueDate, originalValue, currentBalance, overdueDays, orderStatus }]`. Falta confirmar qué `state` filtra lo pendiente.
- **Boleta:** `/pedidos/mis-cuentas/{orderNumber}` ("Ver Boleta", PDF en la página).
- **Exportar todos los pedidos:** `/pedidos/export-orders/{codigoConsultora}/0` ("Exportar Excel", formato no revisado).
- **Ciclo vigente (número):** el HTML de `GET /home` trae `var query_cycle = [AAAACC];`.
- **Tarjetas del home:** `GET /cards` → `{ response: { cards: [{ category, dateStart, dateEnd, metadata, priority, … }] } }`.
- **Enlace a GSP:** "Nuevo Pedido" = `https://gsp.natura.com/login?country=CL` (`target=_blank`, sin token).

---

## 3. GSP (pedido nuevo, ciclo, crédito, ofertas)

### 3.1 Configuración (en vivo)
- `GET https://gsp.natura.com/` → bundle `src="/static/js/static/js/index.<hash>.js"`. Del bundle:
  - `COGNITO_CLIENT_ID`;
  - `COGNITO_X_API_KEY`;
  - `COGNITO_SERVICE_API_URL` (host de la API de login);
  - `COGNITO_REDIRECT_URI` (`https://gsp.natura.com`);
  - `GSP_GRAPHQL_URL`.
  
  Otros presentes: `SHOWCASE_GRAPHQL_URL`, `COGNITO_SERVICE_URL` y `MFE_GSP_URL`.

### 3.2 `POST {COGNITO_SERVICE_API_URL}/authentication-api/recover-session`
- **Encabezados:** `x-api-key` (la de GSP), `content-type: application/json`, `origin`/`referer` `https://gsp.natura.com`.
- **Cuerpo:** `{ "token": "<sso_token del signin>", "redirectUrl": "<COGNITO_REDIRECT_URI>", "clientId": "<COGNITO_CLIENT_ID>" }`.
- **Respuesta:** `{ accessToken, idToken, expiresIn }`. JWT de Cognito, de 6 h. El `idToken` trae `natura_code`, `personId`, `gsp_profiles`, `country`, …

### 3.3 GraphQL
- `POST <GSP_GRAPHQL_URL>` con `{ operationName, query, variables }` y encabezados:
  - **siempre:** `authorization: Bearer <accessToken>`, `x-app-token: <xAppToken actual>`, `content-type: application/json`, `accept: */*`, `origin`/`referer` `https://gsp.natura.com`;
  - **operaciones de perfil:** `operation: <operationName>` y `sessionidentifier: ""`;
  - **el resto:** `application: WEB`, `country: CL` y `http_username: <personCode>`, que viene en `profileGetPersonData.payload.personCode`.
- **Obtener el `xAppToken`** (encadenado; cada respuesta trae uno nuevo que va en la siguiente):
```graphql
query authPersonData($personID: String, $fullTokens: Boolean, $channelId: ID) {
  profileGetPersonData(personID: $personID fullTokens: $fullTokens channelId: $channelId) {
    xAppToken payload { personCode countryCode isBlocked } } }
# variables: { personID: null, channelId: 1, fullTokens: false }   · x-app-token vacío

query profileOtherCycles($businessModelId: Int, $roleId: Int, $functionId: Int) {
  profileGetOtherCycles(businessModelId: $businessModelId roleId: $roleId functionId: $functionId) {
    xAppToken payload { personData { currentCycle { cycleCode dateStart dateEnd orderDate } } } } }
# variables: { roleId: 1, functionId: 1, businessModelId: 1 }

query authCommercialInfo($businessModelId: Int, $systemId: Int, $showcaseAccess: Boolean, $channelId: Int) {
  profileGetCommercialInfo(businessModelId: $businessModelId systemId: $systemId showcaseAccess: $showcaseAccess channelId: $channelId) {
    xAppToken payload { isBlocked credit { available limit additional } } } }
# variables: { channelId: 1, showcaseAccess: true, businessModelId: 1, systemId: 1 }   → xAppToken final (~3400)
```
- **Ciclo actual con fechas:**
```graphql
query consultantSection { consultantSection {
  actualCycle { number label startDate endDate year status remainingDays orderDate } } }
```
  Verificado: `{ number: 19, year: 2026, startDate: 2026-11-26…, endDate: 2026-12-09…, remainingDays: 13, status: CURRENT }`.
- **Catálogo del ciclo y ofertas:** `cardSection(context, cycle, category, page, filterOptions{productCategories, productLines}, lastPromotionCodes)` → `cards[{ code, name, description, brand, image, categories, points, purchasePrice, resalePrice, promotionSummary, gifts, discountTag, percentageDiscount, stockStatus, products[…], type }]`, `totalItens`, `totalPages`. El texto exacto de la consulta está en la captura `gsp.natura.com.har` (local).
- **Canasta y carro** (no implementado; leer, no confirmar):
  - `syncBasket{cycle}` → `{ total, cartId, shouldRedirectToCart }`;
  - `addProductsToCart{products[{code, quantity, itemTypeId}], context, cycle, cartId, version, tags, origin}`;
  - `getCart{cycle, version}` → puntos, totales y tope;
  - `sendBasketOrder{context, cycle, version, cycleType}` (canasta → carro, **no confirma**);
  - `CartGet{cartUid, …}`, `CartRemoveItem` (persisted query), `CartStatus`.
  - **El checkout no está capturado.**
- **Renovar:** `profileGetRefreshToken` (GET) → `payload.credit`, `isBlocked` y `xAppToken`.

---

## 4. Revista digital (pública)

- **Visor:** `https://cl.natura.digital-catalogue.com/consultoria/cl/{AAAA}/{CC}/revista/ciclo-{CC}/view/index.html?id_consultora={código}&utm_term=web`. Solo unos 4 ciclos en línea; los antiguos dan 404.
- **Páginas:** en el HTML, `var INIT_DATA = {…};`, con `pages.list[].filename` (`'0001'` o `"0001"`, cuatro dígitos), `config.template.cycle` y `year`.
- **Por página** (relativas a `…/view/`):
  - `common/data/{NNNN}.json` → `{ paragraphs: [{ id, x, y, text }] }`;
  - `{NNNN}.webp` (imagen) y `{NNNN}.pdf`.
  - **Revista completa:** `common/data/catalogue.pdf` (~46 MB).
- **Precio sugerido por SKU** (heurística del backend; ancho de página 1080):
  1. SKUs = `/\((\d{5,7})\)/g` en cada párrafo.
  2. Párrafos "candidatos a precio": contienen `precio revista( del ciclo)?`, `precio regular`, `a solo`, `de:? $N.NNN` o `$N.NNN`.
  3. **Precio directo del párrafo del SKU:**
     - si dice "precio revista", "precio regular" o "a solo", el primer `$N.NNN`;
     - si no, `de:? $N.NNN` o `a solo $N.NNN`.
  4. Si no hay: mismo **lado** de la página (x < 540 o ≥ 540), candidatos con `y` entre `y-40` y `y+380`, ordenados por cercanía en `y`; el primero con precio.
  5. Si no hay: la etiqueta "precio revista" del mismo lado más cercana hacia abajo, y el primer `$N.NNN` entre su `y` y `y+90`.
  6. Por SKU queda el **primer** precio encontrado al recorrer las páginas.
- **API de productos de la revista** (`api.smg.natura.digital-catalogue.com/search/consultoria/products/…?campaign_id&brochure_id&agent`): los ids no son el ciclo ni el `uid`; **sin resolver**.

---

## 5. Reglas de import (como el backend, con los cambios del plan)

- **Producto:** clave = SKU normalizado (quitar "#" y espacios; comparar en minúsculas). Marca = primera palabra del nombre (backend) o columna `Marca` del Excel.
- **Lote:** uno por línea entregada, con costo y sugerido del Excel. Clasificación por valor (`local-first-migration.md` §4.3).
- **Vendible:** las líneas de revista, catálogo o carta no son vendibles (`/revista|catalog|cat[aá]logo|carta/i` en el nombre). Un producto que llega primero gratis no es vendible (plan §4.3).
- **Idempotencia:** pedido por `id`; línea por (pedido, posición o código).

---

## 6. Pendiente de capturar o confirmar
- El campo exacto de la lista de pedidos que corresponde a `{number}` del Excel.
- `mis-cuentas`: valores de `state`.
- Checkout de GSP (confirmar pedido).
- Ids de la API de productos de la revista.
- Formato de "Exportar Excel" (todos los pedidos).
