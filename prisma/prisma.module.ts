import { Global, Module } from '@nestjs/common';
import { PrismaService } from './prisma.service';

@Global() // Hace que Prisma esté disponible en toda la app sin imports adicionales
@Module({
  providers: [PrismaService],
  exports: [PrismaService],
})
export class PrismaModule {}
