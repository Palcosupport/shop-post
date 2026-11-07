#!/bin/bash
# Lee Eroski desde este Mac y publica los precios en GitHub.
# Eroski bloquea los servidores de GitHub Actions (HTTP 403), así que esta tienda
# se actualiza aquí. Lo ejecuta launchd cada día (scripts/com.shoppost.eroski.plist).
#
# Usa una copia del repositorio en ~/Library/Application Support/ShopPost/repo
# (no depende del disco externo) y el gh de ~/Library/Application Support/ShopPost/bin.
set -euo pipefail

BASE="$HOME/Library/Application Support/ShopPost"
REPO="$BASE/repo"
export PATH="$BASE/bin:/usr/bin:/bin:/usr/sbin:/sbin"

echo "== $(date '+%F %T') Eroski"
cd "$REPO"
git pull -q --rebase -X theirs

/usr/bin/python3 server/run.py eroski

git add docs/data server/history
if git diff --cached --quiet; then
  echo "Sin cambios"
  exit 0
fi
git commit -q -m "Precios Eroski $(date +%F)"

# Si GitHub Actions ha subido algo mientras tanto, se integra y se reintenta.
for attempt in 1 2 3; do
  if git push -q; then
    echo "Publicado"
    exit 0
  fi
  sleep 20
  git pull -q --rebase -X theirs
done
echo "No se pudo publicar" >&2
exit 1
