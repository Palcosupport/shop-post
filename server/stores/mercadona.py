"""Mercadona scraper (tienda.mercadona.es public JSON API, no login).

Endpoints (the same ones the web shop calls):
    GET https://tienda.mercadona.es/api/categories/?lang=es&wh=<wh>
        -> top-level categories, each with its level-1 sub-categories
    GET https://tienda.mercadona.es/api/categories/<level1_id>/?lang=es&wh=<wh>
        -> level-2 sections with their full product listings (prices included)

    GET https://tienda.mercadona.es/api/products/<id>/?lang=es&wh=<wh>
        -> product detail (brand, EAN)

~150 category requests cover the whole catalogue (~4.3k products) in ~2 min.
Brand and EAN are only in the per-product endpoint. Fetching it for every
product would take ~50 min, so the brand is inferred from the display name
(Mercadona puts it there) and the detail is only fetched for products of
third-party brands (~1.1k requests, ~13 min): those are the ones whose EAN is
useful to match the same product in other supermarkets. Own brands (Hacendado,
Deliplus, ...) and unbranded fresh produce keep ean=None.
"""
import re
import sys
import os
from typing import Any, Dict, List, Optional

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from common import canonical_category, http_json, make_product  # noqa: E402

STORE = {"id": "mercadona", "name": "Mercadona", "color": "#00A650", "web": "https://tienda.mercadona.es"}
LIMIT = 0  # if >0, stop after roughly LIMIT products (for quick tests)
DETAILS = True  # fetch /products/<id>/ for third-party brands (exact brand + EAN)

API = "https://tienda.mercadona.es/api"
WAREHOUSE = "mad1"  # Madrid warehouse; prices are national but availability varies a little
PARAMS = {"lang": "es", "wh": WAREHOUSE}

# Store taxonomy (top level) -> canonical category id; sub-level overrides first.
_SUB_CAT = {
    "Embutido": "charcuteria-quesos",
    "Atún y otras conservas de pescado": "pescado",
    "Berberechos y mejillones": "pescado",
    "Harina y preparado repostería": "despensa",
    "Velas y decoración": "limpieza-hogar",
    "Aceitunas y encurtidos": "despensa",
}
_TOP_CAT = {
    "Aceite, especias y salsas": "despensa",
    "Agua y refrescos": "bebidas",
    "Aperitivos": "dulces-desayuno",
    "Arroz, legumbres y pasta": "despensa",
    "Azúcar, caramelos y chocolate": "dulces-desayuno",
    "Bebé": "bebe",
    "Bodega": "bebidas",
    "Cacao, café e infusiones": "dulces-desayuno",
    "Carne": "carne",
    "Cereales y galletas": "dulces-desayuno",
    "Charcutería y quesos": "charcuteria-quesos",
    "Congelados": "congelados",
    "Conservas, caldos y cremas": "despensa",
    "Cuidado del cabello": "higiene-belleza",
    "Cuidado facial y corporal": "higiene-belleza",
    "Fitoterapia y parafarmacia": "higiene-belleza",
    "Fruta y verdura": "fruta-verdura",
    "Huevos, leche y mantequilla": "lacteos-huevos",
    "Limpieza y hogar": "limpieza-hogar",
    "Maquillaje": "higiene-belleza",
    "Marisco y pescado": "pescado",
    "Mascotas": "mascotas",
    "Panadería y pastelería": "panaderia",
    "Pizzas y platos preparados": "preparados",
    "Postres y yogures": "lacteos-huevos",
    "Zumos": "bebidas",
}

# Mercadona own brands: no detail request needed (EAN useless for cross-store matching).
_OWN_BRANDS = {"Hacendado", "Deliplus", "Bosque Verde", "Compy", "Steinburg", "Casa Juncal", "Como tú", "Como Tú",
               "Delikuit"}

# Brands that are often not the last capitalised words of the display name.
_KNOWN_BRANDS = [
    "Hacendado", "Deliplus", "Bosque Verde", "Compy", "Casa Juncal", "Steinburg", "Como tú",
    "Solán de Cabras", "Fuente Dehesa", "Coca-Cola", "Pepsi", "Fanta", "Schweppes", "Monster Energy",
    "Red Bull", "Nestlé", "Danone", "Central Lechera Asturiana", "Pascual", "Puleva", "ColaCao",
    "Nescafé", "Marcilla", "Lavazza", "Gallo", "Barilla", "El Pozo", "ElPozo", "Campofrío", "Navidul",
    "Mahou", "San Miguel", "Estrella Galicia", "Estrella Damm", "Heineken", "Ambar", "Alhambra",
    "Font Vella", "Lanjarón", "Bezoya", "Aquarius", "Nestea", "Kas", "La Casera", "Pringles",
    "Lay's", "Oreo", "Kinder", "Milka", "Lindt", "Valor", "Ferrero", "Colgate", "Sanex", "Nivea",
    "Gillette", "Ariel", "Fairy", "Mimosín", "Evax", "Tampax", "Dodot", "Pantene", "H&S", "Garnier",
]
_KNOWN_RE = [(b, re.compile(r"(?<![\wÀ-ÿ])" + re.escape(b) + r"(?![\wÀ-ÿ])")) for b in _KNOWN_BRANDS]
_CAP = re.compile(r"^[A-ZÁÉÍÓÚÑÜ0-9][\wÁÉÍÓÚÑÜáéíóúñü'&.\-]*$")
_JOIN = {"de", "del", "la", "las", "los", "y", "&"}


