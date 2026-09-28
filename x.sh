#!/usr/bin/env bash
# ============================================================================
#  v28-back-editar-reserva.sh  — coworking-back
#  Mejora el endpoint PATCH /reservas/:id con validación real de negocio:
#  - Permite editar nombre, detalles y recepcion sin side-effects
#  - Si cambia el areaId: libera el área vieja y valida/ocupa la nueva
# ============================================================================
set -euo pipefail

[[ -f "package.json" && -d "src" ]] || { echo "❌  Corré desde la raíz de coworking-back"; exit 1; }

echo "════════════════════════════════════════════════════════"
echo "  v28-back-editar-reserva  |  coworking-back"
echo "════════════════════════════════════════════════════════"
echo ""

# ── src/reserva/reserva.service.ts ───────────────────────────────────────────
echo "📝  Actualizando reserva.service.ts..."
cat > src/reserva/reserva.service.ts << 'EOF'
import { Injectable, BadRequestException, NotFoundException } from '@nestjs/common';
import { CreateReservaDto } from './dto/create-reserva.dto';
import { UpdateReservaDto } from './dto/update-reserva.dto';
import { PrismaService } from 'prisma/prisma.service';
import { AreaStatus } from '@prisma/client';

// ── Helpers de tiempo (Argentina, UTC-3) ─────────────────────────────────────

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

  // ── Verifica que no exista una Ocupación activa para el área ──────────────
  private async verificarOcupacionActiva(areaId: number): Promise<void> {
    const hoy     = hoyArgentina();
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

  // ── CREATE ────────────────────────────────────────────────────────────────
  async create(data: CreateReservaDto) {
    const area = await this.prisma.area.findUnique({ where: { id: data.areaId } });

    if (!area) throw new NotFoundException('Área no encontrada');
    if (area.estado !== AreaStatus.LIBRE)
      throw new BadRequestException('El área no está disponible');

    await this.verificarOcupacionActiva(data.areaId);

    const reserva = await this.prisma.reserva.create({ data });

    await this.prisma.area.update({
      where: { id: data.areaId },
      data: { estado: AreaStatus.OCUPADO },
    });

    return reserva;
  }

  // ── FIND ALL ──────────────────────────────────────────────────────────────
  findAll() {
    return this.prisma.reserva.findMany({
      include: { usuario: true, area: true },
    });
  }

  // ── FIND ONE ──────────────────────────────────────────────────────────────
  findOne(id: number) {
    return this.prisma.reserva.findUnique({
      where: { id },
      include: { usuario: true, area: true },
    });
  }

  // ── UPDATE ────────────────────────────────────────────────────────────────
  // Permite editar: nombre, detalles, recepcion (seguros, sin side-effects).
  // Si cambia areaId: libera el área vieja, valida y ocupa la nueva.
  async update(id: number, dto: UpdateReservaDto) {
    const reserva = await this.prisma.reserva.findUnique({
      where: { id },
      include: { area: true },
    });

    if (!reserva) throw new NotFoundException('Reserva no encontrada');
    if (reserva.fin !== null)
      throw new BadRequestException('No se puede editar una reserva ya completada');

    const { areaId, ...camposSeguros } = dto;

    // ── Sin cambio de área: actualización simple ──────────────────────────
    if (!areaId || areaId === reserva.areaId) {
      return this.prisma.reserva.update({
        where: { id },
        data: camposSeguros,
        include: { usuario: true, area: true },
      });
    }

    // ── Cambio de área: validar nueva área y reasignar ────────────────────
    const nuevaArea = await this.prisma.area.findUnique({ where: { id: areaId } });

    if (!nuevaArea) throw new NotFoundException('Área nueva no encontrada');
    if (nuevaArea.estado !== AreaStatus.LIBRE)
      throw new BadRequestException('El área nueva no está disponible');

    await this.verificarOcupacionActiva(areaId);

    return this.prisma.$transaction(async (tx) => {
      // 1. Actualizar reserva con nueva área + campos
      const actualizada = await tx.reserva.update({
        where: { id },
        data: { ...camposSeguros, areaId },
        include: { usuario: true, area: true },
      });

      // 2. Liberar área anterior (si no tiene otras reservas activas)
      const otrasReservasEnAreaVieja = await tx.reserva.count({
        where: {
          areaId: reserva.areaId,
          fin: null,
          id: { not: id },
        },
      });

      if (otrasReservasEnAreaVieja === 0) {
        await tx.area.update({
          where: { id: reserva.areaId },
          data: { estado: AreaStatus.LIBRE },
        });
      }

      // 3. Marcar nueva área como OCUPADO
      await tx.area.update({
        where: { id: areaId },
        data: { estado: AreaStatus.OCUPADO },
      });

      return actualizada;
    });
  }

  // ── COMPLETAR ─────────────────────────────────────────────────────────────
  async completarReserva(id: number) {
    const reserva = await this.prisma.reserva.findUnique({ where: { id } });
    if (!reserva) throw new NotFoundException('Reserva no encontrada');

    const finalizada = await this.prisma.reserva.update({
      where: { id },
      data: { fin: new Date() },
    });

    await this.prisma.area.update({
      where: { id: reserva.areaId },
      data: { estado: AreaStatus.LIBRE },
    });

    return finalizada;
  }

  // ── REMOVE ────────────────────────────────────────────────────────────────
  remove(id: number) {
    return this.prisma.reserva.delete({ where: { id } });
  }
}
EOF
echo "  ✅  reserva.service.ts listo"

# ── src/reserva/dto/update-reserva.dto.ts ────────────────────────────────────
echo "📝  Actualizando update-reserva.dto.ts..."
cat > src/reserva/dto/update-reserva.dto.ts << 'EOF'
import { ApiPropertyOptional } from '@nestjs/swagger';
import { IsEnum, IsInt, IsOptional, IsString } from 'class-validator';
import { Recepcion } from '@prisma/client';

export class UpdateReservaDto {
  @ApiPropertyOptional({ description: 'Nombre del cliente' })
  @IsOptional()
  @IsString()
  nombre?: string;

  @ApiPropertyOptional({ description: 'Datos adicionales' })
  @IsOptional()
  @IsString()
  detalles?: string;

  @ApiPropertyOptional({ description: 'Nuevo ID de área (reasignación)' })
  @IsOptional()
  @IsInt()
  areaId?: number;

  @ApiPropertyOptional({
    enum: Recepcion,
    description: 'Turno de recepción: MANANA | INTERMEDIO | TARDE',
  })
  @IsOptional()
  @IsEnum(Recepcion)
  recepcion?: Recepcion;
}
EOF
echo "  ✅  update-reserva.dto.ts listo"

# ── Build ─────────────────────────────────────────────────────────────────────
echo ""
echo "🔨  Build de verificación..."
pnpm build

echo ""
echo "✅  v28-back-editar-reserva completado"