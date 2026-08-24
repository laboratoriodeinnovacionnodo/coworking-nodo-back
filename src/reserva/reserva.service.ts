import { Injectable, BadRequestException, NotFoundException } from '@nestjs/common';
import { CreateReservaDto } from './dto/create-reserva.dto';
import { UpdateReservaDto } from './dto/update-reserva.dto';
import { PrismaService } from 'prisma/prisma.service';
import { AreaStatus } from '@prisma/client';

// ── Helpers de tiempo (Argentina, UTC-3) ────────────────────────────────────

function timeToMinutes(hhmm: string): number {
  const [h, m] = hhmm.split(':').map(Number);
  return h * 60 + m;
}

function hoyArgentina(): string {
  const ahora = new Date();
  ahora.setHours(ahora.getHours() - 3);
  return ahora.toISOString().split('T')[0];
}

function nowMinutesArgentina(): number {
  const ahora = new Date();
  ahora.setHours(ahora.getHours() - 3);
  return ahora.getUTCHours() * 60 + ahora.getUTCMinutes();
}

@Injectable()
export class ReservaService {
  constructor(private prisma: PrismaService) {}

  // ── Verifica que no exista una Ocupación activa cubriendo hoy + hora actual ──
  private async verificarOcupacionActiva(areaId: number): Promise<void> {
    const hoy = hoyArgentina();
    const nowMins = nowMinutesArgentina();

    const ocupacion = await this.prisma.ocupacion.findFirst({
      where: {
        liberadaAt: null,
        areas: { some: { areaId } },
        fechaDesde: { lte: new Date(`${hoy}T23:59:59.000Z`) },
        fechaHasta: { gte: new Date(`${hoy}T00:00:00.000Z`) },
      },
    });

    if (!ocupacion) return;

    const fechaDesdeStr = ocupacion.fechaDesde.toISOString().split('T')[0];
    const fechaHastaStr = ocupacion.fechaHasta.toISOString().split('T')[0];

    // Ocupación multi-día que ya arrancó y todavía no termina hoy → bloquea el día entero
    if (fechaDesdeStr < hoy && fechaHastaStr > hoy) {
      throw new BadRequestException(
        `El área está ocupada por "${ocupacion.titulo}" hasta el ${fechaHastaStr}`,
      );
    }

    const desdeMin = fechaDesdeStr === hoy ? timeToMinutes(ocupacion.horaDesde) : 0;
    const hastaMin = fechaHastaStr === hoy ? timeToMinutes(ocupacion.horaHasta) : 24 * 60;

    if (nowMins >= desdeMin && nowMins < hastaMin) {
      throw new BadRequestException(
        `El área está ocupada por "${ocupacion.titulo}" hoy de ${ocupacion.horaDesde} a ${ocupacion.horaHasta}`,
      );
    }
  }

  async create(data: CreateReservaDto) {
    const area = await this.prisma.area.findUnique({
      where: { id: data.areaId },
    });

    if (!area) throw new NotFoundException('Área no encontrada');
    if (area.estado !== AreaStatus.LIBRE)
      throw new BadRequestException('El área no está disponible');

    // Nuevo: valida contra Ocupaciones (día + rango horario), no solo el AreaStatus
    await this.verificarOcupacionActiva(data.areaId);

    // Crear la reserva
    const reserva = await this.prisma.reserva.create({ data });

    // Cambiar estado del área a OCUPADO
    await this.prisma.area.update({
      where: { id: data.areaId },
      data: { estado: AreaStatus.OCUPADO },
    });

    return reserva;
  }

  findAll() {
    return this.prisma.reserva.findMany({
      include: { usuario: true, area: true },
    });
  }

  findOne(id: number) {
    return this.prisma.reserva.findUnique({
      where: { id },
      include: { usuario: true, area: true },
    });
  }

  update(id: number, data: UpdateReservaDto) {
    return this.prisma.reserva.update({
      where: { id },
      data,
    });
  }

  async completarReserva(id: number) {
    const reserva = await this.prisma.reserva.findUnique({ where: { id } });
    if (!reserva) throw new NotFoundException('Reserva no encontrada');

    // Finalizar reserva
    const finalizada = await this.prisma.reserva.update({
      where: { id },
      data: { fin: new Date() },
    });

    // Restaurar área a "LIBRE"
    await this.prisma.area.update({
      where: { id: reserva.areaId },
      data: { estado: AreaStatus.LIBRE },
    });

    return finalizada;
  }

  remove(id: number) {
    return this.prisma.reserva.delete({ where: { id } });
  }
}
