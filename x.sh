#!/usr/bin/env bash
# ============================================================================
#  v7-fix-ocupaciones-lista.sh
#  Fixes:
#    1. [BACK]  hoyArgentina() usa setHours() mutable → fecha incorrecta en
#               findActivas(). Reemplazado por Intl.DateTimeFormat (inmutable).
#    2. [FRONT] agendar-modal no llama onSuccess() → lista no se recarga.
#    3. [FRONT] disponibilidad-inline: toast en dep array de useCallback
#               causa loop/no-recarga. Movido a ref estable con useRef.
#
#  Sin cambios de schema — no requiere prisma migrate.
#
#  Uso:
#    # Backend:
#    cd coworking-back && chmod +x v7-fix-ocupaciones-lista.sh && ./v7-fix-ocupaciones-lista.sh
#    # Frontend:
#    cd coworking-front && chmod +x v7-fix-ocupaciones-lista.sh && ./v7-fix-ocupaciones-lista.sh
#
#  El script detecta automáticamente en qué repo está y aplica solo
#  los cambios que corresponden.
# ============================================================================
set -euo pipefail

# ── Detección de proyecto ────────────────────────────────────────────────────
IS_BACK=false
IS_FRONT=false

if [ -f "package.json" ] && [ -d "src" ] && grep -q "nestjs" package.json 2>/dev/null; then
  IS_BACK=true
fi
if [ -f "package.json" ] && [ -d "app" ] && grep -q "next" package.json 2>/dev/null; then
  IS_FRONT=true
fi

if [ "$IS_BACK" = false ] && [ "$IS_FRONT" = false ]; then
  echo "❌  No se reconoce el proyecto. Corré desde coworking-back o coworking-front."
  exit 1
fi

# ════════════════════════════════════════════════════════════════════════════
# BACKEND — Fix hoyArgentina() en ocupacion.service.ts
# ════════════════════════════════════════════════════════════════════════════
if [ "$IS_BACK" = true ]; then
  echo ""
  echo "╔══════════════════════════════════════════════════════════════════╗"
  echo "║  🔧  BACKEND — Fix hoyArgentina() en OcupacionService           ║"
  echo "╚══════════════════════════════════════════════════════════════════╝"

  cat > src/ocupacion/ocupacion.service.ts << 'EOF'
import {
  Injectable,
  NotFoundException,
  BadRequestException,
  Logger,
} from '@nestjs/common';
import { Cron } from '@nestjs/schedule';
import { PrismaService } from 'prisma/prisma.service';
import { CreateOcupacionDto } from './dto/create-ocupacion.dto';
import { UpdateOcupacionDto } from './dto/update-ocupacion.dto';
import { AreaStatus } from '@prisma/client';

// ── Helpers de tiempo ─────────────────────────────────────────────────────────

function timeToMinutes(hhmm: string): number {
  const [h, m] = hhmm.split(':').map(Number);
  return h * 60 + m;
}

/**
 * Fecha local Argentina como YYYY-MM-DD (UTC-3).
 * Usa Intl.DateTimeFormat (inmutable) en lugar de setHours() mutable,
 * que era la causa del bug en findActivas().
 */
function hoyArgentina(): string {
  return new Intl.DateTimeFormat('es-AR', {
    timeZone: 'America/Argentina/Buenos_Aires',
    year:     'numeric',
    month:    '2-digit',
    day:      '2-digit',
  })
    .format(new Date())
    .split('/')               // dd/mm/yyyy
    .reverse()                // yyyy, mm, dd
    .join('-');               // yyyy-mm-dd
}

@Injectable()
export class OcupacionService {
  private readonly logger = new Logger(OcupacionService.name);

  constructor(private readonly prisma: PrismaService) {}

  // ── Verifica conflicto de horario para un área ────────────────────────────
  private async verificarConflicto(
    areaIds: number[],
    fechaDesde: string,
    fechaHasta: string,
    horaDesde: string,
    horaHasta: string,
    excludeId?: number,
  ): Promise<void> {
    const ocupacionesActivas = await this.prisma.ocupacion.findMany({
      where: {
        liberadaAt: null,
        ...(excludeId ? { id: { not: excludeId } } : {}),
        areas: { some: { areaId: { in: areaIds } } },
        AND: [
          { fechaDesde: { lte: new Date(`${fechaHasta}T23:59:59.000Z`) } },
          { fechaHasta: { gte: new Date(`${fechaDesde}T00:00:00.000Z`) } },
        ],
      },
      include: { areas: { include: { area: true } } },
    });

    const nuevaInicio = timeToMinutes(horaDesde);
    const nuevaFin    = timeToMinutes(horaHasta);

    for (const oc of ocupacionesActivas) {
      const existInicio = timeToMinutes(oc.horaDesde);
      const existFin    = timeToMinutes(oc.horaHasta);
      const solapan     = nuevaInicio < existFin && nuevaFin > existInicio;
      if (!solapan) continue;

      const areasConflicto = oc.areas
        .filter((r) => areaIds.includes(r.areaId))
        .map((r) => r.area.nombre)
        .join(', ');

      throw new BadRequestException(
        `Conflicto de horario: las áreas [${areasConflicto}] ya están ocupadas ` +
        `el ${oc.fechaDesde.toISOString().split('T')[0]} de ${oc.horaDesde} a ${oc.horaHasta} ` +
        `(ocupación "${oc.titulo}")`,
      );
    }
  }

