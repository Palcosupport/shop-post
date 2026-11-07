"""Alcampo (www.compraonline.alcampo.es) catalogue scraper.

Ocado Smart Platform storefront. Uses the same public JSON endpoints as the
web app:
  - category tree: /api/webproductpagews/v1/categories?decoration=false&categoryDepth=N
  - category page: /api/webproductpagews/v6/product-pages?categoryId=<uuid>&tag=web&tag=category-item
                   &maxPageSize=1000&maxProductsToDecorate=1000[&pageToken=...]
    (pageToken only works with the session cookies set by the first call)

Products are fetched per top-level category in big pages so the whole run
needs only a few dozen calls, spaced DELAY seconds apart.

The site sits behind AWS WAF; when it answers with a challenge
(HTTP 202 + ``x-amzn-waf-action: challenge``) we stop instead of trying to
solve it.
"""
import json
import random
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from http.cookiejar import CookieJar
from typing import Any, Dict, List, Optional

import common
from common import make_product, strip_accents

STORE = {"id": "alcampo", "name": "Alcampo", "color": "#E4032E", "web": "https://www.compraonline.alcampo.es"}
LIMIT = 0

BASE = "https://www.compraonline.alcampo.es"
API = BASE + "/api/webproductpagews"
PAGE_SIZE = 1000
DELAY = 30.0  # seconds between API calls: AWS WAF challenges bursts (~6 quick calls)

# Grocery / household top-level categories (retailerCategoryId). Others
# (electronics, toys, garden, books, flyers...) are skipped. Themed sections
# that only regroup products from the main ones go last so the main taxonomy wins.
GROCERY_TOP = ["OC2112", "OC16", "OCC10", "OC10", "OC200220183", "OC20022018", "OCC11", "OCC14", "OC70",
               "OCC13", "OC69", "OC062", "OCSINGSINL", "OC26112021", "OC09112021"]

_UNIT = {"PER_1KG": "kg", "PER_KG": "kg", "PER_LITRE": "L", "PER_1L": "L", "EACH": "ud", "PER_100G": "100 g",
         "PER_100ML": "100 ml", "PER_METRE": "m", "PER_WASH": "lavado", "PER_DOSE": "dosis"}

_PROMO_RE = re.compile(r"%|\d+\s*x\s*\d+|\d\s*ª|unidad|descuento|dto|€", re.I)


class Blocked(RuntimeError):
    pass


def _log(msg: str) -> None:
    print("   [alcampo] " + msg, file=sys.stderr, flush=True)


_jar = CookieJar()
_opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(_jar))


def _get(path: str, params: Optional[List[tuple]] = None) -> Any:
    url = API + path
    if params:
        url += "?" + urllib.parse.urlencode(params)
    headers = {"User-Agent": common.USER_AGENT, "Accept": "application/json", "Accept-Language": "es-ES,es;q=0.9",
               "Referer": BASE + "/"}
    last = None
    for attempt in range(3):
        time.sleep(DELAY * (1 + 0.5 * attempt) + random.random() * 3)
        try:
            with _opener.open(urllib.request.Request(url, headers=headers), timeout=40) as resp:
                if resp.headers.get("x-amzn-waf-action"):
                    raise Blocked("AWS WAF %s (HTTP %s) on %s" % (resp.headers.get("x-amzn-waf-action"),
                                                                   resp.status, path))
                return json.loads(resp.read().decode("utf-8"))
        except urllib.error.HTTPError as e:
            if e.headers.get("x-amzn-waf-action") or e.code in (403, 405):
                raise Blocked("AWS WAF blocked (HTTP %s) on %s" % (e.code, path))
            last = e
            if e.code in (400, 404):
                raise
            time.sleep(2 ** attempt)
        except Blocked:
            raise
        except Exception as e:
            last = e
            time.sleep(2 ** attempt)
    raise RuntimeError("GET failed %s: %s" % (url, last))


def _slug(text: str) -> str:
    return re.sub(r"[^a-z0-9]+", "-", strip_accents(text or "").lower()).strip("-")


def _promo_label(p: Dict[str, Any], on_promo_price: bool) -> Optional[str]:
    for pr in p.get("promotions") or []:
        desc = (pr.get("description") or "").strip()
        if not desc:
            continue
        desc = re.sub(r"\s*\(?\s*\d{1,2}/\d{1,2}/\d{2,4}\s*[-_]\s*\d{1,2}/\d{1,2}/\d{2,4}\s*\)?\.?", "", desc)
        desc = re.sub(r",?\s*del \d{1,2}/\d{1,2}/\d{2,4} al \d{1,2}/\d{1,2}/\d{2,4}\.?", "", desc).strip(" .,")
        if _PROMO_RE.search(desc) or on_promo_price:
            return desc[:60] or ("Oferta" if on_promo_price else None)
    return "Oferta" if on_promo_price else None


