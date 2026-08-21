/*
  Warnings:

  - The values [LIMPIANDO,FUERA_DE_SERVICIO,PARA_COMPARTIR,COMPARTIDO] on the enum `AreaStatus` will be removed. If these variants are still used in the database, this will fail.

*/
-- AlterEnum
BEGIN;
CREATE TYPE "AreaStatus_new" AS ENUM ('LIBRE', 'OCUPADO');
ALTER TABLE "public"."Area" ALTER COLUMN "estado" DROP DEFAULT;
ALTER TABLE "Area" ALTER COLUMN "estado" TYPE "AreaStatus_new" USING ("estado"::text::"AreaStatus_new");
ALTER TYPE "AreaStatus" RENAME TO "AreaStatus_old";
ALTER TYPE "AreaStatus_new" RENAME TO "AreaStatus";
DROP TYPE "public"."AreaStatus_old";
ALTER TABLE "Area" ALTER COLUMN "estado" SET DEFAULT 'LIBRE';
COMMIT;

-- CreateTable
CREATE TABLE "Ocupacion" (
    "id" SERIAL NOT NULL,
    "titulo" TEXT NOT NULL,
    "requerimiento" TEXT NOT NULL,
    "cantidadPersonas" INTEGER NOT NULL,
    "organizador" TEXT NOT NULL,
    "dia" TEXT NOT NULL,
    "hora" TEXT NOT NULL,
    "edadMin" INTEGER,
    "edadMax" INTEGER,
    "anexos" TEXT[],
    "liberadaAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "Ocupacion_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "OcupacionArea" (
    "ocupacionId" INTEGER NOT NULL,
    "areaId" INTEGER NOT NULL,

    CONSTRAINT "OcupacionArea_pkey" PRIMARY KEY ("ocupacionId","areaId")
);

-- AddForeignKey
ALTER TABLE "OcupacionArea" ADD CONSTRAINT "OcupacionArea_ocupacionId_fkey" FOREIGN KEY ("ocupacionId") REFERENCES "Ocupacion"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "OcupacionArea" ADD CONSTRAINT "OcupacionArea_areaId_fkey" FOREIGN KEY ("areaId") REFERENCES "Area"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