  // ── CREATE ────────────────────────────────────────────────────────────────
  async create(dto: CreateOcupacionDto) {
    if (dto.edadMin !== undefined && dto.edadMax !== undefined && dto.edadMin > dto.edadMax) {
      throw new BadRequestException('edadMin no puede ser mayor que edadMax');
    }
    if (dto.fechaDesde > dto.fechaHasta) {
      throw new BadRequestException('fechaDesde no puede ser posterior a fechaHasta');
    }
    if (dto.fechaDesde === dto.fechaHasta && dto.horaDesde >= dto.horaHasta) {
      throw new BadRequestException('horaDesde debe ser anterior a horaHasta');
    }

    const areas = await this.prisma.area.findMany({ where: { id: { in: dto.areaIds } } });
    if (areas.length !== dto.areaIds.length) {
      const missing = dto.areaIds.filter((id) => !areas.map((a) => a.id).includes(id));
      throw new NotFoundException(`Área(s) no encontrada(s): ${missing.join(', ')}`);
    }

    await this.verificarConflicto(dto.areaIds, dto.fechaDesde, dto.fechaHasta, dto.horaDesde, dto.horaHasta);

    const ocupacion = await this.prisma.$transaction(async (tx) => {
      const nueva = await tx.ocupacion.create({
        data: {
          titulo:           dto.titulo,
          requerimiento:    dto.requerimiento,
          cantidadPersonas: dto.cantidadPersonas,
          organizador:      dto.organizador,
          fechaDesde:       new Date(`${dto.fechaDesde}T00:00:00.000Z`),
          fechaHasta:       new Date(`${dto.fechaHasta}T23:59:59.000Z`),
          horaDesde:        dto.horaDesde,
          horaHasta:        dto.horaHasta,
          edadMin:          dto.edadMin,
          edadMax:          dto.edadMax,
          anexos:           dto.anexos ?? [],
          areas: { create: dto.areaIds.map((areaId) => ({ areaId })) },
        },
        include: { areas: { include: { area: true } } },
      });

      await tx.area.updateMany({
        where: { id: { in: dto.areaIds } },
        data:  { estado: AreaStatus.OCUPADO },
      });

      return nueva;
    });

    return ocupacion;
  }

  // ── FIND ALL ──────────────────────────────────────────────────────────────
  findAll() {
    return this.prisma.ocupacion.findMany({
      orderBy: { fechaDesde: 'asc' },
      include: { areas: { include: { area: true } } },
    });
  }

  // ── FIND ACTIVAS (sin liberadaAt, fechaHasta >= hoy Argentina) ────────────
  findActivas() {
    // hoyArgentina() ahora usa Intl.DateTimeFormat — no más bug de setHours()
    const hoy = hoyArgentina();
    return this.prisma.ocupacion.findMany({
      where: {
        liberadaAt: null,
        fechaHasta: { gte: new Date(`${hoy}T00:00:00.000Z`) },
      },
      orderBy: { fechaDesde: 'asc' },
      include: { areas: { include: { area: true } } },
    });
  }

  // ── FIND ONE ──────────────────────────────────────────────────────────────
  async findOne(id: number) {
    const ocupacion = await this.prisma.ocupacion.findUnique({
      where: { id },
      include: { areas: { include: { area: true } } },
    });
    if (!ocupacion) throw new NotFoundException(`Ocupación ${id} no encontrada`);
    return ocupacion;
  }

