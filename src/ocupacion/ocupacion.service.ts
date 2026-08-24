import {
  Injectable,
  NotFoundException,
  BadRequestException,
  Logger,
} from '@nestjs/common';
import { Cron } from '@nestjs/schedule';
import { PrismaService } from 'prisma/prisma.service';
import { CreateOcupacionDto } from './dto/create-ocupacion.dto';
import { UpdateOcupacionDto } from './dto/update-ocupacion.dto';
import { AreaStatus } from '@prisma/client';

// ── Helpers de tiempo ─────────────────────────────────────────────────────────

function timeToMinutes(hhmm: string): number {
  const [h, m] = hhmm.split(':').map(Number);
  return h * 60 + m;
}

/** Construye un DateTime UTC combinando fecha YYYY-MM-DD y hora HH:mm */
function buildDatetime(fecha: string, hora: string): Date {
  return new Date(`${fecha}T${hora}:00.000Z`);
}

/** Fecha local Argentina como YYYY-MM-DD (UTC-3) */
function hoyArgentina(): string {
  const ahora = new Date();
  ahora.setHours(ahora.getHours() - 3); // UTC-3
  return ahora.toISOString().split('T')[0];
}

@Injectable()
export class OcupacionService {
  private readonly logger = new Logger(OcupacionService.name);

  constructor(private readonly prisma: PrismaService) {}

  // ── Verifica conflicto de horario para un área ────────────────────────────
  private async verificarConflicto(
    areaIds: number[],
    fechaDesde: string,
    fechaHasta: string,
    horaDesde: string,
    horaHasta: string,
    excludeId?: number,
  ): Promise<void> {
    // Buscar ocupaciones activas (sin liberadaAt) que se superpongan en fecha
    const ocupacionesActivas = await this.prisma.ocupacion.findMany({
      where: {
        liberadaAt: null,
        ...(excludeId ? { id: { not: excludeId } } : {}),
        areas: { some: { areaId: { in: areaIds } } },
        // Superposición de rango de fechas
        AND: [
          { fechaDesde: { lte: new Date(`${fechaHasta}T23:59:59.000Z`) } },
          { fechaHasta: { gte: new Date(`${fechaDesde}T00:00:00.000Z`) } },
        ],
      },
      include: { areas: { include: { area: true } } },
    });

    // Para cada ocupación con fecha solapada, verificar superposición de horario
    const nuevaInicio = timeToMinutes(horaDesde);
    const nuevaFin    = timeToMinutes(horaHasta);

    for (const oc of ocupacionesActivas) {
      const existInicio = timeToMinutes(oc.horaDesde);
      const existFin    = timeToMinutes(oc.horaHasta);

      // Hay solapamiento si los rangos se intersectan
      const solapan = nuevaInicio < existFin && nuevaFin > existInicio;
      if (!solapan) continue;

      const areasConflicto = oc.areas
        .filter((r) => areaIds.includes(r.areaId))
        .map((r) => r.area.nombre)
        .join(', ');

      throw new BadRequestException(
        `Conflicto de horario: las áreas [${areasConflicto}] ya están ocupadas ` +
        `el ${oc.fechaDesde.toISOString().split('T')[0]} de ${oc.horaDesde} a ${oc.horaHasta} ` +
        `(ocupación "${oc.titulo}")`,
      );
    }
  }

  // ── CREATE ────────────────────────────────────────────────────────────────
  async create(dto: CreateOcupacionDto) {
    // Validaciones básicas
    if (dto.edadMin !== undefined && dto.edadMax !== undefined && dto.edadMin > dto.edadMax) {
      throw new BadRequestException('edadMin no puede ser mayor que edadMax');
    }
    if (dto.fechaDesde > dto.fechaHasta) {
      throw new BadRequestException('fechaDesde no puede ser posterior a fechaHasta');
    }
    if (dto.fechaDesde === dto.fechaHasta && dto.horaDesde >= dto.horaHasta) {
      throw new BadRequestException('horaDesde debe ser anterior a horaHasta');
    }

    // Verificar que las áreas existen
    const areas = await this.prisma.area.findMany({ where: { id: { in: dto.areaIds } } });
    if (areas.length !== dto.areaIds.length) {
      const missing = dto.areaIds.filter((id) => !areas.map((a) => a.id).includes(id));
      throw new NotFoundException(`Área(s) no encontrada(s): ${missing.join(', ')}`);
    }

    // Verificar conflicto de horario
    await this.verificarConflicto(dto.areaIds, dto.fechaDesde, dto.fechaHasta, dto.horaDesde, dto.horaHasta);

    // Crear ocupación + marcar áreas OCUPADO en transacción
    const ocupacion = await this.prisma.$transaction(async (tx) => {
      const nueva = await tx.ocupacion.create({
        data: {
          titulo:           dto.titulo,
          requerimiento:    dto.requerimiento,
          cantidadPersonas: dto.cantidadPersonas,
          organizador:      dto.organizador,
          fechaDesde:       new Date(`${dto.fechaDesde}T00:00:00.000Z`),
          fechaHasta:       new Date(`${dto.fechaHasta}T23:59:59.000Z`),
          horaDesde:        dto.horaDesde,
          horaHasta:        dto.horaHasta,
          edadMin:          dto.edadMin,
          edadMax:          dto.edadMax,
          anexos:           dto.anexos ?? [],
          areas: { create: dto.areaIds.map((areaId) => ({ areaId })) },
        },
        include: { areas: { include: { area: true } } },
      });

      await tx.area.updateMany({
        where: { id: { in: dto.areaIds } },
        data:  { estado: AreaStatus.OCUPADO },
      });

      return nueva;
    });

    return ocupacion;
  }

