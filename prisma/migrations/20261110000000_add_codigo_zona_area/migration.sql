-- CreateEnum
CREATE TYPE "CodigoArea" AS ENUM ('A1', 'A2', 'B1', 'B2', 'B3', 'B4', 'C1', 'C2', 'C3');

-- CreateEnum
CREATE TYPE "ZonaArea" AS ENUM ('SILLONES_NARANJAS', 'SILLONES_ROJOS', 'SEMICIRCULOS_NEGROS');

-- AlterTable
ALTER TABLE "Area" ADD COLUMN "codigo" "CodigoArea",
ADD COLUMN "zona" "ZonaArea";

-- CreateIndex
CREATE UNIQUE INDEX "Area_codigo_key" ON "Area"("codigo");
