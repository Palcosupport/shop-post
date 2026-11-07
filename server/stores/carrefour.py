"""Carrefour Spain online supermarket (www.carrefour.es/supermercado).

STATUS: BLOCKED. Every page and JSON endpoint of www.carrefour.es that the
supermarket uses (the /supermercado HTML, /search-api/query/v1/search and
/cloud-api/plp-food-papi/...) answers plain HTTP clients with a Cloudflare
"Sorry, you have been blocked" page (HTTP 403, server: cloudflare). Only
robots.txt is reachable. Getting past it would require bypassing the bot
protection (browser/TLS impersonation, challenge solving), which this project
does not do.

``fetch()`` therefore makes one polite probe of the public search endpoint
the website itself calls. If it is still blocked it raises
RuntimeError("blocked: ...") so run.py records the store as an error and keeps
any previous data. If one day the endpoint answers JSON, a best-effort parser
for the search-api response shape is attempted (UNTESTED against live data).
"""
import json
import os
import sys
import urllib.error
from typing import Any, Dict, List, Optional

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from common import dedupe, http_get, make_product  # noqa: E402

STORE = {"id": "carrefour", "name": "Carrefour", "color": "#004E9F",
         "web": "https://www.carrefour.es/supermercado"}
LIMIT = 0  # if >0, stop after roughly LIMIT products (quick tests)

BASE = "https://www.carrefour.es"
SEARCH = BASE + "/search-api/query/v1/search"
ROWS = 24
# Broad queries covering the grocery catalogue (used only if the API is reachable).
QUERIES = ["leche", "yogur", "huevos", "queso", "jamon", "embutido", "pollo", "ternera", "cerdo",
           "pescado", "marisco", "fruta", "verdura", "pan", "galletas", "cereales", "cafe", "chocolate",
           "aceite", "arroz", "pasta", "legumbres", "conservas", "salsa", "especias", "harina", "azucar",
           "agua", "refresco", "zumo", "cerveza", "vino", "congelados", "helado", "pizza", "platos preparados",
           "snacks", "frutos secos", "bebe", "pañales", "champu", "gel", "desodorante", "detergente",
           "suavizante", "lavavajillas", "papel higienico", "limpiador", "perro", "gato"]


def _probe(params: Dict[str, Any]) -> bytes:
    try:
        return http_get(SEARCH, params, headers={"Accept": "application/json"}, retries=1)
    except urllib.error.HTTPError as e:
        body = b""
        try:
            body = e.read()[:4000]
        except Exception:
            pass
        server = e.headers.get("server") if e.headers else None
        ray = e.headers.get("cf-ray") if e.headers else None
        snippet = "Sorry, you have been blocked" if b"you have been blocked" in body else \
            body[:120].decode("utf-8", "replace").replace("\n", " ")
        raise RuntimeError("blocked: HTTP %s from %s (server=%s, cf-ray=%s): %s"
                           % (e.code, SEARCH, server, ray, snippet))


def _docs(data: Any) -> List[Dict[str, Any]]:
    content = data.get("content") if isinstance(data, dict) else None
    if isinstance(content, dict):
        docs = content.get("docs")
        if isinstance(docs, list):
            return docs
    if isinstance(data, dict) and isinstance(data.get("docs"), list):
        return data["docs"]
    return []


def _build(d: Dict[str, Any]) -> Optional[Dict[str, Any]]:
    sku = d.get("product_id") or d.get("catalog_ref_id") or d.get("id")
    url = d.get("url")
    if url and url.startswith("/"):
        url = BASE + url
    image = d.get("image_path") or d.get("image")
    unit = d.get("measure_unit") or None
    return make_product(STORE["id"], sku, d.get("display_name") or d.get("name") or "",
                        d.get("active_price") or d.get("price"),
                        brand=d.get("brand"), category=d.get("section"), subcategory=d.get("family"),
                        unit_price=d.get("price_per_unit"), unit=unit,
                        size=d.get("sell_pack_unit") or None, image=image,
                        previous_price=d.get("strikethrough_price") or d.get("list_price"),
                        promo=(d.get("promotion") or {}).get("text") if isinstance(d.get("promotion"), dict) else None,
                        ean=d.get("ean13"), url=url)


def fetch() -> list:
    base = {"scope": "desktop", "lang": "es", "rows": ROWS, "origin": "default", "f.op": "OR"}
    raw = _probe(dict(base, query=QUERIES[0], start=0))
    try:
        first = json.loads(raw.decode("utf-8"))
    except ValueError:
        raise RuntimeError("blocked: %s answered non-JSON (%r)" % (SEARCH, raw[:120]))

    products: List[Optional[Dict[str, Any]]] = []
    for q in QUERIES:
        start = 0
        while True:
            data = first if (q == QUERIES[0] and start == 0) else json.loads(
                _probe(dict(base, query=q, start=start)).decode("utf-8"))
            docs = _docs(data)
            products.extend(_build(d) for d in docs)
            start += ROWS
            if len(docs) < ROWS or start >= 2000:
                break
            if LIMIT and len(products) >= LIMIT:
                break
        if LIMIT and len(products) >= LIMIT:
            break
    out = dedupe(products)
    if not out:
        raise RuntimeError("blocked or changed: %s returned no parsable products" % SEARCH)
    return out[:LIMIT] if LIMIT else out
