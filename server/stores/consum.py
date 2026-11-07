"""Consum scraper (tienda.consum.es public JSON API, no login).

Endpoints (the same ones the web shop's Angular app calls):
    GET https://tienda.consum.es/api/rest/V1.0/shopping/category/menu
        -> full category tree (used to resolve each product's leaf category
           into "top > level-2" store taxonomy)
    GET https://tienda.consum.es/api/rest/V1.0/catalog/product
            ?limit=100&offset=<n>&orderById=5&showRecommendations=false
        -> whole catalogue, paginated (max 100 per page; totalCount/hasMore).
           Includes EAN, brand, prices, offer price, unit price, offers.

~95 requests for the full catalogue (~9.3k products), ~1.5 min.
"""
import os
import re
import sys
from typing import Any, Dict, List, Optional

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from common import canonical_category, http_json, make_product  # noqa: E402

STORE = {"id": "consum", "name": "Consum", "color": "#FF6A13", "web": "https://tienda.consum.es"}
LIMIT = 0  # if >0, stop after roughly LIMIT products (for quick tests)

API = "https://tienda.consum.es/api/rest/V1.0"
PAGE = 100  # the API caps page size at 100

# (top, level-2) -> canonical id. None = use keyword rules (default in _TOP_CAT).
_SUB_CAT = {
    ("Despensa", "Aperitivos y frutos secos"): "dulces-desayuno",
    ("Despensa", "Desayuno, dulces y café"): "dulces-desayuno",
    ("Despensa", "Turrones y Dulces"): "dulces-desayuno",
    ("Despensa", "Lácteos y huevos"): "lacteos-huevos",
    ("Despensa", "Panes y tostadas"): "panaderia",
    ("Despensa", "Conservas, aceites y condimentos"): None,
    ("Despensa", "Nutrición y dietética"): None,
    ("Frescos", "Carnicería"): "carne",
    ("Frescos", "Carnicería corte"): "carne",
    ("Frescos", "Charcutería"): "charcuteria-quesos",
    ("Frescos", "Charcutería corte"): "charcuteria-quesos",
    ("Frescos", "Quesos"): "charcuteria-quesos",
    ("Frescos", "Quesos corte"): "charcuteria-quesos",
    ("Frescos", "Frutas"): "fruta-verdura",
    ("Frescos", "Verduras"): "fruta-verdura",
    ("Frescos", "Pescadería"): "pescado",
    ("Bazar", "Promocionales"): None,
    ("Bazar", "Libros"): "otros",
}
# top -> (default canonical id, apply keyword rules first?)
_TOP_CAT = {
    "Bazar": ("limpieza-hogar", False),
    "Bebidas": ("bebidas", False),
    "Congelados y helados": ("congelados", False),
    "Cuidado personal": ("higiene-belleza", False),
    "Despensa": ("despensa", False),
    "Droguería y limpieza": ("limpieza-hogar", False),
    "Ecológico y saludable": ("despensa", True),
    "Frescos": ("fruta-verdura", True),
    "Horno": ("panaderia", False),
    "Infantil": ("bebe", False),
    "Mascotas": ("mascotas", False),
    "Platos preparados": ("preparados", False),
}

_UNIT = {"kg": "kg", "l": "L", "u": "ud", "ml": "ml", "gr": "g", "g": "g", "cl": "cl", "lv": "lavados",
         "dc": "docena", "do": "docena", "m": "m"}
_REF_UNIT = {"1 kg": "kg", "1 l": "L", "1 u": "ud", "100 ml": "100 ml", "100 gr": "100 g", "1 lv": "lavado",
             "1 dc": "docena", "1 do": "docena", "1 m": "m"}
_SIZE_RE = re.compile(r"^(?:(\d+)\s*x\s*)?(\d+(?:[.,]\d+)?)\s*([A-Za-z]+)\.?$", re.I)


def _canon(path: List[str], name: str) -> str:
    top = path[0] if path else ""
    sub = path[1] if len(path) > 1 else ""
    if (top, sub) in _SUB_CAT and _SUB_CAT[(top, sub)]:
        return _SUB_CAT[(top, sub)]  # type: ignore[return-value]
    default, rules_first = _TOP_CAT.get(top, ("otros", True))
    if rules_first or (top, sub) in _SUB_CAT or top not in _TOP_CAT:
        c = canonical_category(*(path[1:] + [name]))
        if c != "otros":
            return c
    return default


def _category_paths() -> Dict[int, List[str]]:
    """leaf category id -> [top, level2, level3...] (promo trees skipped)."""
    paths: Dict[int, List[str]] = {}
    try:
        menu = http_json(API + "/shopping/category/menu")
    except Exception as e:
        print("   consum: category menu failed: %s" % e)
        return paths

    def walk(node: Dict[str, Any], path: List[str]) -> None:
        path = path + [node.get("name") or ""]
        cid = node.get("id")
        # first occurrence wins; the "Ecológico y saludable" tree is walked last
        if cid is not None and cid not in paths:
            paths[cid] = path
        for c in node.get("subcategories") or []:
            walk(c, path)

    tops = [t for t in (menu or []) if t.get("type", 0) == 0]
    tops.sort(key=lambda t: t.get("name") == "Ecológico y saludable")
    for t in tops:
        walk(t, [])
    return paths


