import { Module } from '@nestjs/common';
import { OcupacionService } from './ocupacion.service';
import { OcupacionController } from './ocupacion.controller';

@Module({
  controllers: [OcupacionController],
  providers:   [OcupacionService],
  exports:     [OcupacionService],
})
export class OcupacionModule {}
