"""Lidl Spain (www.lidl.es).

Lidl ES does not sell groceries online: www.lidl.es is an online shop for
non-food ("bazar") plus a showcase of the food items currently promoted in
the physical stores (weekly offers, "Super finde", permanent price cuts,
Deluxe, bakery, fresh produce...). There is no full grocery catalogue, so this
module collects the food / drugstore items the website exposes:

1. The site's own search API (``/q/api/search``, the one the search page
   uses) filtered to in-store products (``store=1``), keeping only food
   categories ("Food", "F+V" fruit & veg, "P+F" plants & flowers).
2. The in-store campaign pages linked from the home page (``/c/store/...``)
   plus the fresh food / bakery pages. Their product tiles carry the same JSON
   (``data-grid-data``) and include product variants not returned by search.
3. Optionally (``FETCH_EAN``) each product page, only to read the GTIN-13
   from its schema.org JSON-LD block.

Prices are the Peninsula/Baleares default region (regionsPrices "1"). When an
item is only discounted through the Lidl Plus app, the Lidl Plus price is used
as ``price`` with the regular price as ``previous_price`` and a "Lidl Plus"
promo label.
"""
import html
import json
import re
import sys
import os
import urllib.error
from typing import Any, Dict, List, Optional

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from common import canonical_category, dedupe, http_get, http_json, make_product  # noqa: E402

STORE = {"id": "lidl", "name": "Lidl", "color": "#0050AA", "web": "https://www.lidl.es"}
LIMIT = 0           # if >0, stop after roughly LIMIT products (quick tests)
FETCH_EAN = True    # fetch each product page once to read its EAN (GTIN-13)

BASE = "https://www.lidl.es"
SEARCH = BASE + "/q/api/search"
PAGE_SIZE = 60      # the API caps fetchsize at 60
FOOD_CATEGORIES = ("Food", "F+V", "P+F")
# Food pages that are not under /c/store/ (found in the site navigation).
EXTRA_PAGES = [
    "/c/frescos-frutas-y-verduras/s10089404",
    "/c/frescos-carne/s10089402",
    "/c/frescos-pescado/s10089403",
    "/c/panaderia/s10094507",
    "/c/megaprecios-lidl-compara-articulos-calidad-precio/s10089417",
]
FALLBACK_CAMPAIGNS = [
    "/c/store/ofertas-semanales/a10089449",
    "/c/store/super-finde/a10089450",
    "/c/store/bajadas-permanentes/a10089468",
    "/c/store/precios-imbatibles/a10096147",
    "/c/store/deluxe/a10089612",
    "/c/store/tus-otras-marcas-de-siempre/a10089613",
]


# ---------------------------------------------------------------------------
# Parsing helpers
# ---------------------------------------------------------------------------
_SIZE_RE = re.compile(r"(?:(\d+)\s*x\s*)?(\d+(?:[.,]\d+)?)\s*/?\s*(kg|g|gr|mg|l|ml|cl|ud|uds)\b", re.I)
_BASE_RE = re.compile(r"(\d+(?:[.,]\d+)?)\s*€\s*/\s*(kg|l|ud|100\s*g|100\s*ml)", re.I)


def _size_qty(text: Optional[str]):
    """'6x125 g' -> (0.75, 'kg'); '33 cl' -> (0.33, 'L'); None if unparseable."""
    if not text:
        return None
    m = _SIZE_RE.search(text.replace("\xa0", " "))
    if not m:
        return None
    n = int(m.group(1)) if m.group(1) else 1
    q = float(m.group(2).replace(",", "."))
    u = m.group(3).lower()
    if u in ("g", "gr"):
        return n * q / 1000.0, "kg"
    if u == "mg":
        return None
    if u == "kg":
        return n * q, "kg"
    if u == "ml":
        return n * q / 1000.0, "L"
    if u == "cl":
        return n * q / 100.0, "L"
    if u == "l":
        return n * q, "L"
    return n * q, "ud"


def _clean_size(text: Optional[str]) -> Optional[str]:
    if not text:
        return None
    s = re.sub(r"\s+", " ", text.replace("\xa0", " ")).strip()
    s = re.sub(r"(\d)\s*/\s*(g|kg|ml|l)\b", r"\1 \2", s)       # "200/g" -> "200 g"
    s = re.sub(r"(\d)(kg|g|ml|cl|l)\b", r"\1 \2", s)            # "400g" -> "400 g"
    s = re.sub(r"(?i)^aprox[.\s]*", "aprox. ", s)
    if s.lower() in ("ud", "paquete", "unidad"):
        return None
    return s


def _region_price(g: Dict[str, Any]) -> Dict[str, Any]:
    rp = g.get("regionsPrices") or {}
    if not isinstance(rp, dict) or not rp:
        return {}
    return rp.get("1") or rp[sorted(rp)[0]] or {}


