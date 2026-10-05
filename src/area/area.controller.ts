import { Controller, Get, Post, Body, Patch, Param, Delete } from '@nestjs/common';
import { AreaService } from './area.service';
import { CreateAreaDto } from './dto/create-area.dto';
import { UpdateAreaDto } from './dto/update-area.dto';
import { ApiTags, ApiOperation } from '@nestjs/swagger';
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

  /**
   * Devuelve el estado de cada área calculado en tiempo real:
   * tiene en cuenta ocupaciones activas AHORA y reservas de asiento vigentes.
   * Usar este endpoint en el frontend en lugar de GET /areas para mostrar
   * el estado correcto sin depender del campo persistido area.estado.
   */
  @Get('estado-actual')
  @ApiOperation({ summary: 'Estado en tiempo real — basado en ocupaciones y reservas activas ahora' })
  getEstadoActual() {
    return this.areaService.getEstadoActual();
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
    @Param('estado') estado: AreaStatus,
  ) {
    return this.areaService.cambiarEstado(+id, estado);
  }

  @Delete(':id')
  remove(@Param('id') id: string) {
    return this.areaService.remove(+id);
  }
}
