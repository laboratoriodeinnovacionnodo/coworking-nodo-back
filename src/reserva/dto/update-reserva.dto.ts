import { ApiPropertyOptional } from '@nestjs/swagger';
import { IsEmail, IsEnum, IsInt, IsOptional, IsString } from 'class-validator';
import { Recepcion } from '@prisma/client';

export class UpdateReservaDto {
  @ApiPropertyOptional({ description: 'Nombre del cliente' })
  @IsOptional()
  @IsString()
  nombre?: string;

  @ApiPropertyOptional({ description: 'Gmail del cliente' })
  @IsOptional()
  @IsEmail()
  gmail?: string;

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

  @ApiPropertyOptional({ description: 'Nombre de quien recibe al cliente en recepción' })
  @IsOptional()
  @IsString()
  receptor?: string;
}