def _price_info(g: Dict[str, Any]):
    """Return (price, previous, promo, packaging, base_text) or None."""
    reg = _region_price(g)
    cur = reg.get("currentPrice") or {}
    lp = reg.get("currentLidlPlusPrice") or {}
    lp_price = lp.get("price") or {}
    # Search results also mirror the default price at gridbox level.
    top = g.get("price") or {}
    if not cur.get("price") and top.get("price"):
        cur = top
    if not lp_price.get("price"):
        for item in g.get("lidlPlus") or []:
            if (item.get("price") or {}).get("price"):
                lp_price = item["price"]
                break

    if cur.get("price"):
        price = cur["price"]
        disc = cur.get("discount") or {}
        prev = disc.get("deletedPrice") or cur.get("oldPrice")
        promo = (disc.get("discountText") or "").strip()
        if not promo and prev and disc.get("percentageDiscount"):
            promo = "-%s%%" % disc["percentageDiscount"]
        if lp_price.get("price") and lp_price["price"] < price:
            lp_txt = "Lidl Plus %s €" % ("%.2f" % lp_price["price"]).replace(".", ",")
            promo = (promo + " · " + lp_txt) if promo else lp_txt
        if prev and not promo:
            promo = "Oferta"
        src = cur
    elif lp_price.get("price"):
        price = lp_price["price"]
        disc = lp_price.get("discount") or {}
        prev = disc.get("deletedPrice") or lp_price.get("oldPrice")
        extra = (disc.get("discountText") or lp.get("highlightText") or "").strip()
        if not extra and disc.get("percentageDiscount"):
            extra = "-%s%%" % disc["percentageDiscount"]
        promo = "Lidl Plus" + (" " + extra if extra else "")
        src = lp_price
    else:
        return None
    pack = (src.get("packaging") or {}).get("text") or (top.get("packaging") or {}).get("text")
    base = (src.get("basePrice") or {}).get("text") or (top.get("basePrice") or {}).get("text")
    return price, prev, promo, pack, base


def _category(g: Dict[str, Any]):
    won = ((g.get("keyfacts") or {}).get("wonCategoryPrimary") or "").split("/")
    # "Mundos de necesidad/Comida y cerca de la comida/<category>/<subcategory>"
    cat = won[2] if len(won) > 2 else None
    sub = won[3] if len(won) > 3 else None
    if cat == "Presupuesto":       # Lidl's "budget" bucket: use the subcategory instead
        cat, sub = sub, None
    if not cat:
        cat = {"F+V": "Frutas y hortalizas", "P+F": "Flores y plantas"}.get(g.get("category") or "")
    return cat, sub


# Lidl "need world" categories -> app canonical categories.
_CAT_MAP = {
    "Frutas y hortalizas": "fruta-verdura",
    "Carne y aves": "carne",
    "Pescado y marisco": "pescado",
    "Quesos, productos lácteos y huevos": "lacteos-huevos",
    "Panadería": "panaderia",
    "Reservas de alimentos": "despensa",
    "Aceites, especias y salsas": "despensa",
    "Muesli y untables": "dulces-desayuno",
    "Café, té y cacao": "dulces-desayuno",
    "Dulces y aperitivos": "dulces-desayuno",
    "Alimentos congelados": "congelados",
    "Bebidas": "bebidas",
    "Cerveza y sidra": "bebidas",
    "Vino": "bebidas",
    "Champán, vino espumoso & Co.": "bebidas",
    "Licores": "bebidas",
    "Platos precocinados": "preparados",
    "Productos de droguería y cuidado personal": "higiene-belleza",
    "Productos de limpieza": "limpieza-hogar",
    "Limpieza del hogar": "limpieza-hogar",
    "Papel higiénico": "limpieza-hogar",
    "Artículos para mascotas": "mascotas",
    "Artículos para gatos": "mascotas",
    "Artículos para perros": "mascotas",
    "Bebés y niños": "bebe",
    "Flores y plantas": "otros",
}
_SUB_MAP = {"Queso": "charcuteria-quesos", "Embutidos y fiambres": "charcuteria-quesos"}


def _canonical(cat: Optional[str], sub: Optional[str], name: str, default: str) -> str:
    c = _SUB_MAP.get(sub or "") or _CAT_MAP.get(cat or "")
    if c == "carne" and canonical_category(name) == "charcuteria-quesos":
        c = "charcuteria-quesos"   # cured meats filed as "Carne de cerdo"
    return c or default


def _is_food(g: Dict[str, Any]) -> bool:
    return (g.get("category") or "") in FOOD_CATEGORIES


