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

  remove(id: number) {
    return this.prisma.area.delete({ where: { id } });
  }

  // Cambiar estado del área
  cambiarEstado(id: number, estado: AreaStatus) {
    return this.prisma.area.update({
      where: { id },
      data: { estado }
    });
  }
}