  // ── UPDATE ────────────────────────────────────────────────────────────────
  async update(id: number, dto: UpdateOcupacionDto) {
    const actual = await this.findOne(id);

    if (dto.edadMin !== undefined && dto.edadMax !== undefined && dto.edadMin > dto.edadMax) {
      throw new BadRequestException('edadMin no puede ser mayor que edadMax');
    }

    const fechaDesde = dto.fechaDesde ?? actual.fechaDesde.toISOString().split('T')[0];
    const fechaHasta = dto.fechaHasta ?? actual.fechaHasta.toISOString().split('T')[0];
    const horaDesde  = dto.horaDesde  ?? actual.horaDesde;
    const horaHasta  = dto.horaHasta  ?? actual.horaHasta;
    const areaIds    = dto.areaIds    ?? actual.areas.map((r: { areaId: number }) => r.areaId);

    await this.verificarConflicto(areaIds, fechaDesde, fechaHasta, horaDesde, horaHasta, id);

    return this.prisma.ocupacion.update({
      where: { id },
      data: {
        ...(dto.titulo           !== undefined && { titulo:           dto.titulo }),
        ...(dto.requerimiento    !== undefined && { requerimiento:    dto.requerimiento }),
        ...(dto.cantidadPersonas !== undefined && { cantidadPersonas: dto.cantidadPersonas }),
        ...(dto.organizador      !== undefined && { organizador:      dto.organizador }),
        ...(dto.fechaDesde       !== undefined && { fechaDesde:       new Date(`${dto.fechaDesde}T00:00:00.000Z`) }),
        ...(dto.fechaHasta       !== undefined && { fechaHasta:       new Date(`${dto.fechaHasta}T23:59:59.000Z`) }),
        ...(dto.horaDesde        !== undefined && { horaDesde:        dto.horaDesde }),
        ...(dto.horaHasta        !== undefined && { horaHasta:        dto.horaHasta }),
        ...(dto.edadMin          !== undefined && { edadMin:          dto.edadMin }),
        ...(dto.edadMax          !== undefined && { edadMax:          dto.edadMax }),
        ...(dto.anexos           !== undefined && { anexos:           dto.anexos }),
      },
      include: { areas: { include: { area: true } } },
    });
  }

  // ── LIBERAR ───────────────────────────────────────────────────────────────
  async liberar(id: number) {
    const ocupacion = await this.findOne(id);
    const areaIds   = ocupacion.areas.map((r: { areaId: number }) => r.areaId);

    return this.prisma.$transaction(async (tx) => {
      if (areaIds.length > 0) {
        await tx.area.updateMany({
          where: { id: { in: areaIds } },
          data:  { estado: AreaStatus.LIBRE },
        });
      }
      return tx.ocupacion.update({
        where: { id },
        data:  { liberadaAt: new Date() },
        include: { areas: { include: { area: true } } },
      });
    });
  }

  // ── DELETE ────────────────────────────────────────────────────────────────
  async remove(id: number) {
    const ocupacion = await this.findOne(id);
    const areaIds   = ocupacion.areas.map((r: { areaId: number }) => r.areaId);

    await this.prisma.$transaction(async (tx) => {
      if (areaIds.length > 0) {
        await tx.area.updateMany({
          where: { id: { in: areaIds } },
          data:  { estado: AreaStatus.LIBRE },
        });
      }
      await tx.ocupacion.delete({ where: { id } });
    });
  }

  // ── AUTO-LIBERAR (cron cada minuto) ───────────────────────────────────────
  @Cron('* * * * *')
  async autoLiberarVencidas() {
    const ahora      = new Date();
    // UTC-3 inmutable
    const ahoraUTC3  = new Date(ahora.getTime() - 3 * 60 * 60 * 1000);
    const fechaHoy   = ahoraUTC3.toISOString().split('T')[0];
    const minutosNow = ahoraUTC3.getUTCHours() * 60 + ahoraUTC3.getUTCMinutes();

    try {
      const candidatas = await this.prisma.ocupacion.findMany({
        where: {
          liberadaAt: null,
          fechaHasta: { lte: new Date(`${fechaHoy}T23:59:59.000Z`) },
        },
        include: { areas: { include: { area: true } } },
      });

      for (const oc of candidatas) {
        const fechaFin = oc.fechaHasta.toISOString().split('T')[0];

        if (fechaFin < fechaHoy) {
          await this.liberarInterno(oc);
          continue;
        }

        if (fechaFin === fechaHoy) {
          const minutosFin = timeToMinutes(oc.horaHasta);
          if (minutosNow >= minutosFin) {
            await this.liberarInterno(oc);
          }
        }
      }
    } catch (err) {
      this.logger.error('Error en autoLiberarVencidas:', (err as Error).message);
    }
  }

  private async liberarInterno(oc: { id: number; areas: { areaId: number }[] }) {
    const areaIds = oc.areas.map((r) => r.areaId);
    await this.prisma.$transaction(async (tx) => {
      if (areaIds.length > 0) {
        await tx.area.updateMany({
          where: { id: { in: areaIds } },
          data:  { estado: AreaStatus.LIBRE },
        });
      }
      await tx.ocupacion.update({
        where: { id: oc.id },
        data:  { liberadaAt: new Date() },
      });
    });
    this.logger.log(`⏰ Auto-liberada ocupación ${oc.id}`);
  }
}
EOF
  echo "✅  src/ocupacion/ocupacion.service.ts"

  echo ""
  echo "🔨  Compilando backend..."
  pnpm build

  echo ""
  echo "╔══════════════════════════════════════════════════════════════════╗"
  echo "║  ✅  BACKEND completado                                          ║"
  echo "╚══════════════════════════════════════════════════════════════════╝"
  echo ""
  echo "  Fix aplicado:"
  echo "    · hoyArgentina() → Intl.DateTimeFormat('America/Argentina/Buenos_Aires')"
  echo "    · findActivas() filtra correctamente con la fecha de hoy en AR"
  echo "    · autoLiberarVencidas() ya usaba UTC-3 inmutable → sin cambios"
  echo ""
  echo "  ⚠️  No requiere prisma migrate (sin cambios de schema)"
  echo ""
