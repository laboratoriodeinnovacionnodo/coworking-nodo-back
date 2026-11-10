import 'dotenv/config';
import { AreaStatus, CodigoArea, PrismaClient } from '@prisma/client';
import { PrismaPg } from '@prisma/adapter-pg';
import * as pg from 'pg';
import { ZONA_POR_CODIGO } from '../src/area/area.constants';

const pool = new pg.Pool({ connectionString: process.env.DATABASE_URL });
const prisma = new PrismaClient({ adapter: new PrismaPg(pool) });

async function seedAdmin() {
  const email = 'admin@nodo.com';
  // AuthService.login compara la contraseña en texto plano
  const password = 'admin@nodo.com';

  const admin = await prisma.admin.upsert({
    where: { email },
    update: { password },
    create: { email, password },
  });
  console.log(`Admin listo: ${admin.email} (id ${admin.id})`);
}

/**
 * Asegura que existan las 9 áreas A1..C3 con su `codigo` y `zona`.
 * Las áreas existentes se identifican por nombre ("A1"); no se toca su estado.
 * Es lo que permite al calendario bloquear por código/zona (PATCH /areas/bloquear).
 */
async function seedAreas() {
  for (const codigo of Object.values(CodigoArea)) {
    const zona = ZONA_POR_CODIGO[codigo];
    const existente = await prisma.area.findFirst({
      where: { OR: [{ codigo }, { nombre: codigo }] },
    });

    if (existente) {
      await prisma.area.update({ where: { id: existente.id }, data: { codigo, zona } });
    } else {
      await prisma.area.create({
        data: { nombre: codigo, codigo, zona, estado: AreaStatus.LIBRE },
      });
    }
  }
  console.log('Áreas del coworking con código y zona listas');
}

async function main() {
  await seedAdmin();
  await seedAreas();
}

main()
  .catch((e) => {
    console.error(e);
    process.exit(1);
  })
  .finally(async () => {
    await prisma.$disconnect();
    await pool.end();
  });
