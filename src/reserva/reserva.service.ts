import { Injectable, BadRequestException, NotFoundException } from '@nestjs/common';
import { CreateReservaDto } from './dto/create-reserva.dto';
import { UpdateReservaDto } from './dto/update-reserva.dto';
import { PrismaService } from 'prisma/prisma.service';
import { AreaStatus } from '@prisma/client';

@Injectable()
export class ReservaService {
  constructor(private prisma: PrismaService) {}

  async create(data: CreateReservaDto) {
    const area = await this.prisma.area.findUnique({
      where: { id: data.areaId },
    });

    if (!area) throw new NotFoundException('Área no encontrada');
    if (area.estado !== AreaStatus.LIBRE)
      throw new BadRequestException('El área no está disponible');

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