def _product(p: Dict[str, Any], category: str, subcategory: str) -> Optional[dict]:
    price = (p.get("price") or {}).get("amount")
    promo_price = (p.get("promoPrice") or {}).get("amount")
    prev = None
    if promo_price and common.to_float(promo_price) and common.to_float(price) \
            and common.to_float(promo_price) < common.to_float(price):
        prev, price = price, promo_price
    up = p.get("promoUnitPrice") if prev else None
    up = up or p.get("unitPrice") or {}
    unit_price = (up.get("price") or {}).get("amount")
    unit = _UNIT.get(up.get("unitName") or "", None)
    if not unit and up.get("unitName"):
        unit = up["unitName"].replace("PER_", "").lower()
    image = None
    imgs = p.get("images") or []
    if imgs and imgs[0].get("src"):
        image = imgs[0]["src"]
    elif (p.get("image") or {}).get("src"):
        image = p["image"]["src"]
    size = p.get("packSizeDescription")
    if size:
        size = re.sub(r"^(\d+)g$", r"\1 g", size)
        size = re.sub(r"^(\d+)ml$", r"\1 ml", size)
    rid = p.get("retailerProductId") or p.get("productId")
    url = "%s/products/%s/%s" % (BASE, _slug(p.get("name", ""))[:80], rid)
    return make_product(STORE["id"], rid, p.get("name"), price, brand=p.get("brand"), category=category,
                        subcategory=subcategory, unit_price=unit_price, unit=unit, size=size, image=image,
                        previous_price=prev, promo=_promo_label(p, bool(prev)), url=url)


def _decorated(data: Dict[str, Any]) -> List[Dict[str, Any]]:
    out = []
    for g in data.get("productGroups") or []:
        out.extend(g.get("decoratedProducts") or [])
    return out


def _subcategory(p: Dict[str, Any], top_name: str) -> str:
    """Second-level name under ``top_name`` from the product's categoryPath (may hold several paths)."""
    path = p.get("categoryPath") or []
    paths = path if path and isinstance(path[0], list) else [path]
    for cp in paths:
        names = [c.get("name") if isinstance(c, dict) else c for c in cp]
        if top_name in names:
            j = names.index(top_name)
            if j + 1 < len(names):
                return names[j + 1]
    return ""


def _fetch_top(top: Dict[str, Any], seen: set, out: List[dict]) -> None:
    """Fetch every product listed under a top-level category, following nextPageToken."""
    base = [("categoryId", top["categoryId"]), ("tag", "web"), ("tag", "category-item"),
            ("maxPageSize", PAGE_SIZE), ("maxProductsToDecorate", PAGE_SIZE)]
    params = base + [("includeAdditionalPageInfo", "true")]
    for _ in range(40):
        data = _get("/v6/product-pages", params)
        items = _decorated(data)
        for p in items:
            rid = p.get("retailerProductId") or p.get("productId")
            if rid in seen:
                continue
            prod = _product(p, top["name"], _subcategory(p, top["name"]))
            if prod:
                seen.add(rid)
                out.append(prod)
        token = (data.get("metadata") or {}).get("nextPageToken")
        if not token or not items or (LIMIT and len(out) >= LIMIT):
            return
        params = base + [("pageToken", token)]


def fetch() -> list:
    tree = _get("/v1/categories", [("decoration", "false"), ("categoryDepth", 1)])
    by_rid = {n.get("retailerCategoryId"): n for n in tree}
    out: List[dict] = []
    seen: set = set()
    for rid in GROCERY_TOP:
        top = by_rid.get(rid)
        if not top:
            _log("top category %s not found" % rid)
            continue
        if LIMIT and len(out) >= LIMIT:
            break
        before = len(out)
        try:
            _fetch_top(top, seen, out)
        except Blocked as e:
            # A partial catalogue would look like thousands of removed products in the
            # history, so fail the store and let run.py keep the previous data.
            raise Blocked("%s after %d products" % (e, len(out)))
        except Exception as e:
            _log("%s failed: %s" % (top["name"], e))
            continue
        _log("%s: +%d (total %d)" % (top["name"], len(out) - before, len(out)))
    return out
