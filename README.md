# Shop Post

App de lista de la compra para iPhone (SwiftUI, iOS 27) con los productos y precios reales de los supermercados,
cesta compartida por iCloud, despensa/nevera, comparación de precios, ofertas, bajadas y alertas.
Funciones inspiradas en QuéFalta e interfaz inspirada en Closet AI, con nombre, icono y marca propios.

## Estructura

| Carpeta | Qué hay |
|---|---|
| `ShopPost/` | Código de la app (SwiftUI + Core Data/CloudKit). |
| `ShopPost.xcodeproj` | Proyecto de Xcode (las carpetas se sincronizan solas). |
| `Config/` | `Info.plist` y entitlements (iCloud/CloudKit, notificaciones). |
| `server/` | Lectores de catálogos en Python (solo librería estándar). |
| `docs/data/` | JSON publicados por GitHub Pages; los descarga la app. |
| `.github/workflows/scrape.yml` | Ejecución diaria del servidor en GitHub Actions. |

## Pantallas

- **Inicio**: cesta activa, «Falta en casa», Ofertas, Cambios de precio, Novedades, Favoritos, bajadas destacadas, alertas e historial.
- **Catálogo**: búsqueda en todos tus supermercados o en uno, categorías, ordenar por precio o €/kg, cuadrícula o lista.
- **+ (Añadir)**: buscar, escanear código de barras (VisionKit + Open Food Facts), escribir a mano, guardar en la despensa, repetir una compra.
- **Cesta**: grupos (Casa, Piso…), compartir con iCloud, agrupada por supermercado y categoría, recogido, notas, sustitutos,
  «No estaba en la tienda», asignar a un miembro, total estimado y «¿Dónde sale más barata?».
- **Despensa**: Despensa / Nevera / Congelador con baldas, cantidades, caducidad y «Qué falta» → a la cesta.
- **Perfil** (botón de la cabecera de Inicio): supermercados favoritos, alertas, favoritos, grupos y ajustes.

## Supermercados

| Tienda | Estado | Productos aprox. |
|---|---|---|
| Mercadona | Funciona (API pública de tienda.mercadona.es) | 4.350 |
| Consum | Funciona (API pública de tienda.consum.es) | 9.300 |
| Lidl | Funciona, pero lidl.es solo muestra unos 220 productos de alimentación (ofertas y gamas fijas) | 220 |
| Eroski | Funciona (páginas públicas de supermercado.eroski.es); sin código de barras | 24.500 |
| Dia | Bloqueado por Akamai (HTTP 403): desactivado | — |
| Alcampo | La API responde, pero AWS WAF bloquea tras 5–6 peticiones: desactivado | — |
| Carrefour | Bloqueado por Cloudflare: desactivado | — |

Solo se usan las URL públicas que usa la propia web de cada tienda, sin iniciar sesión y sin saltarse protecciones
antibots. Si una tienda falla, se conservan sus últimos datos y la app lo indica en *Perfil → Acerca de*.
Revisa las condiciones de uso de cada web antes de publicar la app.

## Puesta en marcha

### 1. Servidor (GitHub Actions + Pages)

1. Crea un repositorio en GitHub (p. ej. `shop-post`) y sube esta carpeta.
2. En *Settings → Pages*: *Deploy from a branch*, rama `main`, carpeta `/docs`.
3. En *Settings → Actions → General → Workflow permissions*: *Read and write permissions*.
4. En *Actions → Actualizar precios → Run workflow* lánzalo la primera vez (tarda una hora aprox.; luego corre cada día a las 04:30 UTC).
5. Los datos quedarán en `https://<usuario>.github.io/<repo>/data/`. La app ya apunta a `https://palcosupport.github.io/shop-post/data/`; si cambias de repositorio, cámbiala en
   `CatalogService.defaultDataURL` (`ShopPost/Services/CatalogService.swift`) o en la app, *Ajustes → Datos de precios*.

Prueba local:

```bash
python3 server/run.py --limit 100 mercadona consum   # rápido
python3 server/run.py                                # completo
cd docs && python3 -m http.server 8765               # el simulador lee http://localhost:8765/data/
```

### 2. App (Xcode)

1. Abre `ShopPost.xcodeproj` con Xcode 27.
2. *Signing & Capabilities*: elige tu equipo de pago. El contenedor de iCloud es `iCloud.com.shoppost.app`
   (créalo si Xcode lo pide) y el bundle ID `com.shoppost.app` (cámbialos si ya existen).
3. Ejecuta en un iPhone o simulador. En el simulador (Debug) la app lee los datos de `http://localhost:8765/data/`.
4. Para compartir grupos hacen falta dos cuentas de iCloud reales; la primera vez, despliega el esquema de CloudKit
   a producción desde CloudKit Console antes de publicar en TestFlight/App Store.

## Pendiente / ideas

- Más supermercados: Dia, Alcampo y Carrefour si dejan de bloquear (los módulos ya existen).
- Historial de precios por producto (el servidor ya guarda `server/history/`).
- Widget de la cesta y avisos push cuando otro miembro cambia la cesta.
