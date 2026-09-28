import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { IsEmail, IsEnum, IsInt, IsOptional, IsString } from 'class-validator';
import { Recepcion } from '@prisma/client';

export class CreateReservaDto {
  @ApiProperty({ description: 'Nombre del cliente que reserva' })
  @IsString()
  nombre: string;

  @ApiPropertyOptional({ description: 'Gmail del cliente' })
  @IsOptional()
  @IsEmail()
  gmail?: string;

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

  @ApiPropertyOptional({ description: 'Nombre de quien recibe al cliente en recepción' })
  @IsOptional()
  @IsString()
  receptor?: string;
}
