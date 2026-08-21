#!/usr/bin/env bash
# =============================================================================
# back-ocupacion.sh  —  v2.0.0  —  PRODUCCIÓN
# Módulo "ocupacion" con relación many-to-many a Area (tabla OcupacionArea)
# Al crear  → áreas seleccionadas pasan a OCUPADO
# Al liberar → áreas vuelven a LIBRE
# Estados simplificados: solo LIBRE y OCUPADO
#
# ⚠️  SCHEMA MANUAL requerido ANTES de ejecutar este script.
#     Ver bloque al final del archivo.
# =============================================================================
set -euo pipefail

echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║   back-ocupacion.sh — v2.0.0  (many-to-many)        ║"
echo "╚══════════════════════════════════════════════════════╝"
echo ""

mkdir -p src/ocupacion/dto src/ocupacion/entities

# ── 1. DTO create ─────────────────────────────────────────────────────────────
cat > src/ocupacion/dto/create-ocupacion.dto.ts << 'EOF'
import {
  IsString,
  IsOptional,
  IsInt,
  IsArray,
  IsUrl,
  Min,
  Max,
  MinLength,
  ArrayMinSize,
  ArrayMaxSize,
} from 'class-validator';
import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { Type } from 'class-transformer';

export class CreateOcupacionDto {
  @ApiProperty({ description: 'Título de la ocupación / evento' })
  @IsString()
  @MinLength(3)
  titulo: string;

  @ApiProperty({ description: 'Requerimientos o descripción detallada' })
  @IsString()
  @MinLength(3)
  requerimiento: string;

  @ApiProperty({ description: 'Cantidad estimada de personas' })
  @Type(() => Number)
  @IsInt()
  @Min(1)
  cantidadPersonas: number;

  @ApiProperty({ description: 'Nombre del solicitante u organizador' })
  @IsString()
  @MinLength(2)
  organizador: string;

  @ApiProperty({ description: 'Fecha del evento (YYYY-MM-DD)' })
  @IsString()
  dia: string;

  @ApiProperty({ description: 'Hora del evento (HH:mm)' })
  @IsString()
  hora: string;

  @ApiPropertyOptional({ description: 'Edad mínima del público' })
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(0)
  @Max(120)
  edadMin?: number;

  @ApiPropertyOptional({ description: 'Edad máxima del público' })
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(0)
  @Max(120)
  edadMax?: number;

  @ApiPropertyOptional({ description: 'URLs de anexos', type: [String] })
  @IsOptional()
  @IsArray()
  @IsUrl({}, { each: true })
  @ArrayMaxSize(10)
  anexos?: string[];

  @ApiProperty({
    description: 'IDs de las áreas del coworking a ocupar',
    type: [Number],
  })
  @IsArray()
  @ArrayMinSize(1)
  @Type(() => Number)
  @IsInt({ each: true })
  areaIds: number[];
}
EOF
echo "✅  src/ocupacion/dto/create-ocupacion.dto.ts"

# ── 2. DTO update ─────────────────────────────────────────────────────────────
cat > src/ocupacion/dto/update-ocupacion.dto.ts << 'EOF'
import { PartialType } from '@nestjs/swagger';
import { CreateOcupacionDto } from './create-ocupacion.dto';

export class UpdateOcupacionDto extends PartialType(CreateOcupacionDto) {}
EOF
echo "✅  src/ocupacion/dto/update-ocupacion.dto.ts"

# ── 3. Entity placeholder ─────────────────────────────────────────────────────
cat > src/ocupacion/entities/ocupacion.entity.ts << 'EOF'
export class Ocupacion {}
EOF
echo "✅  src/ocupacion/entities/ocupacion.entity.ts"

# ── 4. Service ────────────────────────────────────────────────────────────────
cat > src/ocupacion/ocupacion.service.ts << 'EOF'
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
EOF
echo "✅  src/ocupacion/ocupacion.service.ts"

# ── 5. Controller ─────────────────────────────────────────────────────────────
cat > src/ocupacion/ocupacion.controller.ts << 'EOF'
import {
  Controller,
  Get,
  Post,
  Patch,
  Delete,
  Param,
  Body,
  ParseIntPipe,
  HttpCode,
  HttpStatus,
  UsePipes,
  ValidationPipe,
} from '@nestjs/common';
import { ApiTags, ApiOperation, ApiResponse } from '@nestjs/swagger';
import { OcupacionService } from './ocupacion.service';
import { CreateOcupacionDto } from './dto/create-ocupacion.dto';
import { UpdateOcupacionDto } from './dto/update-ocupacion.dto';

@ApiTags('ocupaciones')
@UsePipes(new ValidationPipe({ transform: true, whitelist: true }))
@Controller('ocupaciones')
export class OcupacionController {
  constructor(private readonly ocupacionService: OcupacionService) {}

  @Post()
  @HttpCode(HttpStatus.CREATED)
  @ApiOperation({ summary: 'Crear ocupación y marcar áreas como OCUPADO' })
  @ApiResponse({ status: 201, description: 'Ocupación creada' })
  @ApiResponse({ status: 400, description: 'Datos inválidos o áreas no disponibles' })
  @ApiResponse({ status: 404, description: 'Área(s) no encontrada(s)' })
  create(@Body() dto: CreateOcupacionDto) {
    return this.ocupacionService.create(dto);
  }

  @Get()
  @ApiOperation({ summary: 'Listar todas las ocupaciones con sus áreas' })
  findAll() {
    return this.ocupacionService.findAll();
  }