def _brand(b: Optional[Dict[str, Any]]) -> Optional[str]:
    name = ((b or {}).get("name") or "").strip()
    if not name:
        return None
    if name.isupper():  # Consum sends brands in caps ("CALVO", "HELLMANN'S", "G.BLANCA")
        def word(w: str) -> str:
            if not re.search(r"[AEIOUÁÉÍÓÚ]", w) or "&" in w:  # acronyms: "NK", "H&S", "3M"
                return w
            return re.sub(r"(^|[.\-])([a-záéíóúñü])", lambda m: m.group(1) + m.group(2).upper(), w.lower())
        name = " ".join(word(w) for w in name.split())
    return name


def _size(name: str, description: str, fmt: str) -> Optional[str]:
    desc = re.sub(r"\s+", " ", description or "").strip()
    name = re.sub(r"\s+", " ", name or "").strip()
    rest = desc[len(name):].strip() if desc.startswith(name) else ""
    m = _SIZE_RE.match(rest)
    if m:
        n, qty, unit = m.groups()
        u = _UNIT.get(unit.lower(), unit)
        s = "%s %s" % (qty.replace(".", ","), u)
        return "%s x %s" % (n, s) if n else s
    if rest:
        return rest
    return (fmt or "").strip() or None


def _promo(offers: List[Dict[str, Any]], has_offer_price: bool) -> Optional[str]:
    labels = []
    for o in offers or []:
        short = (o.get("shortDescription") or "").strip()
        long_ = o.get("longDescription") or ""
        if "pack" in long_.lower() and "pack-number" in long_:
            num = re.search(r"pack-number'>\s*(\d+)", long_)
            each = re.search(r"pack-price'>\s*([\d.,]+)", long_)
            if num and each:
                labels.append("Pack %s uds: %s €/ud" % (num.group(1), each.group(1).replace(".", ",")))
                continue
        if short.lower().startswith("acumulas"):
            amt = o.get("amount")
            labels.append("Cheque regalo %s €" % ("%.2f" % amt).replace(".", ",") if amt else short)
            continue
        if short:
            labels.append(short)
    if not labels and has_offer_price:
        labels.append("Oferta")
    # put real price reductions first
    labels.sort(key=lambda s: s.startswith("Cheque"))
    return " · ".join(dict.fromkeys(labels)) or None


def _product(p: Dict[str, Any], paths: Dict[int, List[str]]) -> Optional[Dict[str, Any]]:
    pd = p.get("productData") or {}
    price_data = p.get("priceData") or {}
    prices = {x.get("id"): (x.get("value") or {}) for x in price_data.get("prices") or []}
    base = prices.get("PRICE") or {}
    offer = prices.get("OFFER_PRICE") or {}
    price = offer.get("centAmount") or base.get("centAmount")
    unit_price = offer.get("centUnitAmount") or base.get("centUnitAmount")
    previous = base.get("centAmount") if offer.get("centAmount") else None

    path: List[str] = []
    for c in p.get("categories") or []:
        if c.get("type", 0) == 0:
            path = paths.get(c.get("id")) or []
            if path:
                break
    leaf = next((c.get("name") for c in p.get("categories") or [] if c.get("type", 0) == 0), None)
    if not path and leaf:
        path = ["", leaf]

    name = pd.get("name") or ""
    by_weight = (price_data.get("priceUnitType") or "").lower() == "kg"
    size = "al peso (precio por kg)" if by_weight else _size(name, pd.get("description") or "", pd.get("format") or "")
    ref = (price_data.get("unitPriceUnitType") or "").strip().lower()
    ean = str(p.get("ean") or "").strip()
    prod = make_product(
        STORE["id"], p.get("code") or p.get("id"), name, price,
        brand=_brand(pd.get("brand")),
        category=path[0] if path else None,
        subcategory=(path[1] if len(path) > 1 else None),
        unit_price=unit_price,
        unit=_REF_UNIT.get(ref, ref.replace("1 ", "", 1) or None),
        size=size,
        image=pd.get("imageURL") or next((m.get("url") for m in p.get("media") or []), None),
        previous_price=previous,
        promo=_promo(p.get("offers") or [], bool(offer.get("centAmount"))),
        ean=ean if ean.isdigit() else None,
        url=pd.get("url"),
    )
    if prod:
        prod["cat"] = _canon(path, name)
    return prod


def fetch() -> list:
    paths = _category_paths()
    out: Dict[str, Dict[str, Any]] = {}
    offset = 0
    total: Optional[int] = None
    while True:
        data = http_json(API + "/catalog/product", {"limit": PAGE, "offset": offset, "orderById": 5,
                                                    "showRecommendations": "false"})
        items = data.get("products") or []
        total = data.get("totalCount", total)
        for p in items:
            prod = _product(p, paths)
            if prod and prod["sku"] not in out:
                out[prod["sku"]] = prod
        offset += PAGE
        if not items or not data.get("hasMore") or (total is not None and offset >= total):
            break
        if LIMIT and len(out) >= LIMIT:
            break
    return list(out.values())
