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
