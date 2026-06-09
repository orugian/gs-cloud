#!/usr/bin/env bash
# Empacota a Lambda (handler + pymysql) em lambda/build/ingest.zip
# Uso: ./build.sh   (precisa de Python 3.12 e pip)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$ROOT/lambda/ingest"
STAGING="$ROOT/lambda/build/ingest"
ZIP="$ROOT/lambda/build/ingest.zip"

echo "==> Limpando build anterior"
rm -rf "$ROOT/lambda/build"
mkdir -p "$STAGING"

echo "==> Instalando dependencias"
pip install -r "$SRC/requirements.txt" -t "$STAGING" --quiet

echo "==> Copiando handler"
cp "$SRC/handler.py" "$STAGING/"

echo "==> Gerando $ZIP"
( cd "$STAGING" && zip -qr "$ZIP" . )

echo "OK -> $ZIP"
