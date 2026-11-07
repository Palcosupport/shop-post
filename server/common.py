"""Shared helpers for the Shop Post supermarket scrapers.

Every store module in ``stores/`` exposes:

    STORE = {"id": "mercadona", "name": "Mercadona", "color": "#00A650"}
    def fetch() -> list[dict]   # list of products built with make_product()

Products are normalised to one schema so the iOS app can treat every
supermarket the same way. Python 3.9 compatible (no match statements,
use typing.Optional instead of ``X | None``).
"""
import json
import random
import re
import time
import unicodedata
import urllib.error
import urllib.parse
import urllib.request
from typing import Any, Dict, List, Optional

USER_AGENT = (
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 "
    "(KHTML, like Gecko) Version/18.0 Safari/605.1.15"
)

# ---------------------------------------------------------------------------
# Canonical categories shown in the app (id, label, emoji). Stores map their
# own taxonomy to these with ``canonical_category``.
# ---------------------------------------------------------------------------
CATEGORIES = [
    ("fruta-verdura", "Fruta y verdura", "🥦"),
    ("carne", "Carne", "🥩"),
    ("pescado", "Pescado y marisco", "🐟"),
    ("charcuteria-quesos", "Charcutería y quesos", "🧀"),
    ("lacteos-huevos", "Lácteos y huevos", "🥛"),
    ("panaderia", "Panadería y bollería", "🥖"),
    ("despensa", "Alimentación", "🫙"),
    ("congelados", "Congelados", "🧊"),
    ("bebidas", "Bebidas", "🥤"),
    ("dulces-desayuno", "Desayuno y dulces", "🍫"),
    ("preparados", "Platos preparados", "🍲"),
    ("bebe", "Bebé", "🍼"),
    ("higiene-belleza", "Higiene y belleza", "🧴"),
    ("limpieza-hogar", "Limpieza y hogar", "🧽"),
    ("mascotas", "Mascotas", "🐾"),
    ("otros", "Otros", "🛒"),
]

# Keyword rules (see canonical_category for how they are applied).
_CATEGORY_RULES = [
    ("mascotas", ["mascota", "perro", "gato", "animales "]),
    ("bebe", ["bebe", "infantil", "pañal", "panal", "papilla", "potito"]),
    ("limpieza-hogar", ["limpieza", "hogar", "detergente", "drogueria", "lavavajillas",
                         "papel higienico", "celulosa", "bolsas de basura", "menaje", "suavizante", "lejia"]),
    ("higiene-belleza", ["higiene", "belleza", "cosmetica", "perfumeria", "cuidado personal",
                          "champu", "gel de ducha", "desodorante", "maquillaje", "farmacia", "parafarmacia", "afeitado"]),
    ("congelados", ["congelad", "helado"]),
    ("bebidas", ["bebida", "agua ", "aguas ", "refresco", "zumo", "cerveza", "vino", "licor", "cava",
                 "bodega", "isotonic", "gaseosa", "sidra"]),
    ("pescado", ["pescado", "marisco", "pescaderia", "conservas de pescado", "atun", "salmon", "gamba"]),
    ("charcuteria-quesos", ["charcuteria", "embutido", "queso", "jamon", "fiambre", "chorizo", "salchich", "pate "]),
    ("lacteos-huevos", ["lacteo", "leche", "yogur", "huevo", "mantequilla", "nata ", "postres lacteos", "kefir", "bebida vegetal"]),
    ("carne", ["carne", "carniceria", "pollo", "cerdo", "vacuno", "ternera", "cordero", "pavo", "hamburguesa"]),
    ("fruta-verdura", ["fruta", "verdura", "hortaliza", "ensalada", "fruteria", "legumbre fresca", "seta"]),
    ("panaderia", ["pan ", "panes ", "panaderia", "bolleria", "pasteleria", "tostada", "biscote"]),
    ("dulces-desayuno", ["desayuno", "cereal", "galleta", "cacao", "cafe", "infusion", "te ", "chocolate",
                         "dulce", "golosina", "snack", "aperitivo", "frutos secos", "mermelada", "miel", "azucar"]),
    ("preparados", ["preparad", "listo para", "pizza", "comida preparada", "sushi", "tortilla", "platos"]),
    ("despensa", ["despensa", "aceite", "arroz", "pasta", "legumbre", "conserva", "salsa", "especia",
                  "harina", "sopa", "caldo", "vinagre", "sal ", "alimentacion"]),
]