  // ── FIND ALL ──────────────────────────────────────────────────────────────
  findAll() {
    return this.prisma.ocupacion.findMany({
      orderBy: { fechaDesde: 'asc' },
      include: { areas: { include: { area: true } } },
    });
  }

  // ── FIND ACTIVAS (sin liberadaAt, desde hoy) ──────────────────────────────
  findActivas() {
    const hoy = new Date(`${hoyArgentina()}T00:00:00.000Z`);
    return this.prisma.ocupacion.findMany({
      where: {
        liberadaAt: null,
        fechaHasta: { gte: hoy },
      },
      orderBy: { fechaDesde: 'asc' },
      include: { areas: { include: { area: true } } },
    });
  }

  // ── FIND ONE ──────────────────────────────────────────────────────────────
  async findOne(id: number) {
    const ocupacion = await this.prisma.ocupacion.findUnique({
      where: { id },
      include: { areas: { include: { area: true } } },
    });
    if (!ocupacion) throw new NotFoundException(`Ocupación ${id} no encontrada`);
    return ocupacion;
  }

  // ── UPDATE ────────────────────────────────────────────────────────────────
  async update(id: number, dto: UpdateOcupacionDto) {
    const actual = await this.findOne(id);

    if (dto.edadMin !== undefined && dto.edadMax !== undefined && dto.edadMin > dto.edadMax) {
      throw new BadRequestException('edadMin no puede ser mayor que edadMax');
    }

    // Si cambió el horario/fecha, verificar conflictos excluyendo esta misma ocupación
    const fechaDesde = dto.fechaDesde ?? actual.fechaDesde.toISOString().split('T')[0];
    const fechaHasta = dto.fechaHasta ?? actual.fechaHasta.toISOString().split('T')[0];
    const horaDesde  = dto.horaDesde  ?? actual.horaDesde;
    const horaHasta  = dto.horaHasta  ?? actual.horaHasta;
    const areaIds    = dto.areaIds    ?? actual.areas.map((r) => r.areaId);

    if (dto.fechaDesde || dto.fechaHasta || dto.horaDesde || dto.horaHasta || dto.areaIds) {
      await this.verificarConflicto(areaIds, fechaDesde, fechaHasta, horaDesde, horaHasta, id);
    }

    // Si cambian las áreas, actualizar relaciones y estados
    if (dto.areaIds) {
      const anterioresIds = actual.areas.map((r) => r.areaId);
      await this.prisma.$transaction(async (tx) => {
        // Liberar áreas que ya no están
        const aLiberar = anterioresIds.filter((aid) => !dto.areaIds!.includes(aid));
        if (aLiberar.length > 0) {
          await tx.area.updateMany({ where: { id: { in: aLiberar } }, data: { estado: AreaStatus.LIBRE } });
        }
        // Ocupar áreas nuevas
        const aNuevas = dto.areaIds!.filter((aid) => !anterioresIds.includes(aid));
        if (aNuevas.length > 0) {
          await tx.area.updateMany({ where: { id: { in: aNuevas } }, data: { estado: AreaStatus.OCUPADO } });
        }
        // Reemplazar relaciones
        await tx.ocupacionArea.deleteMany({ where: { ocupacionId: id } });
        await tx.ocupacionArea.createMany({
          data: dto.areaIds!.map((areaId) => ({ ocupacionId: id, areaId })),
        });
      });
    }

    return this.prisma.ocupacion.update({
      where: { id },
      data: {
        ...(dto.titulo           !== undefined && { titulo:           dto.titulo }),
        ...(dto.requerimiento    !== undefined && { requerimiento:    dto.requerimiento }),
        ...(dto.cantidadPersonas !== undefined && { cantidadPersonas: dto.cantidadPersonas }),
        ...(dto.organizador      !== undefined && { organizador:      dto.organizador }),
        ...(dto.fechaDesde       !== undefined && { fechaDesde:       new Date(`${dto.fechaDesde}T00:00:00.000Z`) }),
        ...(dto.fechaHasta       !== undefined && { fechaHasta:       new Date(`${dto.fechaHasta}T23:59:59.000Z`) }),
        ...(dto.horaDesde        !== undefined && { horaDesde:        dto.horaDesde }),
        ...(dto.horaHasta        !== undefined && { horaHasta:        dto.horaHasta }),
        ...(dto.edadMin          !== undefined && { edadMin:          dto.edadMin }),
        ...(dto.edadMax          !== undefined && { edadMax:          dto.edadMax }),
        ...(dto.anexos           !== undefined && { anexos:           dto.anexos }),
      },
      include: { areas: { include: { area: true } } },
    });
  }

