"""Eroski (supermercado.eroski.es) catalogue scraper.

The site is an Apache Tapestry app. Category listing pages use an infinite
scroll that calls the zone endpoint

    /es/supermarket:loadpage?t:ac=<cat path>&pageNumber=<n>
    (header X-Requested-With: XMLHttpRequest)

which returns {"content": "<html of 20 product cards>"}. The server refuses
pageNumber >= 100 (403), so listings are walked per 2nd-level category and only
split into their 3rd-level children when a category is that big.
The category tree is read from the menu in the home page HTML.
"""
import html as htmllib
import json
import re
import sys
from typing import Dict, List, Optional, Tuple

from common import http_get, make_product

STORE = {"id": "eroski", "name": "Eroski", "color": "#E30613", "web": "https://supermercado.eroski.es"}
LIMIT = 0

BASE = "https://supermercado.eroski.es"
LIST_URL = BASE + "/es/supermarket:loadpage"
PAGE_SIZE = 20
MAX_PAGE = 99  # pageNumber >= 100 -> 403

# Top-level sections that are groceries / household (skip electronics, furniture...)
GROCERY_TOP = {
    "2059698",  # Frescos
    "2059806",  # Alimentación
    "2059919",  # Congelados
    "2060118",  # Dulces y desayuno
    "2060211",  # Bebidas
    "2060327",  # Bebé
    "2060401",  # Higiene y belleza
    "2060538",  # Limpieza
    "2060623",  # Mascotas
    "4000091",  # Parafarmacia
}
# Non-grocery 2nd-level categories inside grocery sections (baby furniture, etc.)
SKIP_SUB = {"6000002", "6000010", "6000015", "6000021", "6000024"}

_UNIT_MAP = {"KILO": "kg", "LITRO": "L", "UNIDAD": "ud", "DOSIS": "dosis", "METRO": "m", "LAVADO": "lavado",
             "DOCENA": "docena", "PAR": "ud", "100 GRAMOS": "100 g", "100 MILILITROS": "100 ml"}


def _log(msg: str) -> None:
    print("   [eroski] " + msg, file=sys.stderr, flush=True)


def _text(fragment: str) -> str:
    return re.sub(r"\s+", " ", htmllib.unescape(re.sub(r"<[^>]+>", " ", fragment or ""))).strip()


def _category_tree() -> Tuple[Dict[str, str], Dict[str, List[str]]]:
    """Return ({path: display name}, {parent path: [child paths]}) from the home page menu."""
    page = http_get(BASE + "/es/").decode("utf-8", "replace")
    names: Dict[str, str] = {}
    children: Dict[str, List[str]] = {}
    for m in re.finditer(r'href="https://supermercado\.eroski\.es(?::443)?/es/supermercado/((?:\d+-[^/"]+/)+)"[^>]*>(.*?)</a>',
                         page, re.S):
        path = m.group(1).strip("/")
        if not path.split("-")[0].isdigit():
            continue
        name = _text(m.group(2))
        name = re.sub(r"^Ver todo\s+", "", name, flags=re.I).strip()
        if name and (path not in names or len(name) < len(names[path])):
            names[path] = name
        parts = path.split("/")
        for i in range(1, len(parts)):
            parent, child = "/".join(parts[:i]), "/".join(parts[:i + 1])
            lst = children.setdefault(parent, [])
            if child not in lst:
                lst.append(child)
    return names, children


def _cat_id(path: str) -> str:
    return path.split("/")[-1].split("-")[0]


def _load_page(path: str, page: int) -> str:
    raw = http_get(LIST_URL, {"t:ac": path, "pageNumber": page},
                   headers={"X-Requested-With": "XMLHttpRequest", "Accept": "application/json, text/javascript, */*",
                            "Referer": "%s/es/supermercado/%s/" % (BASE, path)})
    data = json.loads(raw.decode("utf-8", "replace"))
    return data.get("content") or ""


