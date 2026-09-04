import { Injectable, OnModuleInit, OnModuleDestroy, Logger } from '@nestjs/common';
import { PrismaClient } from '@prisma/client';
import { PrismaPg } from '@prisma/adapter-pg';
import * as pg from 'pg';

@Injectable()
export class PrismaService extends PrismaClient implements OnModuleInit, OnModuleDestroy {
  private readonly logger = new Logger(PrismaService.name);
  private readonly pool: pg.Pool;

  constructor() {
    const connectionString = process.env.DATABASE_URL;

    // Pool con límite explícito — evita saturar PostgreSQL
    const pool = new pg.Pool({
      connectionString,
      max:                    10,   // máximo 10 conexiones simultáneas
      idleTimeoutMillis:   30_000, // libera conexiones inactivas a los 30s
      connectionTimeoutMillis: 5_000, // error si no consigue conexión en 5s
    });

    pool.on('error', (err) => {
      // Log del error pero sin crashear la app
      console.error('[PrismaService] Pool error:', err.message);
    });

    const adapter = new PrismaPg(pool);

    super({ adapter });

    // Guardar referencia para destruir el pool al apagar
    this.pool = pool;
  }

  async onModuleInit() {
    await this.$connect();
    this.logger.log('Prisma conectado (pool max=10)');
  }

  async onModuleDestroy() {
    await this.$disconnect();
    await this.pool.end();
    this.logger.log('Prisma desconectado');
  }
}