fi

# ════════════════════════════════════════════════════════════════════════════
# FRONTEND — Fix agendar-modal + disponibilidad-inline
# ════════════════════════════════════════════════════════════════════════════
if [ "$IS_FRONT" = true ]; then
  echo ""
  echo "╔══════════════════════════════════════════════════════════════════╗"
  echo "║  🔧  FRONTEND — Fix modal + disponibilidad                      ║"
  echo "╚══════════════════════════════════════════════════════════════════╝"

  # ── Fix 1: agendar-modal.tsx — llamar onSuccess tras crear ──────────────
  echo "📄  components/agendar-modal.tsx..."
  cat > components/agendar-modal.tsx << 'EOF'
"use client"

import { useState, useCallback, useEffect } from "react"
import { ocupacionesApi } from "@/lib/ocupacion-api"
import { areasApi } from "@/lib/api"
import type { CreateOcupacionPayload } from "@/types/ocupacion"
import type { BackendArea } from "@/types/seat"
import { useToast } from "@/hooks/use-toast"

import { Button }   from "@/components/ui/button"
import { Input }    from "@/components/ui/input"
import { Label }    from "@/components/ui/label"
import { Textarea } from "@/components/ui/textarea"
import { Badge }    from "@/components/ui/badge"
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogFooter,
  DialogDescription,
} from "@/components/ui/dialog"
import {
  CalendarDays,
  Clock,
  Users,
  User,
  FileText,
  Link2,
  Plus,
  Trash2,
  Loader2,
  ChevronDown,
  ChevronUp,
  MapPin,
  X,
  CheckSquare,
} from "lucide-react"

interface AgendarModalProps {
  open:         boolean
  onOpenChange: (open: boolean) => void
  onSuccess?:   () => void
}

const EMPTY_FORM = {
  titulo:           "",
  requerimiento:    "",
  cantidadPersonas: 1,
  organizador:      "",
  fechaDesde:       "",
  fechaHasta:       "",
  horaDesde:        "",
  horaHasta:        "",
  edadMin:          "",
  edadMax:          "",
}

