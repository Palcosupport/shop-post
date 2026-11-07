#!/usr/bin/env python3
"""Run every supermarket scraper and publish JSON for the Shop Post app.

Usage:
    python3 server/run.py                 # all stores
    python3 server/run.py mercadona dia   # only some stores
    python3 server/run.py --limit 50 dia  # quick test: stop after ~50 products per store (if supported)

Output (served by GitHub Pages from /docs):
    docs/data/meta.json        generation date, stores with status/count, categories
    docs/data/<store>.json     {"store", "updatedAt", "products": [...]}
    docs/data/changes.json     price drops/rises in the last 14 days, all stores
    docs/data/new.json         products first seen in the last 14 days, all stores
Persistent state (committed to the repo, not served):
    server/history/<store>.json  {id: {"first": date, "h": [[date, price], ...]}}
"""
import datetime as dt
import importlib
import json
import os
import sys
import time
import traceback
from typing import Any, Dict, List

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)

import common  # noqa: E402

DATA_DIR = os.path.join(ROOT, "docs", "data")
HIST_DIR = os.path.join(HERE, "history")
# Desactivados porque bloquean los accesos automatizados (no se intenta saltar el bloqueo):
#   carrefour (Cloudflare), dia (Akamai), alcampo (AWS WAF a las pocas peticiones).
# Sus módulos siguen en stores/ por si dejan de bloquear: python3 server/run.py dia
STORE_MODULES = ["mercadona", "consum", "eroski", "lidl"]
WINDOW_DAYS = 14
HISTORY_DAYS = 180


def load_json(path: str, default: Any) -> Any:
    try:
        with open(path, "r", encoding="utf-8") as f:
            return json.load(f)
    except (OSError, ValueError):
        return default


def save_json(path: str, data: Any, pretty: bool = False) -> None:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        if pretty:
            json.dump(data, f, ensure_ascii=False, indent=1)
        else:
            json.dump(data, f, ensure_ascii=False, separators=(",", ":"))
    os.replace(tmp, path)


def update_history(store_id: str, products: List[Dict[str, Any]], today: str) -> Dict[str, Any]:
    path = os.path.join(HIST_DIR, store_id + ".json")
    hist = load_json(path, {})
    cutoff = (dt.date.fromisoformat(today) - dt.timedelta(days=HISTORY_DAYS)).isoformat()
    for p in products:
        e = hist.setdefault(p["id"], {"first": today, "h": []})
        h = e["h"]
        if not h or h[-1][1] != p["price"]:
            if h and h[-1][0] == today:
                h[-1] = [today, p["price"]]
            else:
                h.append([today, p["price"]])
        # trim old points, but always keep the last one before the cutoff as reference
        while len(h) > 2 and h[1][0] < cutoff:
            h.pop(0)
        e["seen"] = today
    # forget products not seen for HISTORY_DAYS
    for pid in [k for k, v in hist.items() if v.get("seen", v["first"]) < cutoff]:
        del hist[pid]
    save_json(path, hist)
    return hist


def run_store(name: str, limit: int) -> Dict[str, Any]:
    mod = importlib.import_module("stores." + name)
    t0 = time.time()
    if limit and hasattr(mod, "LIMIT"):
        mod.LIMIT = limit
    products = common.dedupe(mod.fetch())
    return {"module": mod, "products": products, "seconds": round(time.time() - t0, 1)}


