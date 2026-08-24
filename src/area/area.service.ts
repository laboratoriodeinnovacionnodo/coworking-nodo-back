import { Injectable } from '@nestjs/common';
import { CreateAreaDto } from './dto/create-area.dto';
import { UpdateAreaDto } from './dto/update-area.dto';
import { PrismaService } from 'prisma/prisma.service';
import { AreaStatus } from '@prisma/client';

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
    return this.prisma.area.update({
      where: { id },
      data
    });
  }

  async remove(id: number) {
    await this.prisma.reserva.deleteMany({
      where: { areaId: id },
    });

    return this.prisma.area.delete({
      where: { id },
    });
  }

  // Cambiar estado del área
  cambiarEstado(id: number, estado: AreaStatus) {
    return this.prisma.area.update({
      where: { id },
      data: { estado }
    });
  }

  // ── Bloquea/libera TODAS las áreas de una vez ───────────────────────────
  // Usado por el admin (bloqueo manual por evento) y por calendario-back
  // (sincronización automática cuando un Evento con área COWORKING
  // entra/sale de EN_CURSO).
  async bloquearTodas(estado: AreaStatus) {
    if (estado === AreaStatus.OCUPADO) {
      await this.prisma.area.updateMany({
        data: { estado: AreaStatus.OCUPADO },
      });
    } else {
      // Al liberar, no tocar las áreas que tengan una reserva de persona
      // activa (fin: null) — evita pisar una reserva real en curso.
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
}