export function AgendarModal({ open, onOpenChange, onSuccess }: AgendarModalProps) {
  const { toast } = useToast()

  const [form,       setForm]       = useState(EMPTY_FORM)
  const [anexos,     setAnexos]     = useState<string[]>([])
  const [newAnexo,   setNewAnexo]   = useState("")
  const [areas,      setAreas]      = useState<BackendArea[]>([])
  const [areaIds,    setAreaIds]    = useState<number[]>([])
  const [loading,    setLoading]    = useState(false)
  const [loadAreas,  setLoadAreas]  = useState(false)
  const [showEdad,   setShowEdad]   = useState(false)
  const [showAnexos, setShowAnexos] = useState(false)

  // Cargar áreas disponibles al abrir
  useEffect(() => {
    if (!open) return
    setLoadAreas(true)
    areasApi.getAll()
      .then(setAreas)
      .catch(() => toast({ variant: "destructive", title: "Error", description: "No se pudieron cargar las áreas" }))
      .finally(() => setLoadAreas(false))
  }, [open, toast])

  const resetForm = useCallback(() => {
    setForm(EMPTY_FORM)
    setAnexos([])
    setNewAnexo("")
    setAreaIds([])
    setShowEdad(false)
    setShowAnexos(false)
  }, [])

  const handleClose = useCallback(() => {
    onOpenChange(false)
    resetForm()
  }, [onOpenChange, resetForm])

  const toggleArea = (id: number) =>
    setAreaIds((prev) => prev.includes(id) ? prev.filter((x) => x !== id) : [...prev, id])

  const addAnexo = () => {
    const url = newAnexo.trim()
    if (!url) return
    setAnexos((prev) => [...prev, url])
    setNewAnexo("")
  }

  const handleSubmit = async () => {
    // Validaciones básicas del formulario
    if (!form.titulo.trim())       { toast({ variant: "destructive", title: "Falta título" });        return }
    if (!form.organizador.trim())  { toast({ variant: "destructive", title: "Falta organizador" });   return }
    if (!form.requerimiento.trim()){ toast({ variant: "destructive", title: "Falta requerimiento" }); return }
    if (!form.fechaDesde)          { toast({ variant: "destructive", title: "Falta fecha desde" });   return }
    if (!form.fechaHasta)          { toast({ variant: "destructive", title: "Falta fecha hasta" });   return }
    if (!form.horaDesde)           { toast({ variant: "destructive", title: "Falta hora desde" });    return }
    if (!form.horaHasta)           { toast({ variant: "destructive", title: "Falta hora hasta" });    return }
    if (areaIds.length === 0)      { toast({ variant: "destructive", title: "Seleccioná al menos un área" }); return }

    const payload: CreateOcupacionPayload = {
      titulo:           form.titulo.trim(),
      requerimiento:    form.requerimiento.trim(),
      cantidadPersonas: Number(form.cantidadPersonas),
      organizador:      form.organizador.trim(),
      fechaDesde:       form.fechaDesde,
      fechaHasta:       form.fechaHasta,
      horaDesde:        form.horaDesde,
      horaHasta:        form.horaHasta,
      anexos,
      areaIds,
      ...(form.edadMin && { edadMin: Number(form.edadMin) }),
      ...(form.edadMax && { edadMax: Number(form.edadMax) }),
    }

    setLoading(true)
    try {
      await ocupacionesApi.create(payload)
      toast({ title: "✅ Ocupación agendada", description: `"${payload.titulo}" creada correctamente` })
      handleClose()
      // ✅ FIX: notifica al padre para que recargue la lista
      onSuccess?.()
    } catch (err) {
      const msg = err instanceof Error ? err.message : "Error desconocido"
      toast({ variant: "destructive", title: "Error al agendar", description: msg })
    } finally {
      setLoading(false)
    }
  }

  return (
    <Dialog open={open} onOpenChange={handleClose}>
      <DialogContent className="max-w-lg w-full max-h-[90vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle className="flex items-center gap-2 text-xl">
            <CalendarDays className="w-5 h-5 text-primary" />
            Agendar Ocupación
          </DialogTitle>
          <DialogDescription>
            Reservá uno o más espacios para un evento o actividad
          </DialogDescription>
        </DialogHeader>

        <div className="space-y-4 py-2">
          {/* Título */}
          <div className="space-y-1.5">
            <Label htmlFor="titulo" className="flex items-center gap-1.5 text-sm font-medium">
              <FileText className="w-3.5 h-3.5" /> Título *
            </Label>
            <Input
              id="titulo"
              placeholder="Ej: Taller de fotografía"
              value={form.titulo}
              onChange={(e) => setForm((f) => ({ ...f, titulo: e.target.value }))}
            />
          </div>

          {/* Organizador */}
          <div className="space-y-1.5">
            <Label htmlFor="organizador" className="flex items-center gap-1.5 text-sm font-medium">
              <User className="w-3.5 h-3.5" /> Organizador *
            </Label>
            <Input
              id="organizador"
              placeholder="Nombre del responsable"
              value={form.organizador}
              onChange={(e) => setForm((f) => ({ ...f, organizador: e.target.value }))}
            />
          </div>

          {/* Requerimiento */}
          <div className="space-y-1.5">
            <Label htmlFor="requerimiento" className="flex items-center gap-1.5 text-sm font-medium">
              <FileText className="w-3.5 h-3.5" /> Requerimiento *
            </Label>
            <Textarea
              id="requerimiento"
              placeholder="Describe los requerimientos del espacio..."
              rows={2}
              value={form.requerimiento}
              onChange={(e) => setForm((f) => ({ ...f, requerimiento: e.target.value }))}
            />
          </div>

          {/* Cantidad de personas */}
          <div className="space-y-1.5">
            <Label htmlFor="cantPersonas" className="flex items-center gap-1.5 text-sm font-medium">
              <Users className="w-3.5 h-3.5" /> Cantidad de personas *
            </Label>
            <Input
              id="cantPersonas"
              type="number"
              min={1}
              value={form.cantidadPersonas}
              onChange={(e) => setForm((f) => ({ ...f, cantidadPersonas: Number(e.target.value) }))}
            />
          </div>

          {/* Fechas */}
          <div className="grid grid-cols-2 gap-3">
            <div className="space-y-1.5">
              <Label htmlFor="fechaDesde" className="flex items-center gap-1.5 text-sm font-medium">
                <CalendarDays className="w-3.5 h-3.5" /> Fecha desde *
              </Label>
              <Input
                id="fechaDesde"
                type="date"
                value={form.fechaDesde}
                onChange={(e) => setForm((f) => ({ ...f, fechaDesde: e.target.value }))}
              />
            </div>
            <div className="space-y-1.5">
              <Label htmlFor="fechaHasta" className="flex items-center gap-1.5 text-sm font-medium">
                <CalendarDays className="w-3.5 h-3.5" /> Fecha hasta *
              </Label>
              <Input
                id="fechaHasta"
                type="date"
                value={form.fechaHasta}
                onChange={(e) => setForm((f) => ({ ...f, fechaHasta: e.target.value }))}
              />
            </div>
          </div>

          {/* Horas */}
          <div className="grid grid-cols-2 gap-3">
            <div className="space-y-1.5">
              <Label htmlFor="horaDesde" className="flex items-center gap-1.5 text-sm font-medium">
                <Clock className="w-3.5 h-3.5" /> Hora desde *
              </Label>
              <Input
                id="horaDesde"
                type="time"
                value={form.horaDesde}
                onChange={(e) => setForm((f) => ({ ...f, horaDesde: e.target.value }))}
              />
            </div>
            <div className="space-y-1.5">
              <Label htmlFor="horaHasta" className="flex items-center gap-1.5 text-sm font-medium">
                <Clock className="w-3.5 h-3.5" /> Hora hasta *
              </Label>
              <Input
                id="horaHasta"
                type="time"
                value={form.horaHasta}
                onChange={(e) => setForm((f) => ({ ...f, horaHasta: e.target.value }))}
              />
            </div>
          </div>

          {/* Áreas */}
          <div className="space-y-1.5">
            <Label className="flex items-center gap-1.5 text-sm font-medium">
              <MapPin className="w-3.5 h-3.5" /> Áreas a reservar *
            </Label>
            {loadAreas ? (
              <div className="flex items-center gap-2 text-sm text-muted-foreground py-2">
                <Loader2 className="w-4 h-4 animate-spin" /> Cargando áreas...
              </div>
            ) : (
              <div className="flex flex-wrap gap-2">
                {areas.map((area) => {
                  const sel = areaIds.includes(area.id)
                  return (
                    <button
                      key={area.id}
                      type="button"
                      onClick={() => toggleArea(area.id)}
                      className={`inline-flex items-center gap-1.5 px-3 py-1.5 rounded-full text-sm font-medium border transition-colors ${
                        sel
                          ? "bg-primary text-primary-foreground border-primary"
                          : "bg-background border-border text-foreground hover:bg-muted"
                      }`}
                    >
                      {sel && <CheckSquare className="w-3.5 h-3.5" />}
                      {area.nombre}
                    </button>
                  )
                })}
              </div>
            )}
            {areaIds.length > 0 && (
              <p className="text-xs text-muted-foreground">{areaIds.length} área(s) seleccionada(s)</p>
            )}
          </div>

          {/* Edad (colapsable) */}
          <div>
            <button
              type="button"
              className="flex items-center gap-1.5 text-sm text-muted-foreground hover:text-foreground transition-colors"
              onClick={() => setShowEdad((v) => !v)}
            >
              {showEdad ? <ChevronUp className="w-4 h-4" /> : <ChevronDown className="w-4 h-4" />}
              Restricción de edad (opcional)
            </button>
            {showEdad && (
              <div className="grid grid-cols-2 gap-3 mt-2">
                <div className="space-y-1.5">
                  <Label htmlFor="edadMin" className="text-sm font-medium">Edad mínima</Label>
                  <Input
                    id="edadMin"
                    type="number"
                    min={0}
                    placeholder="0"
                    value={form.edadMin}
                    onChange={(e) => setForm((f) => ({ ...f, edadMin: e.target.value }))}
                  />
                </div>
                <div className="space-y-1.5">
                  <Label htmlFor="edadMax" className="text-sm font-medium">Edad máxima</Label>
                  <Input
                    id="edadMax"
                    type="number"
                    min={0}
                    placeholder="99"
                    value={form.edadMax}
                    onChange={(e) => setForm((f) => ({ ...f, edadMax: e.target.value }))}
                  />
                </div>
              </div>
            )}
          </div>

          {/* Anexos (colapsable) */}
          <div>
            <button
              type="button"
              className="flex items-center gap-1.5 text-sm text-muted-foreground hover:text-foreground transition-colors"
              onClick={() => setShowAnexos((v) => !v)}
            >
              {showAnexos ? <ChevronUp className="w-4 h-4" /> : <ChevronDown className="w-4 h-4" />}
              Anexos / enlaces (opcional)
            </button>
            {showAnexos && (
              <div className="space-y-2 mt-2">
                <div className="flex gap-2">
                  <Input
                    placeholder="https://..."
                    value={newAnexo}
                    onChange={(e) => setNewAnexo(e.target.value)}
                    onKeyDown={(e) => { if (e.key === "Enter") { e.preventDefault(); addAnexo() } }}
                  />
                  <Button type="button" variant="outline" size="icon" onClick={addAnexo}>
                    <Plus className="w-4 h-4" />
                  </Button>
                </div>
                {anexos.map((url, i) => (
                  <div key={i} className="flex items-center gap-2 text-sm">
                    <Link2 className="w-3.5 h-3.5 text-muted-foreground flex-shrink-0" />
                    <span className="truncate flex-1 text-primary">{url}</span>
                    <button
                      type="button"
                      onClick={() => setAnexos((prev) => prev.filter((_, j) => j !== i))}
                      className="text-muted-foreground hover:text-destructive"
                    >
                      <X className="w-3.5 h-3.5" />
                    </button>
                  </div>
                ))}
              </div>
            )}
          </div>
        </div>

        <DialogFooter className="gap-2 pt-2">
          <Button variant="outline" onClick={handleClose} disabled={loading}>
            Cancelar
          </Button>
          <Button onClick={handleSubmit} disabled={loading} className="gap-2">
            {loading
              ? <><Loader2 className="w-4 h-4 animate-spin" /> Agendando...</>
              : "Agendar"
            }
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}
EOF
  echo "✅  components/agendar-modal.tsx"

  # ── Fix 2: disponibilidad-inline.tsx — toast fuera del dep array ─────────
  echo "📄  components/disponibilidad-inline.tsx..."
  cat > components/disponibilidad-inline.tsx << 'EOF'
"use client"

import { useState, useEffect, useCallback, useRef } from "react"
import { ocupacionesApi } from "@/lib/ocupacion-api"
import type { Ocupacion } from "@/types/ocupacion"
import { useToast } from "@/hooks/use-toast"
import { Button } from "@/components/ui/button"
import { Badge }  from "@/components/ui/badge"
import {
  Loader2,
  MapPin,
  Clock,
  Users,
  Unlock,
  RefreshCw,
  Inbox,
  Link2,
  ChevronDown,
  ChevronUp,
  CalendarDays,
} from "lucide-react"
import { cn } from "@/lib/utils"

interface DisponibilidadInlineProps {
  onSuccess?: () => void
}

function formatFecha(iso: string): string {
  const [y, m, d] = iso.split("T")[0].split("-").map(Number)
  return new Date(y, m - 1, d).toLocaleDateString("es-AR", {
    weekday: "short", day: "numeric", month: "short",
  })
}

function esHoy(iso: string): boolean {
  const hoy = new Date()
  const [y, m, d] = iso.split("T")[0].split("-").map(Number)
  const f = new Date(y, m - 1, d)
  return (
    f.getDate()     === hoy.getDate()  &&
    f.getMonth()    === hoy.getMonth() &&
    f.getFullYear() === hoy.getFullYear()
  )
}

export function DisponibilidadInline({ onSuccess }: DisponibilidadInlineProps) {
  const { toast } = useToast()
  // ✅ FIX: toast en ref → no entra en el dep array de useCallback → sin loops
  const toastRef = useRef(toast)
  useEffect(() => { toastRef.current = toast }, [toast])

  const [ocupaciones, setOcupaciones] = useState<Ocupacion[]>([])
  const [loading,     setLoading]     = useState(false)
  const [liberando,   setLiberando]   = useState<number | null>(null)
  const [expandedId,  setExpandedId]  = useState<number | null>(null)

  // ✅ FIX: dep array estable → useEffect se dispara solo al montar
  const cargar = useCallback(async (silencioso = false) => {
    if (!silencioso) setLoading(true)
    try {
      const data = await ocupacionesApi.getActivas()
      setOcupaciones(data)
    } catch {
      if (!silencioso) {
        toastRef.current({
          variant: "destructive",
          title: "Error",
          description: "No se pudieron cargar las ocupaciones",
        })
      }
    } finally {
      if (!silencioso) setLoading(false)
    }
  }, []) // ← sin dependencias externas inestables

  useEffect(() => { cargar() }, [cargar])

  const liberar = async (oc: Ocupacion) => {
    setLiberando(oc.id)
    try {
      await ocupacionesApi.liberar(oc.id)
      toastRef.current({ title: "✅ Zonas liberadas", description: `"${oc.titulo}" finalizada` })
      await cargar(true)
      onSuccess?.()
    } catch (err) {
      toastRef.current({
        variant: "destructive",
        title: "Error al liberar",
        description: err instanceof Error ? err.message : "Error desconocido",
      })
    } finally {
      setLiberando(null)
    }
  }

  const toggleExpand = (id: number) =>
    setExpandedId((prev) => (prev === id ? null : id))

  // ── UI ───────────────────────────────────────────────────────────────────
  return (
    <div className="space-y-3">
      {/* Header */}
      <div className="flex items-center justify-between">
        <h3 className="text-sm font-semibold flex items-center gap-1.5 text-muted-foreground uppercase tracking-wide">
          <MapPin className="w-3.5 h-3.5" />
          Zonas ocupadas
        </h3>
        <Button
          variant="ghost"
          size="sm"
          className="h-7 gap-1.5 text-xs"
          onClick={() => cargar()}
          disabled={loading}
        >
          <RefreshCw className={cn("w-3 h-3", loading && "animate-spin")} />
          Actualizar
        </Button>
      </div>

      {/* Contenido */}
      {loading ? (
        <div className="flex items-center justify-center py-10 gap-2 text-muted-foreground">
          <Loader2 className="w-4 h-4 animate-spin" />
          <span className="text-sm">Cargando...</span>
        </div>
      ) : ocupaciones.length === 0 ? (
        <div className="flex flex-col items-center justify-center py-10 gap-2 text-muted-foreground">
          <Inbox className="w-8 h-8 opacity-30" />
          <p className="text-sm font-medium">Sin zonas ocupadas</p>
          <p className="text-xs opacity-60">Todos los espacios están disponibles</p>
        </div>
      ) : (
        <div className="space-y-2">
          {ocupaciones.map((oc) => {
            const expanded = expandedId === oc.id
            const hoy      = esHoy(oc.fechaDesde)

            return (
              <div
                key={oc.id}
                className="rounded-xl border bg-card text-card-foreground shadow-sm overflow-hidden"
              >
                {/* Fila principal */}
                <button
                  type="button"
                  className="w-full text-left px-4 py-3 flex items-start justify-between gap-2 hover:bg-muted/30 transition-colors"
                  onClick={() => toggleExpand(oc.id)}
                >
                  <div className="flex-1 min-w-0 space-y-1">
                    <div className="flex items-center gap-2 flex-wrap">
                      <span className="font-semibold text-sm truncate">{oc.titulo}</span>
                      {hoy && (
                        <Badge variant="destructive" className="text-[10px] px-1.5 py-0">
                          Hoy
                        </Badge>
                      )}
                    </div>
                    <div className="flex items-center gap-3 flex-wrap text-xs text-muted-foreground">
                      <span className="flex items-center gap-1">
                        <CalendarDays className="w-3 h-3" />
                        {formatFecha(oc.fechaDesde)}
                        {oc.fechaDesde !== oc.fechaHasta && ` → ${formatFecha(oc.fechaHasta)}`}
                      </span>
                      <span className="flex items-center gap-1">
                        <Clock className="w-3 h-3" />
                        {oc.horaDesde} – {oc.horaHasta}
                      </span>
                      <span className="flex items-center gap-1">
                        <Users className="w-3 h-3" />
                        {oc.cantidadPersonas}
                      </span>
                    </div>
                  </div>
                  {expanded
                    ? <ChevronUp className="w-4 h-4 text-muted-foreground flex-shrink-0 mt-0.5" />
                    : <ChevronDown className="w-4 h-4 text-muted-foreground flex-shrink-0 mt-0.5" />
                  }
                </button>

                {/* Detalle expandido */}
                {expanded && (
                  <div className="px-4 pb-4 pt-0 space-y-3 border-t bg-muted/10">
                    {/* Áreas */}
                    <div className="space-y-1 pt-3">
                      <p className="text-xs text-muted-foreground flex items-center gap-1">
                        <MapPin className="w-3 h-3" /> Zonas:
                      </p>
                      <div className="flex flex-wrap gap-1.5">
                        {oc.areas?.length > 0
                          ? oc.areas.map((r) => (
                              <Badge key={r.areaId} variant="secondary" className="text-xs">
                                {r.area?.nombre ?? `Área ${r.areaId}`}
                              </Badge>
                            ))
                          : <span className="text-xs text-muted-foreground">Sin zonas</span>
                        }
                      </div>
                    </div>

                    {/* Requerimiento */}
                    {oc.requerimiento && (
                      <p className="text-xs text-muted-foreground border-t pt-2">
                        {oc.requerimiento}
                      </p>
                    )}

                    {/* Anexos */}
                    {oc.anexos?.length > 0 && (
                      <div className="space-y-1">
                        <p className="text-xs text-muted-foreground flex items-center gap-1">
                          <Link2 className="w-3 h-3" /> Anexos:
                        </p>
                        {oc.anexos.map((url, i) => (
                          <a
                            key={i}
                            href={url}
                            target="_blank"
                            rel="noopener noreferrer"
                            className="text-xs text-primary underline truncate block"
                          >
                            {url}
                          </a>
                        ))}
                      </div>
                    )}

                    {/* Acción liberar */}
                    <div className="pt-1">
                      <Button
                        size="sm"
                        variant="outline"
                        className="gap-1.5 text-xs border-destructive/30 text-destructive hover:bg-destructive hover:text-white"
                        onClick={() => liberar(oc)}
                        disabled={liberando === oc.id}
                      >
                        {liberando === oc.id
                          ? <><Loader2 className="w-3 h-3 animate-spin" /> Liberando...</>
                          : <><Unlock className="w-3 h-3" /> Liberar áreas</>
                        }
                      </Button>
                    </div>
                  </div>
                )}
              </div>
            )
          })}
        </div>
      )}
    </div>
  )
}
EOF
  echo "✅  components/disponibilidad-inline.tsx"

  echo ""
  echo "🔨  Compilando frontend..."
  pnpm build

  echo ""
  echo "╔══════════════════════════════════════════════════════════════════╗"
  echo "║  ✅  FRONTEND completado                                         ║"
  echo "╚══════════════════════════════════════════════════════════════════╝"
  echo ""
  echo "  Fixes aplicados:"
  echo "    · agendar-modal.tsx    → onSuccess() se llama tras crear"
  echo "    · disponibilidad-inline → toast en useRef (dep array estable)"
  echo "    · disponibilidad-inline → cargar() sin deps externas inestables"
  echo ""
  echo "  ⚠️  No requiere prisma migrate (sin cambios de schema)"
  echo ""
fi