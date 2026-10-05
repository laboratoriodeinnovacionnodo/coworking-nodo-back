import { Module } from '@nestjs/common';
import { OcupacionService } from './ocupacion.service';
import { OcupacionController } from './ocupacion.controller';
import { OcupacionCronService } from './ocupacion-cron.service';

@Module({
  controllers: [OcupacionController],
  providers:   [OcupacionService, OcupacionCronService],
  exports:     [OcupacionService],
})
export class OcupacionModule {}
