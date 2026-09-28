#!/usr/bin/env bash
# ============================================================================
#  v31-back-gmail-reserva.sh  — coworking-back
#  Agrega campo gmail (String?) a Reserva en DTOs y service.
#
#  ⚠️  ANTES de correr este script:
#    En prisma/schema.prisma, dentro de model Reserva agregá:
#      gmail      String?
#    Luego:
#      pnpm prisma migrate dev --name add_gmail_reserva
# ============================================================================
set -euo pipefail

[[ -f "package.json" && -d "src" ]] || { echo "❌  Corré desde la raíz de coworking-back"; exit 1; }

echo "════════════════════════════════════════════════════════"
echo "  v31-back-gmail-reserva  |  coworking-back"
echo "════════════════════════════════════════════════════════"
echo ""

# ── src/reserva/dto/create-reserva.dto.ts ────────────────────────────────────
echo "📝  Actualizando create-reserva.dto.ts..."
cat > src/reserva/dto/create-reserva.dto.ts << 'EOF'
import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { IsEmail, IsEnum, IsInt, IsOptional, IsString } from 'class-validator';
import { Recepcion } from '@prisma/client';

export class CreateReservaDto {
  @ApiProperty({ description: 'Nombre del cliente que reserva' })
  @IsString()
  nombre: string;

  @ApiPropertyOptional({ description: 'Gmail del cliente' })
  @IsOptional()
  @IsEmail()
  gmail?: string;

  @ApiPropertyOptional({ description: 'Datos adicionales de la reserva' })
  @IsOptional()
  @IsString()
  detalles?: string;

  @ApiProperty({ description: 'ID del usuario' })
  @IsInt()
  usuarioId: number;

  @ApiProperty({ description: 'ID del área a reservar' })
  @IsInt()
  areaId: number;

  @ApiPropertyOptional({
    enum: Recepcion,
    description: 'Turno de recepción: MANANA | INTERMEDIO | TARDE',
  })
  @IsOptional()
  @IsEnum(Recepcion)
  recepcion?: Recepcion;

  @ApiPropertyOptional({ description: 'Nombre de quien recibe al cliente en recepción' })
  @IsOptional()
  @IsString()
  receptor?: string;
}
EOF
echo "  ✅  create-reserva.dto.ts listo"

# ── src/reserva/dto/update-reserva.dto.ts ────────────────────────────────────
echo "📝  Actualizando update-reserva.dto.ts..."
cat > src/reserva/dto/update-reserva.dto.ts << 'EOF'
import { ApiPropertyOptional } from '@nestjs/swagger';
import { IsEmail, IsEnum, IsInt, IsOptional, IsString } from 'class-validator';
import { Recepcion } from '@prisma/client';

export class UpdateReservaDto {
  @ApiPropertyOptional({ description: 'Nombre del cliente' })
  @IsOptional()
  @IsString()
  nombre?: string;

  @ApiPropertyOptional({ description: 'Gmail del cliente' })
  @IsOptional()
  @IsEmail()
  gmail?: string;

  @ApiPropertyOptional({ description: 'Datos adicionales' })
  @IsOptional()
  @IsString()
  detalles?: string;

  @ApiPropertyOptional({ description: 'Nuevo ID de área (reasignación)' })
  @IsOptional()
  @IsInt()
  areaId?: number;

  @ApiPropertyOptional({
    enum: Recepcion,
    description: 'Turno de recepción: MANANA | INTERMEDIO | TARDE',
  })
  @IsOptional()
  @IsEnum(Recepcion)
  recepcion?: Recepcion;

  @ApiPropertyOptional({ description: 'Nombre de quien recibe al cliente en recepción' })
  @IsOptional()
  @IsString()
  receptor?: string;
}
EOF
echo "  ✅  update-reserva.dto.ts listo"

echo ""
echo "🔨  Build de verificación..."
pnpm build

echo ""
echo "✅  v31-back-gmail-reserva completado"