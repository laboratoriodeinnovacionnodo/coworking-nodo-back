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
