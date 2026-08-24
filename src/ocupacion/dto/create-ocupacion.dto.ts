import {
  IsString,
  IsOptional,
  IsInt,
  IsArray,
  IsUrl,
  IsDateString,
  Matches,
  Min,
  Max,
  MinLength,
  ArrayMinSize,
  ArrayMaxSize,
} from 'class-validator';
import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { Type } from 'class-transformer';

export class CreateOcupacionDto {
  @ApiProperty({ description: 'Título del evento / ocupación' })
  @IsString()
  @MinLength(3)
  titulo: string;

  @ApiProperty({ description: 'Requerimientos o descripción' })
  @IsString()
  @MinLength(3)
  requerimiento: string;

  @ApiProperty({ description: 'Cantidad estimada de personas' })
  @Type(() => Number)
  @IsInt()
  @Min(1)
  cantidadPersonas: number;

  @ApiProperty({ description: 'Nombre del organizador / solicitante' })
  @IsString()
  @MinLength(2)
  organizador: string;

  @ApiProperty({ example: '2026-08-25', description: 'Fecha de inicio (YYYY-MM-DD)' })
  @IsDateString()
  fechaDesde: string;

  @ApiProperty({ example: '2026-08-25', description: 'Fecha de fin (YYYY-MM-DD)' })
  @IsDateString()
  fechaHasta: string;

  @ApiProperty({ example: '09:00', description: 'Hora de inicio (HH:mm)' })
  @IsString()
  @Matches(/^([0-1]?\d|2[0-3]):[0-5]\d$/, { message: 'horaDesde debe ser HH:mm' })
  horaDesde: string;

  @ApiProperty({ example: '12:00', description: 'Hora de fin (HH:mm)' })
  @IsString()
  @Matches(/^([0-1]?\d|2[0-3]):[0-5]\d$/, { message: 'horaHasta debe ser HH:mm' })
  horaHasta: string;

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

  @ApiProperty({ description: 'IDs de las áreas a ocupar', type: [Number] })
  @IsArray()
  @ArrayMinSize(1)
  @Type(() => Number)
  @IsInt({ each: true })
  areaIds: number[];
}