  // ── LIBERAR MANUAL ────────────────────────────────────────────────────────
  async liberar(id: number) {
    const ocupacion = await this.findOne(id);
    const areaIds   = ocupacion.areas.map((r) => r.areaId);

    await this.prisma.$transaction(async (tx) => {
      if (areaIds.length > 0) {
        await tx.area.updateMany({ where: { id: { in: areaIds } }, data: { estado: AreaStatus.LIBRE } });
      }
      await tx.ocupacion.update({ where: { id }, data: { liberadaAt: new Date() } });
    });

    return this.findOne(id);
  }

  // ── REMOVE ────────────────────────────────────────────────────────────────
  async remove(id: number) {
    const ocupacion = await this.findOne(id);
    const areaIds   = ocupacion.areas.map((r) => r.areaId);

    await this.prisma.$transaction(async (tx) => {
      await tx.ocupacionArea.deleteMany({ where: { ocupacionId: id } });
      if (areaIds.length > 0) {
        await tx.area.updateMany({ where: { id: { in: areaIds } }, data: { estado: AreaStatus.LIBRE } });
      }
      await tx.ocupacion.delete({ where: { id } });
    });

    return { message: `Ocupación ${id} eliminada y áreas liberadas` };
  }

  // ── CRON: auto-liberar áreas cuando termina el evento ────────────────────
  // Corre cada minuto. Libera ocupaciones donde fechaHasta+horaHasta < ahora
  @Cron('* * * * *')
  async autoLiberarVencidas() {
    const ahora      = new Date();
    const ahoraUTC3  = new Date(ahora.getTime() - 3 * 60 * 60 * 1000); // UTC-3
    const fechaHoy   = ahoraUTC3.toISOString().split('T')[0];
    const minutosNow = ahoraUTC3.getHours() * 60 + ahoraUTC3.getMinutes();

    try {
      // Buscar ocupaciones activas cuya fechaHasta ya pasó o es hoy y horaHasta ya pasó
      const candidatas = await this.prisma.ocupacion.findMany({
        where: {
          liberadaAt: null,
          fechaHasta: { lte: new Date(`${fechaHoy}T23:59:59.000Z`) },
        },
        include: { areas: { include: { area: true } } },
      });

      for (const oc of candidatas) {
        const fechaFin = oc.fechaHasta.toISOString().split('T')[0];

        // Si la fecha de fin ya pasó completamente
        if (fechaFin < fechaHoy) {
          await this.liberarInterno(oc);
          continue;
        }

        // Si es hoy, verificar que la hora ya pasó
        if (fechaFin === fechaHoy) {
          const minutosFin = timeToMinutes(oc.horaHasta);
          if (minutosNow >= minutosFin) {
            await this.liberarInterno(oc);
          }
        }
      }
    } catch (err) {
      this.logger.error('Error en autoLiberarVencidas:', (err as Error).message);
    }
  }

  private async liberarInterno(oc: { id: number; areas: { areaId: number }[] }) {
    const areaIds = oc.areas.map((r) => r.areaId);
    await this.prisma.$transaction(async (tx) => {
      if (areaIds.length > 0) {
        await tx.area.updateMany({ where: { id: { in: areaIds } }, data: { estado: AreaStatus.LIBRE } });
      }
      await tx.ocupacion.update({ where: { id: oc.id }, data: { liberadaAt: new Date() } });
    });
    this.logger.log(`⏰ Auto-liberada ocupación ${oc.id}`);
  }
}
