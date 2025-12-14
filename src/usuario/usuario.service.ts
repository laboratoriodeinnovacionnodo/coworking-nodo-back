import { Injectable } from '@nestjs/common';
import { CreateUsuarioDto } from './dto/create-usuario.dto';
import { UpdateUsuarioDto } from './dto/update-usuario.dto';
import { PrismaService } from 'prisma/prisma.service';

@Injectable()
export class UsuarioService {
  constructor(private prisma: PrismaService) {}

  crear(data: CreateUsuarioDto) {
    return this.prisma.usuario.create({
      data,
    });
  }

  listar() {
    return this.prisma.usuario.findMany({
      include: { reservas: true },
    });
  }

  buscarPorId(id: number) {
    return this.prisma.usuario.findUnique({
      where: { id },
      include: { reservas: true },
    });
  }

  actualizar(id: number, data: UpdateUsuarioDto) {
    return this.prisma.usuario.update({
      where: { id },
      data,
    });
  }

  eliminar(id: number) {
    return this.prisma.usuario.delete({
      where: { id },
    });
  }
}
