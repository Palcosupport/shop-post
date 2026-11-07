"""Dia (www.dia.es) catalogue scraper.

STATUS: www.dia.es is fronted by Akamai Bot Manager, which answers plain
(non-browser) HTTP clients with "403 Access Denied" (errors.edgesuite.net
reference), both for the HTML pages and the JSON API. We do not try to get
around that, so ``fetch()`` raises a clear error when blocked and run.py keeps
the previous data for the store.

If the API becomes reachable, the code below uses the same public endpoints
the website calls:
  - category tree:  /api/v1/plp-back/reduced
  - category PLP:   /api/v1/plp-insight/initial_analytics/<path>/c/<code>?navigation=<code>
The JSON parsing is defensive because it could not be verified against live
responses.
"""
import re
import sys
import urllib.error
from typing import Any, Dict, Iterable, List, Optional, Tuple

from common import http_json, make_product

STORE = {"id": "dia", "name": "Dia", "color": "#E2001A", "web": "https://www.dia.es"}
LIMIT = 0

BASE = "https://www.dia.es"
TREE_URL = BASE + "/api/v1/plp-back/reduced"
PLP_URL = BASE + "/api/v1/plp-insight/initial_analytics%s"


class Blocked(RuntimeError):
    pass


def _log(msg: str) -> None:
    print("   [dia] " + msg, file=sys.stderr, flush=True)


def _get(url: str, params: Optional[Dict[str, Any]] = None) -> Any:
    try:
        return http_json(url, params, headers={"Referer": BASE + "/"})
    except urllib.error.HTTPError as e:
        if e.code == 403:
            body = e.read()[:200].decode("utf-8", "replace")
            raise Blocked("dia.es blocked the request (HTTP 403, Akamai): %s" % re.sub(r"\s+", " ", body))
        raise


def _walk(node: Any, trail: Tuple[str, ...] = ()) -> Iterable[Tuple[Tuple[str, ...], str, bool]]:
    """Yield (names trail, path, is_leaf) for every category node with a '/c/<code>' path."""
    if isinstance(node, dict):
        path = node.get("path") or node.get("url") or ""
        name = node.get("name") or node.get("display_name") or node.get("title") or ""
        kids = node.get("children") or node.get("categories") or node.get("subcategories") or {}
        here = trail + ((name,) if name else ())
        if isinstance(path, str) and "/c/" in path:
            yield here, path, not kids
        if kids:
            for child in (kids.values() if isinstance(kids, dict) else kids):
                for x in _walk(child, here):
                    yield x
        else:
            for k, v in node.items():
                if isinstance(v, (dict, list)) and k not in ("children", "categories", "subcategories"):
                    for x in _walk(v, here):
                        yield x
    elif isinstance(node, list):
        for v in node:
            for x in _walk(v, trail):
                yield x


def _leaf_categories() -> List[Tuple[Tuple[str, ...], str]]:
    tree = _get(TREE_URL)
    out, seen = [], set()
    for trail, path, leaf in _walk(tree):
        if leaf and path not in seen:
            seen.add(path)
            out.append((trail, path))
    return out


def _first(d: Dict[str, Any], *keys: str) -> Any:
    for k in keys:
        if d.get(k) not in (None, ""):
            return d[k]
    return None


def _items(data: Any) -> List[Dict[str, Any]]:
    if isinstance(data, dict):
        for k in ("plp_items", "items", "products"):
            if isinstance(data.get(k), list):
                return data[k]
        for v in data.values():
            got = _items(v)
            if got:
                return got
    return []


def _product(it: Dict[str, Any], trail: Tuple[str, ...]) -> Optional[dict]:
    prices = it.get("prices") or {}
    price = _first(prices, "price", "current_price") or _first(it, "price")
    prev = _first(prices, "strikethrough_price", "previous_price", "price_before")
    unit_price = _first(prices, "price_per_unit", "unit_price")
    unit = _first(prices, "measure_unit", "unit")
    image = _first(it, "image", "image_url")
    if image and image.startswith("/"):
        image = BASE + image
    url = _first(it, "url")
    if url and url.startswith("/"):
        url = BASE + url
    promo = None
    promos = it.get("promotions") or []
    if isinstance(promos, list) and promos:
        p0 = promos[0]
        promo = p0.get("text") or p0.get("description") or p0.get("name") if isinstance(p0, dict) else str(p0)
    elif prev:
        promo = "Oferta"
    category = trail[0] if trail else None
    subcategory = trail[-1] if len(trail) > 1 else None
    return make_product(STORE["id"], _first(it, "object_id", "id", "sku"), _first(it, "display_name", "name"), price,
                        brand=_first(it, "brand"), category=category, subcategory=subcategory,
                        unit_price=unit_price, unit=unit, image=image, previous_price=prev, promo=promo,
                        ean=_first(it, "ean"), url=url)


def fetch() -> list:
    cats = _leaf_categories()  # raises Blocked when Akamai refuses us
    _log("%d leaf categories" % len(cats))
    out: List[dict] = []
    seen = set()
    for trail, path in cats:
        if LIMIT and len(out) >= LIMIT:
            break
        code = path.rstrip("/").rsplit("/", 1)[-1]
        try:
            data = _get(PLP_URL % path, {"navigation": code})
        except Blocked:
            raise
        except Exception as e:
            _log("%s failed: %s" % (path, e))
            continue
        for it in _items(data):
            p = _product(it, trail)
            if p and p["sku"] not in seen:
                seen.add(p["sku"])
                out.append(p)
    return out
