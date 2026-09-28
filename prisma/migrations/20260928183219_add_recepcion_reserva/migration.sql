-- CreateEnum
CREATE TYPE "Recepcion" AS ENUM ('MANANA', 'INTERMEDIO', 'TARDE');

-- AlterTable
ALTER TABLE "Reserva" ADD COLUMN     "recepcion" "Recepcion";
