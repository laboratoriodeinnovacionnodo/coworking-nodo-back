import { ApiProperty } from '@nestjs/swagger';

export class CreateReservaDto {
  @ApiProperty()
  nombre: string;

  @ApiProperty({ required: false })
  detalles?: string;

  @ApiProperty()
  usuarioId: number;

  @ApiProperty()
  areaId: number;
}
