import { Injectable, OnModuleInit, OnModuleDestroy } from '@nestjs/common';
import { PrismaClient } from '@prisma/client';
// Importa el adaptador de PostgreSQL
import { PrismaPg } from '@prisma/adapter-pg';
// Importa el driver pg (node-postgres)
import * as pg from 'pg';

@Injectable()
export class PrismaService extends PrismaClient implements OnModuleInit, OnModuleDestroy {

  constructor() {
    // Asegúrate de que DATABASE_URL esté disponible en tu archivo .env
    const connectionString = process.env.DATABASE_URL;

    // Crea una instancia del Pool de conexión del driver
    const pool = new pg.Pool({ connectionString });

    // Crea una instancia del adaptador de Prisma
    const adapter = new PrismaPg(pool);

    // Pasa el adaptador al constructor de PrismaClient
    super({
      adapter: adapter,
      // Puedes añadir tus logs aquí si es necesario:
      // log: ['query', 'error', 'warn'],
    });
  }

  async onModuleInit() {
    await this.$connect();
  }

  async onModuleDestroy() {
    await this.$disconnect();
  }
}
