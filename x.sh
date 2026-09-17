#!/usr/bin/env bash
# ============================================================================
#  v26b-back-telefono-fix.sh  — coworking-back
#  Fix TS: telefono ?? null → telefono ?? undefined
# ============================================================================
set -euo pipefail

[[ -f "package.json" && -d "src" ]] || { echo "❌ Corré desde la raíz de coworking-back"; exit 1; }

echo "🔧  Fixing tipo telefono en ocupacion.service.ts..."

sed -i 's/telefono: telefono ?? null,/telefono: telefono ?? undefined,/' src/ocupacion/ocupacion.service.ts

echo "✅  Fix aplicado"
echo ""
echo "🔨  Build..."
pnpm build

echo ""
echo "✅  v26b completado"