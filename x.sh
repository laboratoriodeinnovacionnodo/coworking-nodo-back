#!/usr/bin/env bash
# ============================================================================
#  v26-back-telefono.sh  — coworking-back
#  Agrega campo `telefono` (opcional) a Ocupacion.
#
#  ⚠️  ANTES de correr este script:
#     1. Editá prisma/schema.prisma y agregá en el model Ocupacion:
#           telefono  String?
#        (después de `organizador String`)
#     2. Corré la migración manualmente:
#           pnpm prisma migrate dev --name add_telefono_ocupacion
#     3. Recién entonces ejecutá este script.
# ============================================================================
set -euo pipefail

# ── Colores ────────────────────────────────────────────────────────────────
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; RESET='\033[0m'
ok()   { echo -e "${GREEN}✅  $*${RESET}"; }
warn() { echo -e "${YELLOW}⚠️   $*${RESET}"; }
fail() { echo -e "${RED}❌  $*${RESET}"; exit 1; }

# ── Guardia ────────────────────────────────────────────────────────────────
[[ -f "package.json" && -d "src" ]] || fail "Corré desde la raíz de coworking-back"

echo ""
echo "════════════════════════════════════════════════════════════"
echo "  v26 · coworking-back · campo telefono en Ocupacion"
echo "════════════════════════════════════════════════════════════"
echo ""

# ── 1. create-ocupacion.dto.ts ─────────────────────────────────────────────
echo "📄  src/ocupacion/dto/create-ocupacion.dto.ts"
cat > src/ocupacion/dto/create-ocupacion.dto.ts << 'TSEOF'
import {
  IsString,
  IsOptional,
  IsInt,
  IsArray,
  IsUrl,
  IsDateString,
  Matches,
  Min,
  Max,
  MinLength,
  ArrayMinSize,
  ArrayMaxSize,
} from 'class-validator';
import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { Type } from 'class-transformer';

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
TSEOF
ok "create-ocupacion.dto.ts"

# ── 2. update-ocupacion.dto.ts ─────────────────────────────────────────────
echo "📄  src/ocupacion/dto/update-ocupacion.dto.ts"
cat > src/ocupacion/dto/update-ocupacion.dto.ts << 'TSEOF'
import { PartialType } from '@nestjs/swagger';
import { CreateOcupacionDto } from './create-ocupacion.dto';
export class UpdateOcupacionDto extends PartialType(CreateOcupacionDto) {}
TSEOF
ok "update-ocupacion.dto.ts"

# ── 3. ocupacion.service.ts ────────────────────────────────────────────────
echo "📄  src/ocupacion/ocupacion.service.ts"
cat > src/ocupacion/ocupacion.service.ts << 'TSEOF'
import {
  Injectable,
  BadRequestException,
  NotFoundException,
} from '@nestjs/common';
import { PrismaService } from 'prisma/prisma.service';
import { CreateOcupacionDto } from './dto/create-ocupacion.dto';
import { UpdateOcupacionDto } from './dto/update-ocupacion.dto';
import { AreaStatus } from '@prisma/client';

// ── helpers ──────────────────────────────────────────────────────────────────
function timeToMinutes(hhmm: string): number {
  const [h, m] = hhmm.split(':').map(Number);
  return h * 60 + m;
}

function rangosSolapan(
  aDesde: Date, aHasta: Date, aHoraDesde: string, aHoraHasta: string,
  bDesde: Date, bHasta: Date, bHoraDesde: string, bHoraHasta: string,
): boolean {
  const aD = aDesde.toISOString().split('T')[0];
  const aH = aHasta.toISOString().split('T')[0];
  const bD = bDesde.toISOString().split('T')[0];
  const bH = bHasta.toISOString().split('T')[0];

  if (aD > bH || aH < bD) return false;

  const aDesdeMin = timeToMinutes(aHoraDesde);
  const aHastaMin = timeToMinutes(aHoraHasta);
  const bDesdeMin = timeToMinutes(bHoraDesde);
  const bHastaMin = timeToMinutes(bHoraHasta);

  return aDesdeMin < bHastaMin && aHastaMin > bDesdeMin;
}

