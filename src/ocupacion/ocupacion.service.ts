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
          telefono: telefono ?? undefined,
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