def _parse_cards(content: str, category: str, subcategory: str) -> List[dict]:
    out: List[dict] = []
    for block in re.split(r"product-item-lineal item-type-1", content)[1:]:
        url_m = re.search(r"href=['\"](https://supermercado\.eroski\.es(?::443)?/es/productdetail/(\d+)-[^'\"]*)['\"]", block)
        if not url_m:
            continue
        url = url_m.group(1).replace(":443", "")
        sku = url_m.group(2)
        title_m = re.search(r"product-title-link[^>]*>(.*?)</a>", block, re.S)
        name = _text(title_m.group(1)) if title_m else ""
        brand = None
        met = re.search(r"data-metrics=['\"](\{.*?\})['\"]", block)
        if met:
            try:
                item = json.loads(htmllib.unescape(met.group(1)))["ecommerce"]["items"][0]
                brand = item.get("item_brand") or None
                if not name:
                    name = item.get("item_name") or ""
            except (ValueError, KeyError, IndexError, TypeError):
                pass
        now_m = re.search(r"class=['\"]price-offer-now['\"]>([^<]*)<", block)
        before_m = re.search(r"class=['\"]price-offer-before['\"]>([^<]*)<", block)
        price = now_m.group(1) if now_m else None
        prev = before_m.group(1) if before_m else None
        unit_price, unit = None, None
        q = re.search(r"class=['\"]quantity-text['\"]>(.*?)</p>", block, re.S)
        if q:
            qm = re.match(r"1\s+(.+?)\s+A\s+([\d.,]+)\s*€", _text(q.group(1)), re.I)
            if qm:
                unit = _UNIT_MAP.get(qm.group(1).upper(), qm.group(1).lower())
                unit_price = qm.group(2)
        promo = None
        o = re.search(r"product-offer product-offer[^'\"]*['\"]>(.*?)</div>", block, re.S)
        if o:
            promo = _text(o.group(1)) or None
            if promo:
                promo = re.sub(r"(-?\d+)\s+%", r"\1%", promo)
        img_m = re.search(r"<img[^>]+src=['\"](https://supermercado\.eroski\.es//?images/[^'\"]+)['\"]", block)
        image = img_m.group(1).replace(".es//images", ".es/images") if img_m else None
        size = None
        if "," in name:
            tail = name.rsplit(",", 1)[1].strip()
            if re.search(r"\d", tail) or re.search(r"\b(unidad|manojo|pieza|al peso|al corte)\b", tail, re.I):
                size = tail
        p = make_product(STORE["id"], sku, name, price, brand=brand, category=category, subcategory=subcategory,
                         unit_price=unit_price, unit=unit, size=size, image=image, previous_price=prev,
                         promo=promo, url=url)
        if p:
            out.append(p)
    return out


def _crawl(path: str, names: Dict[str, str], children: Dict[str, List[str]], seen: set, out: List[dict]) -> None:
    top = path.split("/")[0]
    category = names.get(top, top)
    subcategory = names.get("/".join(path.split("/")[:2]), "")
    for page in range(0, MAX_PAGE + 1):
        if LIMIT and len(out) >= LIMIT:
            return
        if page == MAX_PAGE and children.get(path):
            # listing truncated by the server: walk the children instead
            _log("%s has >%d products, splitting into children" % (path, MAX_PAGE * PAGE_SIZE))
            for child in children[path]:
                _crawl(child, names, children, seen, out)
            return
        try:
            content = _load_page(path, page)
        except Exception as e:  # keep going with the other categories
            _log("page %d of %s failed: %s" % (page, path, e))
            return
        cards = _parse_cards(content, category, subcategory)
        for p in cards:
            if p["sku"] not in seen:
                seen.add(p["sku"])
                out.append(p)
        # pages sometimes hold fewer than PAGE_SIZE cards, so only an empty page ends the listing
        if "productdetail/" not in content:
            return


def fetch() -> list:
    names, children = _category_tree()
    tops = sorted({p.split("/")[0] for p in names if _cat_id(p.split("/")[0]) in GROCERY_TOP})
    out: List[dict] = []
    seen: set = set()
    for top in tops:
        subs = [s for s in children.get(top, []) if _cat_id(s) not in SKIP_SUB] or [top]
        for sub in subs:
            if LIMIT and len(out) >= LIMIT:
                return out
            before = len(out)
            _crawl(sub, names, children, seen, out)
            _log("%s: +%d (total %d)" % (sub, len(out) - before, len(out)))
    return out