def guess_brand(name: str) -> Optional[str]:
    """Mercadona embeds the brand in the display name ("Tomate frito Hacendado")."""
    hits = [(m.start(), b) for b, rx in _KNOWN_RE for m in [rx.search(name)] if m]
    if hits:
        return max(hits)[1]
    words = name.split()
    best: List[str] = []
    run: List[str] = []
    for i, w in enumerate(words):
        if i > 0 and _CAP.match(w) and not w[0].isdigit():
            run.append(w)
            best = list(run)
        elif run and w.lower() in _JOIN and i + 1 < len(words) and _CAP.match(words[i + 1]):
            run.append(w)
        else:
            run = []
    if not best:
        return None
    return " ".join(best[-3:]) or None


def _fmt_qty(value: Optional[float], fmt: Optional[str]) -> Optional[str]:
    if not value:
        return None
    fmt = (fmt or "").lower()

    def num(x: float) -> str:
        s = ("%.3f" % x).rstrip("0").rstrip(".")
        return s.replace(".", ",")

    if fmt == "kg":
        return "%s g" % num(value * 1000) if value < 1 else "%s kg" % num(value)
    if fmt == "l":
        if value < 1:
            cl = value * 100
            return "%s cl" % num(cl) if abs(cl - round(cl)) < 1e-6 else "%s ml" % num(value * 1000)
        return "%s L" % num(value)
    if fmt == "ud":
        return "%s ud" % num(value)
    if fmt == "m":
        return "%s m" % num(value)
    return "%s %s" % (num(value), fmt)


def _size(pi: Dict[str, Any]) -> Optional[str]:
    fmt = pi.get("size_format")
    units = pi.get("total_units")
    if pi.get("is_pack") and units and pi.get("pack_size"):
        return "%d x %s" % (int(units), _fmt_qty(pi["pack_size"], fmt))
    s = _fmt_qty(pi.get("unit_size"), fmt)
    if s and pi.get("approx_size"):
        s = "aprox. " + s
    if units and pi.get("unit_name") and fmt != "ud":
        extra = "%d %s" % (int(units), str(pi["unit_name"]).rstrip("."))
        s = "%s (%s)" % (s, extra) if s else extra
    elif units and pi.get("unit_name") and fmt == "ud" and (pi.get("unit_size") or 1) <= 1:
        s = "%d %s" % (int(units), str(pi["unit_name"]).rstrip("."))
    return s


_REF_UNIT = {"kg": "kg", "l": "L", "ud": "ud", "100 g": "100 g", "100 ml": "100 ml", "lv": "lavado",
             "dc": "docena", "dz": "docena", "m": "m"}


def _product(p: Dict[str, Any], top: str, sub: str, section: str) -> Optional[Dict[str, Any]]:
    pi = p.get("price_instructions") or {}
    price = pi.get("unit_price")
    prev = pi.get("previous_unit_price")
    prev = prev.strip() if isinstance(prev, str) else prev
    promo = None
    try:
        if prev and float(prev) > float(price):
            promo = "Ha bajado"
        else:
            prev = None
    except (TypeError, ValueError):
        prev = None
    name = p.get("display_name") or ""
    ref = (pi.get("reference_format") or "").lower()
    prod = make_product(
        STORE["id"], p.get("id"), name, price,
        brand=guess_brand(name),
        category=top,
        subcategory=sub,
        unit_price=pi.get("bulk_price"),
        unit=_REF_UNIT.get(ref, ref or None),
        size=_size(pi),
        image=p.get("thumbnail"),
        previous_price=prev,
        promo=promo,
        url=p.get("share_url") or "https://tienda.mercadona.es/product/%s/%s" % (p.get("id"), p.get("slug", "")),
    )
    if prod:
        prod["cat"] = _SUB_CAT.get(sub) or _TOP_CAT.get(top) or canonical_category(top, sub, section, name)
    return prod


def fetch() -> list:
    tree = http_json(API + "/categories/", PARAMS)
    out: Dict[str, Dict[str, Any]] = {}
    for top in tree.get("results", []):
        for sub in top.get("categories", []):
            if sub.get("published") is False:
                continue
            try:
                data = http_json("%s/categories/%d/" % (API, sub["id"]), PARAMS)
            except Exception as e:  # one broken category should not kill the run
                print("   mercadona: category %s failed: %s" % (sub.get("id"), e))
                continue
            for section in data.get("categories", []):
                for p in section.get("products", []):
                    if p.get("published") is False:
                        continue
                    sku = str(p.get("id"))
                    if sku in out:
                        continue
                    prod = _product(p, top.get("name", ""), data.get("name") or sub.get("name", ""),
                                    section.get("name", ""))
                    if prod:
                        out[sku] = prod
            if LIMIT and len(out) >= LIMIT:
                break
        if LIMIT and len(out) >= LIMIT:
            break
    if DETAILS:
        _add_details(list(out.values()))
    return list(out.values())


def _add_details(products: List[Dict[str, Any]]) -> None:
    """Exact brand + EAN for third-party-brand products (see module docstring)."""
    todo = [p for p in products if p["brand"] and p["brand"] not in _OWN_BRANDS]
    fails = 0
    for p in todo:
        try:
            d = http_json("%s/products/%s/" % (API, p["sku"]), PARAMS, retries=2)
        except Exception:
            fails += 1
            if fails > 50 and fails > len(todo) // 4:  # endpoint broken/blocked: keep what we have
                print("   mercadona: product details failing, skipping the rest")
                return
            continue
        brand = (d.get("brand") or (d.get("details") or {}).get("brand") or "").strip()
        if brand:
            p["brand"] = brand
        ean = str(d.get("ean") or "").strip()
        if ean.isdigit() and len(ean) in (8, 12, 13, 14) and not ean.startswith("2"):
            p["ean"] = ean
