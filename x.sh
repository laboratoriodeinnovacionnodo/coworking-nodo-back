#!/usr/bin/env bash
# ============================================================================
#  v32-back-ocupacion-gmail-recepcion.sh  — coworking-back
#
#  Agrega gmail, recepcion y receptor a Ocupacion (DTO + service).
#
#  ⚠️  ANTES de correr este script, en prisma/schema.prisma
#      dentro de model Ocupacion agregá:
#        gmail      String?
#        recepcion  Recepcion?
#        receptor   String?
#
#      Luego migrá:
#        pnpm prisma migrate dev --name add_gmail_recepcion_receptor_ocupacion
# ============================================================================
set -euo pipefail

[[ -f "package.json" && -d "src" ]] || { echo "❌  Corré desde la raíz de coworking-back"; exit 1; }

echo "════════════════════════════════════════════════════════"
echo "  v32-back-ocupacion-gmail-recepcion  |  coworking-back"
echo "════════════════════════════════════════════════════════"
echo ""

# ── src/ocupacion/dto/create-ocupacion.dto.ts ─────────────────────────────────
echo "📝  Actualizando create-ocupacion.dto.ts..."
cat > src/ocupacion/dto/create-ocupacion.dto.ts << 'EOF'
import {
  IsString,
  IsOptional,
  IsInt,
  IsArray,
  IsUrl,
  IsDateString,
  IsEmail,
  IsEnum,
  Matches,
  Min,
  Max,
  MinLength,
  ArrayMinSize,
  ArrayMaxSize,
} from 'class-validator';
import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { Type } from 'class-transformer';
import { Recepcion } from '@prisma/client';

export class CreateOcupacionDto {
  @ApiProperty({ description: 'Título del evento / ocupación' })
  @IsString()
  @MinLength(3)
  titulo: string;

  @ApiProperty({ description: 'Requerimientos o descripción' })
  @IsString()
  @MinLength(3)
  requerimiento: string;

  @ApiProperty({ description: 'Cantidad estimada de personas' })
  @Type(() => Number)
  @IsInt()
  @Min(1)
  cantidadPersonas: number;

  @ApiProperty({ description: 'Nombre del organizador / solicitante' })
  @IsString()
  @MinLength(2)
  organizador: string;

  @ApiPropertyOptional({ description: 'Teléfono de contacto del organizador' })
  @IsOptional()
  @IsString()
  telefono?: string;

  @ApiPropertyOptional({ description: 'Gmail del organizador' })
  @IsOptional()
  @IsEmail()
  gmail?: string;

  @ApiPropertyOptional({
    enum: Recepcion,
    description: 'Turno de recepción del evento: MANANA | INTERMEDIO | TARDE',
  })
  @IsOptional()
  @IsEnum(Recepcion)
  recepcion?: Recepcion;

  @ApiPropertyOptional({ description: 'Nombre de quien recibe al grupo en recepción' })
  @IsOptional()
  @IsString()
  receptor?: string;

  @ApiProperty({ example: '2026-08-25', description: 'Fecha de inicio (YYYY-MM-DD)' })
  @IsDateString()
  fechaDesde: string;

  @ApiProperty({ example: '2026-08-25', description: 'Fecha de fin (YYYY-MM-DD)' })
  @IsDateString()
  fechaHasta: string;

  @ApiProperty({ example: '09:00', description: 'Hora de inicio (HH:mm)' })
  @IsString()
  @Matches(/^([0-1]?\d|2[0-3]):[0-5]\d$/, { message: 'horaDesde debe ser HH:mm' })
  horaDesde: string;

  @ApiProperty({ example: '12:00', description: 'Hora de fin (HH:mm)' })
  @IsString()
  @Matches(/^([0-1]?\d|2[0-3]):[0-5]\d$/, { message: 'horaHasta debe ser HH:mm' })
  horaHasta: string;

  @ApiPropertyOptional({ description: 'Edad mínima del público' })
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(0)
  @Max(120)
  edadMin?: number;

  @ApiPropertyOptional({ description: 'Edad máxima del público' })
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(0)
  @Max(120)
  edadMax?: number;

  @ApiPropertyOptional({ description: 'URLs de anexos / documentos', type: [String] })
  @IsOptional()
  @IsArray()
  @ArrayMaxSize(10)
  @IsUrl({}, { each: true })
  anexos?: string[];

  @ApiProperty({ description: 'IDs de las áreas a ocupar', type: [Number] })
  @IsArray()
  @ArrayMinSize(1)
  @Type(() => Number)
  @IsInt({ each: true })
  areaIds: number[];
}
EOF
echo "  ✅  create-ocupacion.dto.ts listo"

# ── src/ocupacion/dto/update-ocupacion.dto.ts ────────────────────────────────
echo "📝  Actualizando update-ocupacion.dto.ts..."
cat > src/ocupacion/dto/update-ocupacion.dto.ts << 'EOF'
import { PartialType } from '@nestjs/swagger';
import { CreateOcupacionDto } from './create-ocupacion.dto';
export class UpdateOcupacionDto extends PartialType(CreateOcupacionDto) {}
EOF
echo "  ✅  update-ocupacion.dto.ts listo"

# ── src/ocupacion/ocupacion.service.ts — propagar nuevos campos ───────────────
# El service no necesita cambios: usa spread (...rest) para todos los campos
# del DTO y Prisma los persiste automáticamente.
# Solo verificamos que el build compila correctamente.

echo ""
echo "🔨  Build de verificación..."
pnpm build

echo ""
echo "✅  v32-back-ocupacion-gmail-recepcion completado"