import { PartialType } from '@nestjs/swagger';
import { CreateOcupacionDto } from './create-ocupacion.dto';

export class UpdateOcupacionDto extends PartialType(CreateOcupacionDto) {}
