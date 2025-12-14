import { Module } from '@nestjs/common';
import { AppController } from './app.controller';
import { AppService } from './app.service';
import { PrismaModule } from 'prisma/prisma.module';
import { UsuarioModule } from './usuario/usuario.module';
import { AreaModule } from './area/area.module';
import { ReservaModule } from './reserva/reserva.module';

@Module({
  imports: [PrismaModule, UsuarioModule, AreaModule, ReservaModule],
  controllers: [AppController],
  providers: [AppService],
})
export class AppModule {}
