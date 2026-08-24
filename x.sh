#!/usr/bin/env bash
# =============================================================================
# v6-back-reserva-vs-ocupacion.sh — v1.0.0 — PRODUCCIÓN (coworking-back)
#
# Cambios:
#  · ReservaService: NO permite crear una reserva si el área tiene una
#    Ocupación activa que cubre el día y rango horario actual.
#  · AreaService/AreaController: nuevo endpoint bulk
#      PATCH /areas/bloquear-todas/:estado
#    - OCUPADO  -> marca TODAS las áreas ocupadas
#    - LIBRE    -> libera todas EXCEPTO las que tengan una reserva de
#                  persona activa (fin: null), para no pisar una reserva real
#
#  Este endpoint es el que usará calendario-back para sincronizar el
#  Coworking cuando un Evento con área COWORKING está EN_CURSO / FINALIZADO.
#
# ⚠️  No requiere cambios de schema — no correr prisma migrate.
# =============================================================================
set -euo pipefail

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║  v6-back-reserva-vs-ocupacion.sh — v1.0.0                    ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

if [ ! -f "package.json" ] || [ ! -d "src" ]; then
  echo "❌  Corré desde la raíz del proyecto NestJS (coworking-back)"
  exit 1
fi

# ════════════════════════════════════════════════════════════════════════════
# 1. ReservaService — chequeo de Ocupación activa antes de crear
# ════════════════════════════════════════════════════════════════════════════
echo "📄  src/reserva/reserva.service.ts..."
cat > src/reserva/reserva.service.ts << 'EOF'
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
EOF
echo "✅  reserva.service.ts"

# ════════════════════════════════════════════════════════════════════════════
# 2. AreaService — bloquearTodas()
# ════════════════════════════════════════════════════════════════════════════
echo "📄  src/area/area.service.ts..."
cat > src/area/area.service.ts << 'EOF'
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
EOF
echo "✅  area.service.ts"

# ════════════════════════════════════════════════════════════════════════════
# 3. AreaController — endpoint bulk
# ════════════════════════════════════════════════════════════════════════════
echo "📄  src/area/area.controller.ts..."
cat > src/area/area.controller.ts << 'EOF'
import { Controller, Get, Post, Body, Patch, Param, Delete } from '@nestjs/common';
import { AreaService } from './area.service';
import { CreateAreaDto } from './dto/create-area.dto';
import { UpdateAreaDto } from './dto/update-area.dto';
import { ApiTags } from '@nestjs/swagger';
import { AreaStatus } from '@prisma/client';

@ApiTags('areas')
@Controller('areas')
export class AreaController {
  constructor(private readonly areaService: AreaService) {}

  @Post()
  create(@Body() dto: CreateAreaDto) {
    return this.areaService.create(dto);
  }

  @Get()
  findAll() {
    return this.areaService.findAll();
  }

  // Bulk: PATCH /areas/bloquear-todas/OCUPADO | LIBRE
  @Patch('bloquear-todas/:estado')
  bloquearTodas(@Param('estado') estado: AreaStatus) {
    return this.areaService.bloquearTodas(estado);
  }

  @Get(':id')
  findOne(@Param('id') id: string) {
    return this.areaService.findOne(+id);
  }

  @Patch(':id')
  update(@Param('id') id: string, @Body() dto: UpdateAreaDto) {
    return this.areaService.update(+id, dto);
  }

  @Patch(':id/estado/:estado')
  cambiarEstado(
    @Param('id') id: string,
    @Param('estado') estado: AreaStatus
  ) {
    return this.areaService.cambiarEstado(+id, estado);
  }

  @Delete(':id')
  remove(@Param('id') id: string) {
    return this.areaService.remove(+id);
  }
}
EOF
echo "✅  area.controller.ts"

# ════════════════════════════════════════════════════════════════════════════
# 4. Build
# ════════════════════════════════════════════════════════════════════════════
echo ""
echo "🔨  Compilando..."
pnpm build

echo ""
echo "╔══════════════════════════════════════════════════════════════════╗"
echo "║  ✅  v6-back-reserva-vs-ocupacion.sh — v1.0.0 completado          ║"
echo "╚══════════════════════════════════════════════════════════════════╝"
echo ""
echo "  Cambios:"
echo "    · POST /reservas ahora rechaza si hay Ocupación activa (día+hora)"
echo "    · PATCH /areas/bloquear-todas/:estado (OCUPADO | LIBRE) — nuevo"
echo ""
echo "  ⚠️  No requiere prisma migrate (no hay cambios de schema)"
echo ""