  @Get(':id')
  @ApiOperation({ summary: 'Obtener una ocupación por ID' })
  @ApiResponse({ status: 404, description: 'No encontrada' })
  findOne(@Param('id', ParseIntPipe) id: number) {
    return this.ocupacionService.findOne(id);
  }

  @Patch(':id')
  @ApiOperation({ summary: 'Actualizar ocupación (también actualiza áreas si se envía areaIds)' })
  update(
    @Param('id', ParseIntPipe) id: number,
    @Body() dto: UpdateOcupacionDto,
  ) {
    return this.ocupacionService.update(id, dto);
  }

  @Patch(':id/liberar')
  @ApiOperation({ summary: 'Liberar ocupación → áreas vuelven a LIBRE' })
  liberar(@Param('id', ParseIntPipe) id: number) {
    return this.ocupacionService.liberar(id);
  }

  @Delete(':id')
  @HttpCode(HttpStatus.NO_CONTENT)
  @ApiOperation({ summary: 'Eliminar ocupación y liberar sus áreas' })
  remove(@Param('id', ParseIntPipe) id: number) {
    return this.ocupacionService.remove(id);
  }
}
EOF
echo "✅  src/ocupacion/ocupacion.controller.ts"

# ── 6. Module ─────────────────────────────────────────────────────────────────
cat > src/ocupacion/ocupacion.module.ts << 'EOF'
import { Module } from '@nestjs/common';
import { OcupacionService } from './ocupacion.service';
import { OcupacionController } from './ocupacion.controller';

@Module({
  controllers: [OcupacionController],
  providers:   [OcupacionService],
  exports:     [OcupacionService],
})
export class OcupacionModule {}
EOF
echo "✅  src/ocupacion/ocupacion.module.ts"

# ── 7. Registrar en AppModule ─────────────────────────────────────────────────
if grep -q "OcupacionModule" src/app.module.ts; then
  echo "ℹ️   OcupacionModule ya estaba registrado"
else
  sed -i "1s/^/import { OcupacionModule } from '.\/ocupacion\/ocupacion.module';\n/" src/app.module.ts
  sed -i "s/AuthModule,/AuthModule,\n    OcupacionModule,/" src/app.module.ts
  echo "✅  OcupacionModule registrado en app.module.ts"
fi

# ── 8. ValidationPipe global en main.ts ──────────────────────────────────────
if grep -q "useGlobalPipes" src/main.ts; then
  echo "ℹ️   ValidationPipe global ya presente"
else
  sed -i "s/app\.enableCors/app.useGlobalPipes(new (require('@nestjs\/common').ValidationPipe)({ transform: true, whitelist: true }));\n\n  app.enableCors/" src/main.ts
  echo "✅  ValidationPipe global añadido"
fi

# ── 9. Dependencias ───────────────────────────────────────────────────────────
echo ""
echo "📦  Verificando class-validator / class-transformer..."
if ! grep -q '"class-validator"' package.json; then
  pnpm add class-validator class-transformer
  echo "✅  Dependencias instaladas"
else
  echo "ℹ️   class-validator ya presente"
fi

# ── 10. Build ─────────────────────────────────────────────────────────────────
echo ""
echo "🔨  Compilando..."
pnpm build

echo ""
echo "╔══════════════════════════════════════════════════════════════════╗"
echo "║  ✅  back-ocupacion.sh v2 completado                            ║"
echo "╚══════════════════════════════════════════════════════════════════╝"
echo ""
echo "  Endpoints disponibles:"
echo "    POST   /ocupaciones           → crea y ocupa áreas"
echo "    GET    /ocupaciones           → lista con áreas incluidas"
echo "    GET    /ocupaciones/:id"
echo "    PATCH  /ocupaciones/:id       → actualiza (incluso áreas)"
echo "    PATCH  /ocupaciones/:id/liberar → libera áreas → LIBRE"
echo "    DELETE /ocupaciones/:id       → elimina y libera áreas"
echo ""
echo "════════════════════════════════════════════════════════════════════"
echo "  ⚠️  SCHEMA MANUAL — Agregar a prisma/schema.prisma:"
echo "════════════════════════════════════════════════════════════════════"
cat << 'SCHEMA'

// ── Simplificar AreaStatus a solo dos estados ──────────────────────────────
// REEMPLAZÁ el enum existente por este:
enum AreaStatus {
  LIBRE
  OCUPADO
}

// ── Nuevo modelo Ocupacion ─────────────────────────────────────────────────
model Ocupacion {
  id               Int             @id @default(autoincrement())
  titulo           String
  requerimiento    String
  cantidadPersonas Int
  organizador      String
  dia              String
  hora             String
  edadMin          Int?
  edadMax          Int?
  anexos           String[]
  liberadaAt       DateTime?
  areas            OcupacionArea[]
  createdAt        DateTime        @default(now())
  updatedAt        DateTime        @updatedAt
}

// ── Tabla intermedia many-to-many ──────────────────────────────────────────
model OcupacionArea {
  ocupacionId Int
  areaId      Int
  ocupacion   Ocupacion @relation(fields: [ocupacionId], references: [id])
  area        Area      @relation(fields: [areaId], references: [id])

  @@id([ocupacionId, areaId])
}

// ── En el modelo Area existente, agregar la relación inversa: ──────────────
// areas  OcupacionArea[]    ← agregar esta línea dentro del model Area

SCHEMA
echo ""
echo "  ⚠️  El enum AreaStatus cambia — revisá que los datos existentes"
echo "     solo tengan LIBRE u OCUPADO antes de migrar."
echo ""
echo "  Luego ejecutá:"
echo "    npx prisma migrate dev --name add_ocupacion_many_to_many"
echo "    npx prisma generate"
echo ""