import { ApiPropertyOptional, ApiProperty } from '@nestjs/swagger';
import { AreaStatus, CodigoArea, ZonaArea } from '@prisma/client';
import { ArrayUnique, IsArray, IsEnum, IsOptional } from 'class-validator';

export class BloquearAreasDto {
  @ApiProperty({ enum: AreaStatus })
  @IsEnum(AreaStatus)
  estado: AreaStatus;

  @ApiPropertyOptional({ enum: CodigoArea, isArray: true })
  @IsOptional()
  @IsArray()
  @ArrayUnique()
  @IsEnum(CodigoArea, { each: true })
  codigos?: CodigoArea[];

  @ApiPropertyOptional({ enum: ZonaArea, isArray: true })
  @IsOptional()
  @IsArray()
  @ArrayUnique()
  @IsEnum(ZonaArea, { each: true })
  zonas?: ZonaArea[];
}
