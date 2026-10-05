import { Injectable, Logger } from '@nestjs/common';
import { Cron, CronExpression } from '@nestjs/schedule';
import { PrismaService } from 'prisma/prisma.service';
import { AreaStatus } from '@prisma/client';

/**
 * Convierte "HH:mm" a minutos desde medianoche.
 */
function toMin(hhmm: string): number {
  const [h, m] = hhmm.split(':').map(Number);
  return h * 60 + m;
}

/**
 * Devuelve la fecha/hora actual en zona Argentina (UTC-3)
 * como { fechaHoy: "YYYY-MM-DD", minNow: number }.
 */
function nowArgentina(): { fechaHoy: string; minNow: number } {
  const ar = new Date(Date.now() - 3 * 60 * 60 * 1000);
  const fechaHoy = ar.toISOString().split('T')[0];
  const minNow = ar.getUTCHours() * 60 + ar.getUTCMinutes();
  return { fechaHoy, minNow };
}

@Injectable()
export class OcupacionCronService {
  private readonly logger = new Logger(OcupacionCronService.name);

  constructor(private readonly prisma: PrismaService) {}

  /**
   * Cada minuto sincroniza el estado de las áreas con las ocupaciones activas.
   *
   * Lógica:
   *   - Una ocupación está EN CURSO si:
   *       fechaDesde <= hoy <= fechaHasta
   *       Y horaDesde <= minNow < horaHasta
   *   - Si está en curso  → sus áreas deben estar OCUPADO
   *   - Si NO está en curso (ya venció o aún no empieza) → sus áreas pueden
   *     quedar LIBRE (a menos que otra ocupación activa las use)
   *
   * Solo procesa ocupaciones sin liberadaAt (no liberadas manualmente).
   */
  @Cron(CronExpression.EVERY_MINUTE)
  async sincronizarEstadoAreas(): Promise<void> {
    const { fechaHoy, minNow } = nowArgentina();
    const hoyDate = new Date(`${fechaHoy}T00:00:00.000Z`);

    try {
      // Traer todas las ocupaciones no liberadas manualmente que pueden
      // tener impacto hoy (desde <= hoy <= hasta)
      const ocupaciones = await this.prisma.ocupacion.findMany({
        where: {
          liberadaAt: null,
          fechaDesde: { lte: new Date(`${fechaHoy}T23:59:59.000Z`) },
          fechaHasta: { gte: hoyDate },
        },
        include: { areas: true },
      });

      const idsEnCurso = new Set<number>();
      const idsVencidas: number[] = []; // ocupaciones que YA terminaron

      for (const oc of ocupaciones) {
        const ocDesde = oc.fechaDesde.toISOString().split('T')[0];
        const ocHasta = oc.fechaHasta.toISOString().split('T')[0];

        // ¿Está en curso ahora mismo?
        const enCurso = (() => {
          if (ocDesde > fechaHoy || ocHasta < fechaHoy) return false;
          // Mismo día inicio y fin
          if (ocDesde === fechaHoy && ocHasta === fechaHoy) {
            return minNow >= toMin(oc.horaDesde) && minNow < toMin(oc.horaHasta);
          }
          // Rango multi-día: hoy es el primer día
          if (ocDesde === fechaHoy) {
            return minNow >= toMin(oc.horaDesde);
          }
          // Rango multi-día: hoy es el último día
          if (ocHasta === fechaHoy) {
            return minNow < toMin(oc.horaHasta);
          }
          // Día intermedio → siempre en curso
          return true;
        })();

        // ¿Ya venció completamente?
        const vencida = (() => {
          if (ocHasta < fechaHoy) return true;
          if (ocHasta === fechaHoy) return minNow >= toMin(oc.horaHasta);
          return false;
        })();

        if (enCurso) {
          oc.areas.forEach((r) => idsEnCurso.add(r.areaId));
        }

        if (vencida) {
          idsVencidas.push(oc.id);
        }
      }

      // ── Marcar OCUPADO las áreas en curso ────────────────────────────────
      if (idsEnCurso.size > 0) {
        await this.prisma.area.updateMany({
          where: { id: { in: [...idsEnCurso] }, estado: AreaStatus.LIBRE },
          data: { estado: AreaStatus.OCUPADO },
        });
      }

      // ── Liberar áreas de ocupaciones vencidas ────────────────────────────
      if (idsVencidas.length > 0) {
        // Áreas que pertenecen a ocupaciones vencidas
        const areasVencidas = await this.prisma.ocupacionArea.findMany({
          where: { ocupacionId: { in: idsVencidas } },
          select: { areaId: true },
        });
        const idsAreasVencidas = [...new Set(areasVencidas.map((r) => r.areaId))];

        // Filtrar: no liberar áreas que siguen en uso por otra ocupación activa
        const idsALiberar = idsAreasVencidas.filter((id) => !idsEnCurso.has(id));

        // Tampoco liberar áreas con reservas de asiento activas (fin: null)
        if (idsALiberar.length > 0) {
          const reservasActivas = await this.prisma.reserva.findMany({
            where: { areaId: { in: idsALiberar }, fin: null },
            select: { areaId: true },
          });
          const idsConReserva = new Set(reservasActivas.map((r) => r.areaId));
          const idsFinalALiberar = idsALiberar.filter((id) => !idsConReserva.has(id));

          if (idsFinalALiberar.length > 0) {
            await this.prisma.area.updateMany({
              where: { id: { in: idsFinalALiberar }, estado: AreaStatus.OCUPADO },
              data: { estado: AreaStatus.LIBRE },
            });
            this.logger.log(
              `Auto-liberadas ${idsFinalALiberar.length} área(s): [${idsFinalALiberar.join(', ')}]`,
            );
          }
        }
      }
    } catch (err) {
      this.logger.error('Error en sincronizarEstadoAreas:', err);
    }
  }
}