def main(argv: List[str]) -> int:
    limit = 0
    if "--limit" in argv:
        i = argv.index("--limit")
        limit = int(argv[i + 1])
        argv = argv[:i] + argv[i + 2:]
    names = argv or STORE_MODULES
    now = dt.datetime.now(dt.timezone.utc)
    today = now.date().isoformat()
    meta = load_json(os.path.join(DATA_DIR, "meta.json"), {"stores": []})
    baseline = meta.get("baseline", {})
    stores_meta = {s["id"]: s for s in meta.get("stores", [])}

    for name in names:
        print("==> %s" % name, flush=True)
        try:
            res = run_store(name, limit)
        except Exception as e:  # keep previous data when a store fails
            traceback.print_exc()
            prev = stores_meta.get(name, {"id": name, "name": name.title(), "count": 0})
            prev.update({"status": "error", "error": str(e)[:300], "checkedAt": now.isoformat()})
            stores_meta[name] = prev
            continue
        mod, products = res["module"], res["products"]
        store = mod.STORE
        if len(products) < 20:
            print("   only %d products, keeping previous data" % len(products))
            prev = stores_meta.get(store["id"], dict(store, count=0))
            prev.update({"status": "error", "error": "too few products (%d)" % len(products),
                         "checkedAt": now.isoformat()})
            stores_meta[store["id"]] = prev
            continue
        hist = update_history(store["id"], products, today)
        baseline.setdefault(store["id"], today)
        for p in products:
            h = hist[p["id"]]["h"]
            if len(h) >= 2:
                p["lastPrice"] = h[-2][1]
                p["changedAt"] = h[-1][0]
            p["firstSeen"] = hist[p["id"]]["first"]
        save_json(os.path.join(DATA_DIR, store["id"] + ".json"),
                  {"store": store["id"], "updatedAt": now.isoformat(), "products": products})
        stores_meta[store["id"]] = dict(store, status="ok", count=len(products), updatedAt=now.isoformat(),
                                        checkedAt=now.isoformat(), seconds=res["seconds"])
        print("   %d products in %ss" % (len(products), res["seconds"]), flush=True)

    # Las tiendas desactivadas desaparecen de la app.
    stores_meta = {k: v for k, v in stores_meta.items() if k in STORE_MODULES or k in names}

    # Cross-store feeds -----------------------------------------------------
    since = (now.date() - dt.timedelta(days=WINDOW_DAYS)).isoformat()
    changes: List[Dict[str, Any]] = []
    new: List[Dict[str, Any]] = []
    keep = ("id", "store", "name", "brand", "cat", "price", "unitPrice", "unit", "size", "image",
            "previousPrice", "promo")
    for sid in stores_meta:
        data = load_json(os.path.join(DATA_DIR, sid + ".json"), {"products": []})
        for p in data["products"]:
            if p.get("changedAt", "") >= since and p.get("lastPrice"):
                c = {k: p.get(k) for k in keep}
                c.update(oldPrice=p["lastPrice"], date=p["changedAt"],
                         pct=round((p["price"] - p["lastPrice"]) / p["lastPrice"] * 100, 1))
                changes.append(c)
            if p.get("firstSeen", "") >= since and p.get("firstSeen") != baseline.get(sid):
                n = {k: p.get(k) for k in keep}
                n["date"] = p["firstSeen"]
                new.append(n)
    changes.sort(key=lambda c: (c["date"], -abs(c["pct"])), reverse=True)
    new.sort(key=lambda n: n["date"], reverse=True)
    save_json(os.path.join(DATA_DIR, "changes.json"), {"updatedAt": now.isoformat(), "items": changes[:3000]})
    save_json(os.path.join(DATA_DIR, "new.json"), {"updatedAt": now.isoformat(), "items": new[:3000]})

    order = {n: i for i, n in enumerate(STORE_MODULES)}
    meta = {
        "version": 1,
        "updatedAt": now.isoformat(),
        "baseline": baseline,
        "stores": sorted(stores_meta.values(), key=lambda s: order.get(s["id"], 99)),
        "categories": [{"id": c[0], "name": c[1], "emoji": c[2]} for c in common.CATEGORIES],
    }
    save_json(os.path.join(DATA_DIR, "meta.json"), meta, pretty=True)
    ok = [s["id"] for s in meta["stores"] if s.get("status") == "ok"]
    print("done: %d stores ok (%s), %d changes, %d new" % (len(ok), ", ".join(ok), len(changes), len(new)))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