def _build(g: Dict[str, Any]) -> Optional[Dict[str, Any]]:
    info = _price_info(g)
    if not info:
        return None
    price, prev, promo, pack, base = info
    brand = ((g.get("brand") or {}).get("name") or "").replace("®", "").replace("™", "").strip()
    name = (g.get("fullTitle") or (g.get("keyfacts") or {}).get("fullTitle") or g.get("title") or "")
    name = re.sub(r"^\s*-\s+", "", name.replace("®", "").replace("™", ""))
    if brand in ("-", "--"):
        brand = ""
    cat, sub = _category(g)
    size = _clean_size(pack)

    unit_price, unit = None, None
    if base:
        m = _BASE_RE.search(base)
        if m:
            unit_price, unit = m.group(1), re.sub(r"\s+", " ", m.group(2).lower())
    if unit_price is None:
        q = _size_qty(pack)
        if q and q[0] > 0:
            unit_price, unit = float(price) / q[0], q[1]
        elif (pack or "").strip().lower() in ("ud", "unidad"):
            unit_price, unit = price, "ud"

    url = g.get("canonicalUrl") or g.get("canonicalPath")
    if url and url.startswith("/"):
        url = BASE + url
    image = g.get("image") or ((g.get("imageList") or [None])[0])
    if image and image.startswith("/"):
        image = BASE + image
    p = make_product(STORE["id"], g.get("erpNumber") or g.get("productId"), name, price,
                     brand=brand or None, category=cat, subcategory=sub,
                     unit_price=unit_price, unit=unit, size=size, image=image,
                     previous_price=prev, promo=promo, url=url)
    if p:
        p["cat"] = _canonical(cat, sub, name, p["cat"])
    return p


# ---------------------------------------------------------------------------
# Sources
# ---------------------------------------------------------------------------
def _search_items() -> List[Dict[str, Any]]:
    out: List[Dict[str, Any]] = []
    offset, total = 0, None
    while total is None or offset < total:
        d = http_json(SEARCH, {"assortment": "ES", "locale": "es_ES", "version": "v2.0.0", "q": "*",
                               "store": "1", "offset": offset, "fetchsize": PAGE_SIZE})
        items = d.get("items") or []
        total = d.get("numFound") or 0
        if not items:
            break
        for it in items:
            g = (it.get("gridbox") or {}).get("data") or {}
            if g and _is_food(g):
                out.append(g)
        offset += PAGE_SIZE
        if LIMIT and len(out) >= LIMIT:
            break
    return out


_GRID_RE = re.compile(r'data-grid-data="([^"]*)"')


def _page_items(path: str) -> List[Dict[str, Any]]:
    try:
        s = http_get(BASE + path, headers={"Accept": "text/html"}).decode("utf-8", "replace")
    except (urllib.error.HTTPError, RuntimeError) as e:
        print("   lidl: skip %s (%s)" % (path, e))
        return []
    out = []
    for raw in _GRID_RE.findall(s):
        try:
            g = json.loads(html.unescape(raw))
        except ValueError:
            continue
        if isinstance(g, dict) and _is_food(g):
            out.append(g)
    return out


def _campaign_paths() -> List[str]:
    try:
        s = http_get(BASE + "/", headers={"Accept": "text/html"}).decode("utf-8", "replace")
        paths = sorted(set(re.findall(r'href="(/c/store/[a-z0-9-]+/a\d+)"', s)))
    except Exception:
        paths = []
    paths = [p for p in paths if "proxima-semana" not in p and "jardin" not in p] or FALLBACK_CAMPAIGNS
    return paths + [p for p in EXTRA_PAGES if p not in paths]


_GTIN_RE = re.compile(r'"gtin13"\s*:\s*\[?\s*"(\d{8,14})"')


def _fetch_ean(url: str) -> Optional[str]:
    try:
        s = http_get(url, headers={"Accept": "text/html"}, retries=2).decode("utf-8", "replace")
    except Exception:
        return None
    m = _GTIN_RE.search(s)
    # Codes starting with 2 are in-store variable-weight codes, not real EANs.
    return m.group(1) if m and not m.group(1).startswith("2") else None


def _head_erp(erp: str) -> str:
    # Variants are "<8-digit head erp><3-digit variant>" (e.g. 11137319004).
    return erp[:8] if len(erp) == 11 and erp.startswith("1") else erp


def fetch() -> list:
    grids: List[Dict[str, Any]] = _search_items()
    if not (LIMIT and len(grids) >= LIMIT):
        for path in _campaign_paths():
            grids.extend(_page_items(path))
            if LIMIT and len(grids) >= LIMIT:
                break

    products: List[Dict[str, Any]] = []
    heads = set()
    # Prefer the head product; keep only one variant per head when no head is listed.
    grids.sort(key=lambda g: len(str(g.get("erpNumber") or "")))
    for g in grids:
        erp = str(g.get("erpNumber") or g.get("productId") or "")
        if not erp:
            continue
        h = _head_erp(erp)
        if h in heads:
            continue
        p = _build(g)
        if p:
            heads.add(h)
            products.append(p)
    products = dedupe(products)
    if LIMIT:
        products = products[:LIMIT]

    if FETCH_EAN:
        for p in products:
            if p.get("url"):
                ean = _fetch_ean(p["url"])
                if ean:
                    p["ean"] = ean
    return products
