import { Controller, Get, Post, Body, Param, Patch, Delete } from '@nestjs/common';
import { UsuarioService } from './usuario.service';
import { CreateUsuarioDto } from './dto/create-usuario.dto';
import { UpdateUsuarioDto } from './dto/update-usuario.dto';

@Controller('usuario')
export class UsuarioController {
  constructor(private readonly usuarioService: UsuarioService) {}

  @Post()
  crear(@Body() data: CreateUsuarioDto) {
    return this.usuarioService.crear(data);
  }

  @Get()
  listar() {
    return this.usuarioService.listar();
  }

  @Get(':id')
  buscar(@Param('id') id: string) {
    return this.usuarioService.buscarPorId(Number(id));
  }

  @Patch(':id')
  actualizar(@Param('id') id: string, @Body() data: UpdateUsuarioDto) {
    return this.usuarioService.actualizar(Number(id), data);
  }

  @Delete(':id')
  eliminar(@Param('id') id: string) {
    return this.usuarioService.eliminar(Number(id));
  }
}
