import {
  Injectable,
  NotFoundException,
  BadRequestException,
} from '@nestjs/common';
import { PrismaService } from 'prisma/prisma.service';
import { CreateOcupacionDto } from './dto/create-ocupacion.dto';
import { UpdateOcupacionDto } from './dto/update-ocupacion.dto';
import { AreaStatus } from '@prisma/client';

@Injectable()
export class OcupacionService {
  constructor(private readonly prisma: PrismaService) {}

  // ── CREATE ──────────────────────────────────────────────────────────────
  async create(dto: CreateOcupacionDto) {
    if (
      dto.edadMin !== undefined &&
      dto.edadMax !== undefined &&
      dto.edadMin > dto.edadMax
    ) {
      throw new BadRequestException('edadMin no puede ser mayor que edadMax');
    }

    // Verificar que todas las áreas existen y están LIBRES
    const areas = await this.prisma.area.findMany({
      where: { id: { in: dto.areaIds } },
    });

    if (areas.length !== dto.areaIds.length) {
      const found = areas.map((a) => a.id);
      const missing = dto.areaIds.filter((id) => !found.includes(id));
      throw new NotFoundException(
        `Área(s) no encontrada(s): ${missing.join(', ')}`,
      );
    }

    const ocupadas = areas.filter((a) => a.estado !== AreaStatus.LIBRE);
    if (ocupadas.length > 0) {
      throw new BadRequestException(
        `Las siguientes áreas no están disponibles: ${ocupadas.map((a) => a.nombre).join(', ')}`,
      );
    }

    // Crear ocupación + relaciones + actualizar estados en una transacción
    const ocupacion = await this.prisma.$transaction(async (tx) => {
      const nueva = await tx.ocupacion.create({
        data: {
          titulo:           dto.titulo,
          requerimiento:    dto.requerimiento,
          cantidadPersonas: dto.cantidadPersonas,
          organizador:      dto.organizador,
          dia:              dto.dia,
          hora:             dto.hora,
          edadMin:          dto.edadMin,
          edadMax:          dto.edadMax,
          anexos:           dto.anexos ?? [],
          areas: {
            create: dto.areaIds.map((areaId) => ({ areaId })),
          },
        },
        include: {
          areas: { include: { area: true } },
        },
      });

      // Marcar todas las áreas como OCUPADO
      await tx.area.updateMany({
        where: { id: { in: dto.areaIds } },
        data:  { estado: AreaStatus.OCUPADO },
      });

      return nueva;
    });

    return ocupacion;
  }

  // ── FIND ALL ────────────────────────────────────────────────────────────
  findAll() {
    return this.prisma.ocupacion.findMany({
      orderBy: { createdAt: 'desc' },
      include: {
        areas: { include: { area: true } },
      },
    });
  }

  // ── FIND ONE ────────────────────────────────────────────────────────────
  async findOne(id: number) {
    const ocupacion = await this.prisma.ocupacion.findUnique({
      where: { id },
      include: {
        areas: { include: { area: true } },
      },
    });
    if (!ocupacion) throw new NotFoundException(`Ocupación ${id} no encontrada`);
    return ocupacion;
  }

  // ── UPDATE ──────────────────────────────────────────────────────────────
  async update(id: number, dto: UpdateOcupacionDto) {
    await this.findOne(id);

    if (
      dto.edadMin !== undefined &&
      dto.edadMax !== undefined &&
      dto.edadMin > dto.edadMax
    ) {
      throw new BadRequestException('edadMin no puede ser mayor que edadMax');
    }

    return this.prisma.$transaction(async (tx) => {
      // Si se cambian las áreas, liberar las anteriores y ocupar las nuevas
      if (dto.areaIds !== undefined) {
        const actual = await tx.ocupacionArea.findMany({
          where: { ocupacionId: id },
          select: { areaId: true },
        });
        const idsActuales = actual.map((r) => r.areaId);

        // Validar nuevas áreas
        const nuevasAreas = await tx.area.findMany({
          where: { id: { in: dto.areaIds } },
        });
        if (nuevasAreas.length !== dto.areaIds.length) {
          throw new NotFoundException('Una o más áreas no existen');
        }

        // Áreas que se quitan → LIBRE; áreas que se agregan → OCUPADO
        const aLiberar  = idsActuales.filter((i) => !dto.areaIds!.includes(i));
        const aOcupar   = dto.areaIds.filter((i) => !idsActuales.includes(i));

        if (aLiberar.length > 0) {
          await tx.area.updateMany({
            where: { id: { in: aLiberar } },
            data:  { estado: AreaStatus.LIBRE },
          });
        }
        if (aOcupar.length > 0) {
          await tx.area.updateMany({
            where: { id: { in: aOcupar } },
            data:  { estado: AreaStatus.OCUPADO },
          });
        }

        // Reemplazar relaciones
        await tx.ocupacionArea.deleteMany({ where: { ocupacionId: id } });
        await tx.ocupacionArea.createMany({
          data: dto.areaIds.map((areaId) => ({ ocupacionId: id, areaId })),
        });
      }

      return tx.ocupacion.update({
        where: { id },
        data: {
          ...(dto.titulo            !== undefined && { titulo:           dto.titulo }),
          ...(dto.requerimiento     !== undefined && { requerimiento:    dto.requerimiento }),
          ...(dto.cantidadPersonas  !== undefined && { cantidadPersonas: dto.cantidadPersonas }),
          ...(dto.organizador       !== undefined && { organizador:      dto.organizador }),
          ...(dto.dia               !== undefined && { dia:              dto.dia }),
          ...(dto.hora              !== undefined && { hora:             dto.hora }),
          ...(dto.edadMin           !== undefined && { edadMin:          dto.edadMin }),
          ...(dto.edadMax           !== undefined && { edadMax:          dto.edadMax }),
          ...(dto.anexos            !== undefined && { anexos:           dto.anexos }),
        },
        include: {
          areas: { include: { area: true } },
        },
      });
    });
  }

  // ── LIBERAR (completar ocupación) ───────────────────────────────────────
  async liberar(id: number) {
    const ocupacion = await this.findOne(id);

    const areaIds = ocupacion.areas.map((r) => r.areaId);

    await this.prisma.$transaction(async (tx) => {
      if (areaIds.length > 0) {
        await tx.area.updateMany({
          where: { id: { in: areaIds } },
          data:  { estado: AreaStatus.LIBRE },
        });
      }
      await tx.ocupacion.update({
        where: { id },
        data:  { liberadaAt: new Date() },
      });
    });

    return this.findOne(id);
  }

  // ── REMOVE ──────────────────────────────────────────────────────────────
  async remove(id: number) {
    const ocupacion = await this.findOne(id);
    const areaIds   = ocupacion.areas.map((r) => r.areaId);

    await this.prisma.$transaction(async (tx) => {
      await tx.ocupacionArea.deleteMany({ where: { ocupacionId: id } });

      if (areaIds.length > 0) {
        await tx.area.updateMany({
          where: { id: { in: areaIds } },
          data:  { estado: AreaStatus.LIBRE },
        });
      }

      await tx.ocupacion.delete({ where: { id } });
    });

    return { message: `Ocupación ${id} eliminada y áreas liberadas` };
  }
}