// ── service ──────────────────────────────────────────────────────────────────
@Injectable()
export class OcupacionService {
  constructor(private prisma: PrismaService) {}

  // ── CREATE ─────────────────────────────────────────────────────────────────
  async create(dto: CreateOcupacionDto) {
    const { areaIds, fechaDesde, fechaHasta, horaDesde, horaHasta, telefono, ...rest } = dto;

    const fechaDesdeDate = new Date(`${fechaDesde}T00:00:00.000Z`);
    const fechaHastaDate = new Date(`${fechaHasta}T00:00:00.000Z`);

    if (fechaDesdeDate > fechaHastaDate) {
      throw new BadRequestException('fechaDesde no puede ser posterior a fechaHasta');
    }
    if (timeToMinutes(horaDesde) >= timeToMinutes(horaHasta)) {
      throw new BadRequestException('horaDesde debe ser anterior a horaHasta');
    }

    // Verificar que todas las áreas existen
    const areas = await this.prisma.area.findMany({ where: { id: { in: areaIds } } });
    if (areas.length !== areaIds.length) {
      const encontrados = areas.map((a) => a.id);
      const faltantes   = areaIds.filter((id) => !encontrados.includes(id));
      throw new NotFoundException(`Área(s) no encontrada(s): ${faltantes.join(', ')}`);
    }

    // Verificar conflictos de horario con ocupaciones activas
    const existentes = await this.prisma.ocupacion.findMany({
      where: {
        liberadaAt: null,
        areas: { some: { areaId: { in: areaIds } } },
      },
      include: { areas: true },
    });

    const conflictivas = existentes.filter((oc) =>
      rangosSolapan(
        fechaDesdeDate, fechaHastaDate, horaDesde, horaHasta,
        oc.fechaDesde,  oc.fechaHasta,  oc.horaDesde, oc.horaHasta,
      ),
    );

    if (conflictivas.length > 0) {
      const areasConflicto = [
        ...new Set(
          conflictivas.flatMap((oc) =>
            oc.areas
              .filter((r) => areaIds.includes(r.areaId))
              .map((r) => r.areaId),
          ),
        ),
      ];
      const nombreConflicto = conflictivas[0].titulo;
      throw new BadRequestException(
        `Conflicto de horario: las áreas [${areasConflicto.join(', ')}] ya están reservadas para la ocupación "${nombreConflicto}"`,
      );
    }

    // Crear ocupación y relaciones en una transacción
    return this.prisma.$transaction(async (tx) => {
      const ocupacion = await tx.ocupacion.create({
        data: {
          ...rest,
          telefono: telefono ?? null,
          fechaDesde: fechaDesdeDate,
          fechaHasta: fechaHastaDate,
          horaDesde,
          horaHasta,
          areas: {
            create: areaIds.map((areaId) => ({ areaId })),
          },
        },
        include: { areas: { include: { area: true } } },
      });

      // Marcar áreas como OCUPADO
      await tx.area.updateMany({
        where: { id: { in: areaIds } },
        data:  { estado: AreaStatus.OCUPADO },
      });

      return ocupacion;
    });
  }

  // ── FIND ALL ───────────────────────────────────────────────────────────────
  findAll() {
    return this.prisma.ocupacion.findMany({
      orderBy: { createdAt: 'desc' },
      include: { areas: { include: { area: true } } },
    });
  }

  // ── FIND ACTIVAS ───────────────────────────────────────────────────────────
  findActivas() {
    const hoy = new Date();
    hoy.setUTCHours(0, 0, 0, 0);
    return this.prisma.ocupacion.findMany({
      where: {
        liberadaAt: null,
        fechaHasta: { gte: hoy },
      },
      orderBy: { fechaDesde: 'asc' },
      include: { areas: { include: { area: true } } },
    });
  }

