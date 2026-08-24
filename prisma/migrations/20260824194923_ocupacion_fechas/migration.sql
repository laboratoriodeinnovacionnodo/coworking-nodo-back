-- Eliminar columnas viejas
ALTER TABLE "Ocupacion" DROP COLUMN IF EXISTS "dia";
ALTER TABLE "Ocupacion" DROP COLUMN IF EXISTS "hora";

-- Agregar nuevas con default temporal para filas existentes (tabla vacía, pero Prisma lo requiere)
ALTER TABLE "Ocupacion" ADD COLUMN "fechaDesde" TIMESTAMP(3) NOT NULL DEFAULT NOW();
ALTER TABLE "Ocupacion" ADD COLUMN "fechaHasta" TIMESTAMP(3) NOT NULL DEFAULT NOW();
ALTER TABLE "Ocupacion" ADD COLUMN "horaDesde"  TEXT NOT NULL DEFAULT '09:00';
ALTER TABLE "Ocupacion" ADD COLUMN "horaHasta"  TEXT NOT NULL DEFAULT '18:00';

-- Quitar los defaults (quedan como NOT NULL sin default, igual que el schema)
ALTER TABLE "Ocupacion" ALTER COLUMN "fechaDesde" DROP DEFAULT;
ALTER TABLE "Ocupacion" ALTER COLUMN "fechaHasta" DROP DEFAULT;
ALTER TABLE "Ocupacion" ALTER COLUMN "horaDesde"  DROP DEFAULT;
ALTER TABLE "Ocupacion" ALTER COLUMN "horaHasta"  DROP DEFAULT;