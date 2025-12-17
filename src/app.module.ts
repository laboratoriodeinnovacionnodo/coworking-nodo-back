import { Module } from '@nestjs/common';
import { ConfigModule } from '@nestjs/config';
import { AreaModule } from './area/area.module';
import { UsuarioModule } from './usuario/usuario.module';
import { ReservaModule } from './reserva/reserva.module';
import { PrismaModule } from 'prisma/prisma.module';
import { AuthModule } from './auth/auth.module';

@Module({
  imports: [
    ConfigModule.forRoot({
      isGlobal: true,
    }),
    PrismaModule,
    AreaModule,
    UsuarioModule,
    ReservaModule,
    AuthModule,
  ],
})
export class AppModule {}
