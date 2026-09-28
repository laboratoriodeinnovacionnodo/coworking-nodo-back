import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { IsEnum, IsInt, IsOptional, IsString } from 'class-validator';
import { Recepcion } from '@prisma/client';

export class CreateReservaDto {
  @ApiProperty({ description: 'Nombre del cliente que reserva' })
  @IsString()
  nombre: string;

  @ApiPropertyOptional({ description: 'Datos adicionales de la reserva' })
  @IsOptional()
  @IsString()
  detalles?: string;

  @ApiProperty({ description: 'ID del usuario' })
  @IsInt()
  usuarioId: number;

  @ApiProperty({ description: 'ID del área a reservar' })
  @IsInt()
  areaId: number;

  @ApiPropertyOptional({
    enum: Recepcion,
    description: 'Turno de recepción: MANANA | INTERMEDIO | TARDE',
  })
  @IsOptional()
  @IsEnum(Recepcion)
  recepcion?: Recepcion;
}
