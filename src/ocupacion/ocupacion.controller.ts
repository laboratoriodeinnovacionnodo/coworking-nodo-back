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
  @ApiOperation({ summary: 'Crear ocupación — valida conflictos de horario y marca áreas OCUPADO' })
  @ApiResponse({ status: 201, description: 'Ocupación creada' })
  @ApiResponse({ status: 400, description: 'Datos inválidos o conflicto de horario' })
  @ApiResponse({ status: 404, description: 'Área(s) no encontrada(s)' })
  create(@Body() dto: CreateOcupacionDto) {
    return this.ocupacionService.create(dto);
  }

  @Get()
  @ApiOperation({ summary: 'Listar todas las ocupaciones' })
  findAll() {
    return this.ocupacionService.findAll();
  }

  @Get('activas')
  @ApiOperation({ summary: 'Listar ocupaciones activas (sin liberadaAt, desde hoy)' })
  findActivas() {
    return this.ocupacionService.findActivas();
  }

  @Get(':id')
  @ApiOperation({ summary: 'Obtener una ocupación por ID' })
  @ApiResponse({ status: 404, description: 'No encontrada' })
  findOne(@Param('id', ParseIntPipe) id: number) {
    return this.ocupacionService.findOne(id);
  }

  @Patch(':id')
  @ApiOperation({ summary: 'Actualizar ocupación — revalida conflictos si cambia horario/áreas' })
  update(@Param('id', ParseIntPipe) id: number, @Body() dto: UpdateOcupacionDto) {
    return this.ocupacionService.update(id, dto);
  }

  @Patch(':id/liberar')
  @ApiOperation({ summary: 'Liberar ocupación manualmente → áreas vuelven a LIBRE' })
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
