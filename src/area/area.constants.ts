import { CodigoArea, ZonaArea } from '@prisma/client';

/** Zona a la que pertenece cada código (A → naranjas, B → rojos, C → negros). */
export const ZONA_POR_CODIGO: Record<CodigoArea, ZonaArea> = {
  A1: ZonaArea.SILLONES_NARANJAS,
  A2: ZonaArea.SILLONES_NARANJAS,
  B1: ZonaArea.SILLONES_ROJOS,
  B2: ZonaArea.SILLONES_ROJOS,
  B3: ZonaArea.SILLONES_ROJOS,
  B4: ZonaArea.SILLONES_ROJOS,
  C1: ZonaArea.SEMICIRCULOS_NEGROS,
  C2: ZonaArea.SEMICIRCULOS_NEGROS,
  C3: ZonaArea.SEMICIRCULOS_NEGROS,
};

/** Nombre legible de cada zona (Prisma no permite etiquetas en enums). */
export const NOMBRE_ZONA: Record<ZonaArea, string> = {
  SILLONES_NARANJAS: 'Sillones Naranjas',
  SILLONES_ROJOS: 'Sillones Rojos',
  SEMICIRCULOS_NEGROS: 'Semicírculos Negros',
};