def strip_accents(text: str) -> str:
    return "".join(c for c in unicodedata.normalize("NFD", text) if unicodedata.category(c) != "Mn")


_RULE_PATTERNS = [
    # Keywords match at the start of a word; a trailing space means "whole word only".
    (cat_id, [re.compile(r"(?<![a-z0-9])" + re.escape(strip_accents(w.strip()).lower())
                         + (r"(?![a-z0-9])" if w.endswith(" ") else "")) for w in words])
    for cat_id, words in _CATEGORY_RULES
]


def _match_text(text: str) -> Optional[str]:
    """Category whose keyword appears earliest in text (keywords match at word starts)."""
    t = strip_accents(text).lower()
    best = None  # (position, rule index, cat)
    for idx, (cat_id, pats) in enumerate(_RULE_PATTERNS):
        for pat in pats:
            m = pat.search(t)
            if m and (best is None or (m.start(), idx) < best[:2]):
                best = (m.start(), idx, cat_id)
    return best[2] if best else None


def canonical_category(*texts: Optional[str]) -> str:
    """Map store taxonomy + product name to one of CATEGORIES ids.

    Callers pass texts from general to specific, with the product name last
    (category, subcategory, ..., name). The most specific taxonomy level is
    checked first, then the more general ones, and the name only as a fallback.
    Inside a text the earliest keyword wins ("Aceite, vinagre ... y pan rallado"
    is pantry, not bakery).
    """
    items = [t for t in texts if t]
    if not items:
        return "otros"
    order = items[-2::-1] + [items[-1]] if len(items) > 1 else items
    for text in order:
        cat = _match_text(text)
        if cat:
            return cat
    return "otros"


# ---------------------------------------------------------------------------
# HTTP
# ---------------------------------------------------------------------------
def http_get(url: str, params: Optional[Dict[str, Any]] = None, headers: Optional[Dict[str, str]] = None,
             retries: int = 3, delay: float = 0.35, timeout: float = 30) -> bytes:
    """GET with retries, polite delay and a browser-like User-Agent."""
    if params:
        url = url + ("&" if "?" in url else "?") + urllib.parse.urlencode(params)
    h = {"User-Agent": USER_AGENT, "Accept": "application/json, text/html;q=0.9, */*;q=0.8",
         "Accept-Language": "es-ES,es;q=0.9"}
    if headers:
        h.update(headers)
    last: Optional[Exception] = None
    for attempt in range(retries):
        try:
            time.sleep(delay + random.random() * delay)
            req = urllib.request.Request(url, headers=h)
            with urllib.request.urlopen(req, timeout=timeout) as resp:
                return resp.read()
        except urllib.error.HTTPError as e:
            last = e
            if e.code in (400, 401, 403, 404):
                raise
            time.sleep(2 ** attempt)
        except Exception as e:  # network errors, timeouts
            last = e
            time.sleep(2 ** attempt)
    raise RuntimeError("GET failed %s: %s" % (url, last))


def http_json(url: str, params: Optional[Dict[str, Any]] = None, headers: Optional[Dict[str, str]] = None,
              **kw) -> Any:
    return json.loads(http_get(url, params, headers, **kw).decode("utf-8"))