  // ── FIND ONE ───────────────────────────────────────────────────────────────
  async findOne(id: number) {
    const oc = await this.prisma.ocupacion.findUnique({
      where: { id },
      include: { areas: { include: { area: true } } },
    });
    if (!oc) throw new NotFoundException('Ocupación no encontrada');
    return oc;
  }

  // ── UPDATE ─────────────────────────────────────────────────────────────────
  async update(id: number, dto: UpdateOcupacionDto) {
    await this.findOne(id);

    const { areaIds, fechaDesde, fechaHasta, horaDesde, horaHasta, telefono, ...rest } = dto;

    const fechaDesdeDate = fechaDesde ? new Date(`${fechaDesde}T00:00:00.000Z`) : undefined;
    const fechaHastaDate = fechaHasta ? new Date(`${fechaHasta}T00:00:00.000Z`) : undefined;

    return this.prisma.ocupacion.update({
      where: { id },
      data: {
        ...rest,
        ...(telefono !== undefined && { telefono }),
        ...(fechaDesdeDate && { fechaDesde: fechaDesdeDate }),
        ...(fechaHastaDate && { fechaHasta: fechaHastaDate }),
        ...(horaDesde && { horaDesde }),
        ...(horaHasta && { horaHasta }),
        ...(areaIds && {
          areas: {
            deleteMany: {},
            create: areaIds.map((areaId) => ({ areaId })),
          },
        }),
      },
      include: { areas: { include: { area: true } } },
    });
  }

  // ── LIBERAR ────────────────────────────────────────────────────────────────
  async liberar(id: number) {
    const oc = await this.findOne(id);

    return this.prisma.$transaction(async (tx) => {
      const liberada = await tx.ocupacion.update({
        where: { id },
        data:  { liberadaAt: new Date() },
        include: { areas: { include: { area: true } } },
      });

      const areaIds = oc.areas.map((r) => r.areaId);
      await tx.area.updateMany({
        where: { id: { in: areaIds } },
        data:  { estado: AreaStatus.LIBRE },
      });

      return liberada;
    });
  }

  // ── REMOVE ─────────────────────────────────────────────────────────────────
  async remove(id: number) {
    const oc = await this.findOne(id);

    return this.prisma.$transaction(async (tx) => {
      await tx.ocupacionArea.deleteMany({ where: { ocupacionId: id } });

      const removed = await tx.ocupacion.delete({ where: { id } });

      const areaIds = oc.areas.map((r) => r.areaId);
      await tx.area.updateMany({
        where: { id: { in: areaIds } },
        data:  { estado: AreaStatus.LIBRE },
      });

      return removed;
    });
  }
}
TSEOF
ok "ocupacion.service.ts"

# ── 4. Verificar TypeScript ────────────────────────────────────────────────
echo ""
echo "🔨  Verificando TypeScript..."
pnpm exec tsc --noEmit --skipLibCheck 2>&1 | head -40 || true

# ── 5. Build ───────────────────────────────────────────────────────────────
echo ""
echo "🔨  Build de producción..."
pnpm build

# ── Resumen ────────────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}════════════════════════════════════════════════════════════${RESET}"
echo -e "${GREEN}  ✅  v26 coworking-back completado                        ${RESET}"
echo -e "${GREEN}════════════════════════════════════════════════════════════${RESET}"
echo ""
echo "  Archivos modificados:"
echo "    src/ocupacion/dto/create-ocupacion.dto.ts  → campo telefono? añadido"
echo "    src/ocupacion/dto/update-ocupacion.dto.ts  → hereda de PartialType"
echo "    src/ocupacion/ocupacion.service.ts         → persiste telefono"
echo ""
echo -e "${YELLOW}  ⚠️  Recordatorio schema (manual):${RESET}"
echo "    En prisma/schema.prisma, model Ocupacion, agregar:"
echo "      telefono  String?"
echo "    Luego: pnpm prisma migrate dev --name add_telefono_ocupacion"
echo ""