#!/usr/bin/env bash
# ============================================================================
#  v35-back-no-persistir-estado.sh  — coworking-back
#
#  PROBLEMA: OcupacionService marca area.estado = OCUPADO al crear y
#  area.estado = LIBRE al liberar. Eso desincroniza el estado porque
#  no considera si la ocupación ya empezó o no.
#
#  SOLUCIÓN: Eliminar TODOS los updateMany de area.estado en
#  OcupacionService. El estado se calcula 100% en tiempo real desde
#  GET /areas/estado-actual (basado en fechaDesde/Hasta + horaDesde/Hasta).
#
#  ⚠️  Sin cambios en el schema — no requiere migración.
# ============================================================================
set -euo pipefail

[[ -f "package.json" && -d "src" ]] || {
  echo "❌  Corré desde la raíz de coworking-back"
  exit 1
}

echo "════════════════════════════════════════════════════════"
echo "  v35-back-no-persistir-estado  |  coworking-back"
echo "════════════════════════════════════════════════════════"
echo ""

# ── src/ocupacion/ocupacion.service.ts ───────────────────────────────────────
echo "📝  Actualizando ocupacion.service.ts..."
cat > src/ocupacion/ocupacion.service.ts << 'EOF'
import {
  Injectable,
  BadRequestException,
  NotFoundException,
} from '@nestjs/common';
import { PrismaService } from 'prisma/prisma.service';
import { CreateOcupacionDto } from './dto/create-ocupacion.dto';
import { UpdateOcupacionDto } from './dto/update-ocupacion.dto';

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
  // NO toca area.estado — el estado se calcula en tiempo real
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

    const areas = await this.prisma.area.findMany({ where: { id: { in: areaIds } } });
    if (areas.length !== areaIds.length) {
      const encontrados = areas.map((a) => a.id);
      const faltantes   = areaIds.filter((id) => !encontrados.includes(id));
      throw new NotFoundException(`Área(s) no encontrada(s): ${faltantes.join(', ')}`);
    }

    await this._validarConflictos(areaIds, fechaDesdeDate, fechaHastaDate, horaDesde, horaHasta);

    // Solo crea la ocupación — NO modifica area.estado
    return this.prisma.ocupacion.create({
      data: {
        ...rest,
        telefono: telefono ?? undefined,
        fechaDesde: fechaDesdeDate,
        fechaHasta: fechaHastaDate,
        horaDesde,
        horaHasta,
        areas: { create: areaIds.map((areaId) => ({ areaId })) },
      },
      include: { areas: { include: { area: true } } },
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
      where: { liberadaAt: null, fechaHasta: { gte: hoy } },
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
  // NO toca area.estado — el estado se calcula en tiempo real
  async update(id: number, dto: UpdateOcupacionDto) {
    const oc = await this.findOne(id);

    const {
      areaIds, fechaDesde, fechaHasta,
      horaDesde, horaHasta, telefono, ...rest
    } = dto;

    const fechaDesdeDate = fechaDesde
      ? new Date(`${fechaDesde}T00:00:00.000Z`)
      : oc.fechaDesde;
    const fechaHastaDate = fechaHasta
      ? new Date(`${fechaHasta}T00:00:00.000Z`)
      : oc.fechaHasta;

    const horaDesdeEfectiva = horaDesde ?? oc.horaDesde;
    const horaHastaEfectiva = horaHasta ?? oc.horaHasta;

    if (fechaDesdeDate > fechaHastaDate) {
      throw new BadRequestException('fechaDesde no puede ser posterior a fechaHasta');
    }
    if (timeToMinutes(horaDesdeEfectiva) >= timeToMinutes(horaHastaEfectiva)) {
      throw new BadRequestException('horaDesde debe ser anterior a horaHasta');
    }

    const areaIdsEfectivos = areaIds ?? oc.areas.map((r) => r.areaId);

    const cambiaHorario =
      areaIds !== undefined ||
      fechaDesde !== undefined ||
      fechaHasta !== undefined ||
      horaDesde !== undefined ||
      horaHasta !== undefined;

    if (cambiaHorario) {
      if (areaIds !== undefined) {
        const areas = await this.prisma.area.findMany({ where: { id: { in: areaIds } } });
        if (areas.length !== areaIds.length) {
          const faltantes = areaIds.filter((aid) => !areas.find((a) => a.id === aid));
          throw new NotFoundException(`Área(s) no encontrada(s): ${faltantes.join(', ')}`);
        }
      }

      await this._validarConflictos(
        areaIdsEfectivos,
        fechaDesdeDate,
        fechaHastaDate,
        horaDesdeEfectiva,
        horaHastaEfectiva,
        id,
      );
    }

    // Solo actualiza la ocupación — NO modifica area.estado
    return this.prisma.ocupacion.update({
      where: { id },
      data: {
        ...rest,
        ...(telefono !== undefined && { telefono: telefono || null }),
        fechaDesde: fechaDesdeDate,
        fechaHasta: fechaHastaDate,
        horaDesde:  horaDesdeEfectiva,
        horaHasta:  horaHastaEfectiva,
        ...(areaIds !== undefined && {
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
  // NO toca area.estado — el estado se calcula en tiempo real
  async liberar(id: number) {
    await this.findOne(id);

    return this.prisma.ocupacion.update({
      where: { id },
      data:  { liberadaAt: new Date() },
      include: { areas: { include: { area: true } } },
    });
  }

  // ── REMOVE ─────────────────────────────────────────────────────────────────
  // NO toca area.estado — el estado se calcula en tiempo real
  async remove(id: number) {
    await this.findOne(id);

    await this.prisma.ocupacionArea.deleteMany({ where: { ocupacionId: id } });
    return this.prisma.ocupacion.delete({ where: { id } });
  }

  // ── helper: valida conflictos de horario ───────────────────────────────────
  private async _validarConflictos(
    areaIds: number[],
    fechaDesdeDate: Date,
    fechaHastaDate: Date,
    horaDesde: string,
    horaHasta: string,
    excluirId?: number,
  ) {
    const existentes = await this.prisma.ocupacion.findMany({
      where: {
        liberadaAt: null,
        areas: { some: { areaId: { in: areaIds } } },
        ...(excluirId !== undefined && { id: { not: excluirId } }),
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
      throw new BadRequestException(
        `Conflicto de horario: las áreas [${areasConflicto.join(', ')}] ya están reservadas para la ocupación "${conflictivas[0].titulo}"`,
      );
    }
  }
}
EOF
echo "  ✅  ocupacion.service.ts — sin updateMany de area.estado"

echo ""
echo "🔨  Build de verificación..."
pnpm build

echo ""
echo "✅  v35-back-no-persistir-estado completado"
echo ""
echo "  Cambios:"
echo "   • create()  — ya NO hace updateMany OCUPADO"
echo "   • update()  — ya NO hace updateMany LIBRE/OCUPADO"
echo "   • liberar() — ya NO hace updateMany LIBRE"
echo "   • remove()  — ya NO hace updateMany LIBRE"
echo ""
echo "  El estado de las áreas ahora se calcula 100% en tiempo real"
echo "  desde GET /areas/estado-actual usando fechaDesde/Hasta + horaDesde/Hasta"