def http_post_json(url: str, body: Any, headers: Optional[Dict[str, str]] = None, timeout: float = 30) -> Any:
    h = {"User-Agent": USER_AGENT, "Content-Type": "application/json", "Accept": "application/json"}
    if headers:
        h.update(headers)
    time.sleep(0.35 + random.random() * 0.35)
    req = urllib.request.Request(url, data=json.dumps(body).encode("utf-8"), headers=h, method="POST")
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return json.loads(resp.read().decode("utf-8"))


# ---------------------------------------------------------------------------
# Products
# ---------------------------------------------------------------------------
def to_float(value: Any) -> Optional[float]:
    if value is None or value == "":
        return None
    if isinstance(value, (int, float)):
        return float(value)
    s = str(value).replace("€", "").replace("\xa0", " ").strip()
    s = re.sub(r"[^\d,.\-]", "", s)
    if "," in s and "." in s:
        s = s.replace(".", "").replace(",", ".")
    else:
        s = s.replace(",", ".")
    try:
        return float(s)
    except ValueError:
        return None


_UNIT_ALIASES = {"kg": "kg", "kilo": "kg", "kilos": "kg", "l": "L", "litro": "L", "litros": "L", "lt": "L",
                 "ud": "ud", "u": "ud", "unidad": "ud", "unidades": "ud", "uds": "ud", "docena": "docena",
                 "100 g": "100 g", "100g": "100 g", "100 ml": "100 ml", "100ml": "100 ml", "m": "m", "lavado": "lavado"}


def norm_unit(unit: Optional[str]) -> Optional[str]:
    if not unit:
        return None
    u = strip_accents(str(unit)).lower().strip().strip("/").strip()
    return _UNIT_ALIASES.get(u, u or None)


def make_product(store: str, sku: Any, name: str, price: Any, *,
                 brand: Optional[str] = None,
                 category: Optional[str] = None,
                 subcategory: Optional[str] = None,
                 unit_price: Any = None,
                 unit: Optional[str] = None,
                 size: Optional[str] = None,
                 image: Optional[str] = None,
                 previous_price: Any = None,
                 promo: Optional[str] = None,
                 ean: Optional[str] = None,
                 url: Optional[str] = None) -> Optional[Dict[str, Any]]:
    """Build a normalised product dict. Returns None if name/price are unusable.

    - price: current shelf price in EUR (float)
    - previous_price: the store's own "antes"/crossed-out price when on promotion
    - promo: short label shown on the offer badge ("2ª ud -50%", "Oferta"...)
    - unit_price + unit: price per kg / L / ud (unit normalised to kg, L, ud, 100 g...)
    - size: human pack size ("1 L", "6 x 33 cl", "500 g")
    - category/subcategory: the store's own taxonomy (kept for display)
    """
    p = to_float(price)
    name = re.sub(r"\s+", " ", (name or "")).strip()
    if not name or p is None or p <= 0:
        return None
    prev = to_float(previous_price)
    if prev is not None and prev <= p:
        prev = None
    up = to_float(unit_price)
    if image and image.startswith("//"):
        image = "https:" + image
    return {
        "id": "%s:%s" % (store, sku),
        "store": store,
        "sku": str(sku),
        "name": name,
        "brand": (brand or "").strip() or None,
        "cat": canonical_category(category, subcategory, name),
        "category": (category or "").strip() or None,
        "subcategory": (subcategory or "").strip() or None,
        "price": round(p, 2),
        "unitPrice": round(up, 2) if up else None,
        "unit": norm_unit(unit),
        "size": (size or "").strip() or None,
        "image": image or None,
        "previousPrice": round(prev, 2) if prev else None,
        "promo": (promo or "").strip() or None,
        "ean": str(ean) if ean else None,
        "url": url or None,
    }


def dedupe(products: List[Optional[Dict[str, Any]]]) -> List[Dict[str, Any]]:
    seen: Dict[str, Dict[str, Any]] = {}
    for p in products:
        if p and p["id"] not in seen:
            seen[p["id"]] = p
    return list(seen.values())
