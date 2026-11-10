import { AreaStatus, CodigoArea, ZonaArea } from '@prisma/client';
import { IsOptional, IsString, IsEnum } from 'class-validator';

export class CreateAreaDto {
  @IsString()
  nombre: string;

  @IsOptional()
  @IsString()
  descripcion?: string;

  @IsOptional()
  @IsEnum(AreaStatus)
  estado?: AreaStatus;

  @IsOptional()
  @IsEnum(CodigoArea)
  codigo?: CodigoArea;

  @IsOptional()
  @IsEnum(ZonaArea)
  zona?: ZonaArea;
}
