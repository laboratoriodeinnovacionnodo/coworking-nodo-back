import { Injectable } from '@nestjs/common';
import { CreateAreaDto } from './dto/create-area.dto';
import { UpdateAreaDto } from './dto/update-area.dto';
import { PrismaService } from 'prisma/prisma.service';
import { AreaStatus } from '@prisma/client';

/**
 * Helpers de zona horaria Argentina (UTC-3).
 */
function nowArgentina(): { fechaHoy: string; minNow: number } {
  const ar = new Date(Date.now() - 3 * 60 * 60 * 1000);
  const fechaHoy = ar.toISOString().split('T')[0];
  const minNow = ar.getUTCHours() * 60 + ar.getUTCMinutes();
  return { fechaHoy, minNow };
}

function toMin(hhmm: string): number {
  const [h, m] = hhmm.split(':').map(Number);
  return h * 60 + m;
}

@Injectable()
export class AreaService {
  constructor(private prisma: PrismaService) {}

  create(data: CreateAreaDto) {
    return this.prisma.area.create({ data });
  }

  findAll() {
    return this.prisma.area.findMany();
  }

  findOne(id: number) {
    return this.prisma.area.findUnique({ where: { id } });
  }

  update(id: number, data: UpdateAreaDto) {
    return this.prisma.area.update({ where: { id }, data });
  }

  async remove(id: number) {
    await this.prisma.reserva.deleteMany({ where: { areaId: id } });
    return this.prisma.area.delete({ where: { id } });
  }

  cambiarEstado(id: number, estado: AreaStatus) {
    return this.prisma.area.update({ where: { id }, data: { estado } });
  }

  async bloquearTodas(estado: AreaStatus) {
    if (estado === AreaStatus.OCUPADO) {
      await this.prisma.area.updateMany({ data: { estado: AreaStatus.OCUPADO } });
    } else {
      const reservasActivas = await this.prisma.reserva.findMany({
        where: { fin: null },
        select: { areaId: true },
      });
      const idsOcupados = reservasActivas.map((r) => r.areaId);
      await this.prisma.area.updateMany({
        where: { id: { notIn: idsOcupados } },
        data: { estado: AreaStatus.LIBRE },
      });
    }
    return this.prisma.area.findMany();
  }

  /**
   * Devuelve todas las áreas con el estado calculado en tiempo real,
   * basado en ocupaciones activas AHORA y reservas de asiento vigentes.
   *
   * No depende del campo area.estado persistido — es la fuente de verdad
   * para el frontend cuando necesita saber si un área está ocupada en
   * este momento exacto.
   */
  async getEstadoActual() {
    const { fechaHoy, minNow } = nowArgentina();
    const hoyDate = new Date(`${fechaHoy}T00:00:00.000Z`);

    const [areas, ocupaciones, reservasActivas] = await Promise.all([
      this.prisma.area.findMany(),
      this.prisma.ocupacion.findMany({
        where: {
          liberadaAt: null,
          fechaDesde: { lte: new Date(`${fechaHoy}T23:59:59.000Z`) },
          fechaHasta: { gte: hoyDate },
        },
        include: { areas: true },
      }),
      this.prisma.reserva.findMany({
        where: { fin: null },
        select: { areaId: true },
      }),
    ]);

    // IDs de áreas ocupadas por ocupaciones activas AHORA
    const idsOcupadasPorOcupacion = new Set<number>();
    for (const oc of ocupaciones) {
      const ocDesde = oc.fechaDesde.toISOString().split('T')[0];
      const ocHasta = oc.fechaHasta.toISOString().split('T')[0];

      const enCurso = (() => {
        if (ocDesde > fechaHoy || ocHasta < fechaHoy) return false;
        if (ocDesde === fechaHoy && ocHasta === fechaHoy) {
          return minNow >= toMin(oc.horaDesde) && minNow < toMin(oc.horaHasta);
        }
        if (ocDesde === fechaHoy) return minNow >= toMin(oc.horaDesde);
        if (ocHasta === fechaHoy) return minNow < toMin(oc.horaHasta);
        return true;
      })();

      if (enCurso) {
        oc.areas.forEach((r) => idsOcupadasPorOcupacion.add(r.areaId));
      }
    }

    // IDs de áreas ocupadas por reservas de asiento vigentes
    const idsOcupadasPorReserva = new Set(reservasActivas.map((r) => r.areaId));

    // Combinar: un área está OCUPADO si alguna fuente la marca como tal
    return areas.map((area) => ({
      ...area,
      estado:
        idsOcupadasPorOcupacion.has(area.id) || idsOcupadasPorReserva.has(area.id)
          ? AreaStatus.OCUPADO
          : AreaStatus.LIBRE,
    }));
  }
}
