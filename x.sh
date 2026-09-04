#!/usr/bin/env bash
# ============================================================================
#  v17-fix-too-many-connections.sh
#
#  Problema: P2037 "Too many connections" en PostgreSQL.
#  Causas combinadas:
#    BACK: pg.Pool sin max configurado → abre hasta el límite de PG (100)
#          El cron cada minuto + requests concurrentes saturan la DB.
#    FRONT: fetchSeats disparado en loop por useCallback sin deps estables
#           → polling descontrolado con decenas de requests/segundo.
#
#  Fixes BACKEND (coworking-back):
#    · prisma/prisma.service.ts → pg.Pool con max:10, idleTimeoutMillis,
#      connectionTimeoutMillis
#    · src/ocupacion/ocupacion.service.ts → cron cada 5 min en vez de 1 min
#
#  Fixes FRONTEND (coworking-front):
#    · hooks/use-seats.ts → fetchSeats con useCallback sin deps + polling
#      cada 30s en vez de en cada render
#    · app/page.tsx → useEffect con [] para fetchSeats inicial (sin deps)
#
#  El script detecta en qué repo estás y aplica solo lo que corresponde.
#
#  Uso:
#    cd coworking-back  → chmod +x v17... && ./v17...
#    cd coworking-front → chmod +x v17... && ./v17...
# ============================================================================
set -euo pipefail

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

echo ""
echo "╔══════════════════════════════════════════════════════════════════╗"
echo "║  🔧  v17 — Fix Too Many Connections                             ║"
echo "╚══════════════════════════════════════════════════════════════════╝"

# ════════════════════════════════════════════════════════════════════════════
# BACKEND
# ════════════════════════════════════════════════════════════════════════════
if [ "$IS_BACK" = true ]; then
  echo ""
  echo "── BACKEND ──────────────────────────────────────────────────────────"

  # ── prisma/prisma.service.ts — pool limitado ────────────────────────────
  echo "📄  prisma/prisma.service.ts..."
  cat > prisma/prisma.service.ts << 'EOF'
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
EOF
  echo "✅  prisma/prisma.service.ts — pool max=10"

  # ── src/ocupacion/ocupacion.service.ts — cron cada 5 min ───────────────
  echo "📄  src/ocupacion/ocupacion.service.ts — cron cada 5 min..."
  # Reemplazar @Cron('* * * * *') por @Cron('*/5 * * * *')
  sed -i "s|@Cron('\\* \\* \\* \\* \\*')|@Cron('*/5 * * * *')|g" src/ocupacion/ocupacion.service.ts
  echo "✅  Cron: cada minuto → cada 5 minutos"

  echo ""
  echo "🔨  Compilando backend..."
  pnpm build

  echo ""
  echo "╔══════════════════════════════════════════════════════════════════╗"
  echo "║  ✅  BACKEND completado                                          ║"
  echo "╚══════════════════════════════════════════════════════════════════╝"
  echo ""
  echo "  Cambios:"
  echo "    · prisma.service.ts → pg.Pool max=10, idle=30s, timeout=5s"
  echo "    · ocupacion.service.ts → cron cada 5 min (era cada 1 min)"
  echo ""
  echo "  Sin cambios de schema."
  echo ""
fi

# ════════════════════════════════════════════════════════════════════════════
# FRONTEND
# ════════════════════════════════════════════════════════════════════════════
if [ "$IS_FRONT" = true ]; then
  echo ""
  echo "── FRONTEND ─────────────────────────────────────────────────────────"

  # ── hooks/use-seats.ts — fetchSeats estable + polling controlado ────────
  echo "📄  hooks/use-seats.ts..."
  cat > hooks/use-seats.ts << 'EOF'
"use client"

import { useState, useCallback, useRef, useEffect } from "react"
import { areasApi, reservasApi, convertBackendAreaToSeat } from "@/lib/api"
import type { Seat } from "@/types/seat"
import { useToast } from "@/hooks/use-toast"

// Polling cada 30s — suficiente para datos en tiempo real sin saturar la DB
const POLLING_MS = 30_000

export function useSeats() {
  const { toast }    = useToast()
  const toastRef     = useRef(toast)
  useEffect(() => { toastRef.current = toast }, [toast])

  const [seats,   setSeats]   = useState<Seat[]>([])
  const [loading, setLoading] = useState(false)
  const [error,   setError]   = useState<string | null>(null)

  // ── fetchSeats: estable, no se recrea entre renders ──────────────────────
  const fetchSeats = useCallback(async () => {
    try {
      setLoading(true)
      setError(null)
      const [areas, reservas] = await Promise.all([
        areasApi.getAll(),
        reservasApi.getAll(),
      ])
      setSeats(areas.map((area) => convertBackendAreaToSeat(area, reservas)))
    } catch (err) {
      const msg = err instanceof Error ? err.message : "Error al cargar áreas"
      setError(msg)
    } finally {
      setLoading(false)
    }
  }, []) // sin deps → referencia estable entre renders

  // ── updateSeatStatus ─────────────────────────────────────────────────────
  const updateSeatStatus = useCallback(async (
    seat: Seat,
    newStatus: string,
    userName?: string,
    peopleCount?: number,
    shareLimit?: number,
  ) => {
    if (!seat.backendId) throw new Error("Asiento sin ID de backend")

    try {
      if (newStatus === "occupied" || newStatus === "for-share" || newStatus === "shared") {
        if (!userName) throw new Error("Nombre de usuario requerido")

        // Buscar usuario por nombre
        const user = await (async () => {
          try {
            const res = await fetch(
              `${process.env.NEXT_PUBLIC_API_URL ?? ""}/usuario`,
              { headers: { "Content-Type": "application/json" } }
            )
            if (!res.ok) return null
            const usuarios = await res.json()
            return usuarios.find((u: { nombre: string; id: number }) => u.nombre === userName) ?? null
          } catch { return null }
        })()

        const usuarioId = user?.id ?? 1
        const detalles  =
          newStatus === "for-share"
            ? `Para compartir (límite: ${shareLimit || 6}, personas: ${peopleCount})`
            : `Ocupado por ${peopleCount} persona(s)`

        await reservasApi.create({ nombre: userName, detalles, usuarioId, areaId: seat.backendId })

        if (newStatus === "for-share") {
          const reservas    = await reservasApi.getAll()
          const activeCount = reservas.filter((r) => r.areaId === seat.backendId && r.fin === null).length
          await areasApi.cambiarEstado(seat.backendId, activeCount >= (shareLimit || 6) ? "shared" : newStatus)
        } else {
          await areasApi.cambiarEstado(seat.backendId, newStatus)
        }

        toastRef.current({ title: "Reserva creada", description: `${seat.id} asignado a ${userName}` })
      } else {
        await areasApi.cambiarEstado(seat.backendId, newStatus)
        toastRef.current({ title: "Estado actualizado", description: `${seat.id} cambió de estado` })
      }

      await fetchSeats()
    } catch (err) {
      const msg = err instanceof Error ? err.message : "Error al actualizar"
      setError(msg)
      toastRef.current({ variant: "destructive", title: "Error al actualizar asiento", description: msg })
      throw err
    }
  }, [fetchSeats])

  // ── toggleBlockAll ───────────────────────────────────────────────────────
  const toggleBlockAll = useCallback(async (block: boolean) => {
    try {
      setLoading(true)
      await areasApi.bloquearTodas(block)
      toastRef.current({
        title:       block ? "Coworking bloqueado" : "Coworking desbloqueado",
        description: block ? "Todas las áreas están bloqueadas" : "Las áreas volvieron a su estado libre",
      })
      await fetchSeats()
    } catch (err) {
      const msg = err instanceof Error ? err.message : "Error al operar"
      setError(msg)
      toastRef.current({ variant: "destructive", title: "Error", description: msg })
    } finally {
      setLoading(false)
    }
  }, [fetchSeats])

  return { seats, loading, error, fetchSeats, updateSeatStatus, toggleBlockAll, POLLING_MS }
}
EOF
  echo "✅  hooks/use-seats.ts"

  # ── app/page.tsx — polling controlado, useEffect sin deps ───────────────
  echo "📄  app/page.tsx — polling controlado..."
  cat > app/page.tsx << 'EOF'
"use client"

import { useState, useEffect, useRef } from "react"
import { useRouter }            from "next/navigation"
import { useAuth }              from "@/contexts/auth-context"
import { useSeats }             from "@/hooks/use-seats"
import { useEventoActivo }      from "@/hooks/use-evento-activo"
import { SeatGrid }             from "@/components/seat-grid"
import { SeatLegend }           from "@/components/seat-legend"
import { AdminPanel }           from "@/components/admin-panel"
import { AgendarModal }         from "@/components/agendar-modal"
import { MapaModal }            from "@/components/mapa-modal"
import { DisponibilidadInline } from "@/components/disponibilidad-inline"
import { CalendarioCoworking }  from "@/components/calendario-coworking"
import { EventoActivoBanner }   from "@/components/evento-activo-banner"
import { Button }               from "@/components/ui/button"
import { Switch }               from "@/components/ui/switch"
import { Label }                from "@/components/ui/label"
import { cn }                   from "@/lib/utils"
import { useToast }             from "@/hooks/use-toast"
import {
  Loader2, RefreshCw, LogOut, Menu,
  Armchair, CalendarPlus, CalendarRange, MapPin, Map, LayoutGrid,
} from "lucide-react"
import { Sheet, SheetContent, SheetTrigger } from "@/components/ui/sheet"

type Vista = "disponibilidad" | "asientos" | "mapa" | "agendar" | "calendario"

const VISTAS: { id: Vista; label: string; icon: React.ElementType }[] = [
  { id: "disponibilidad", label: "Disponibilidad", icon: MapPin        },
  { id: "asientos",       label: "Asientos",       icon: LayoutGrid    },
  { id: "mapa",           label: "Mapa",           icon: Map           },
  { id: "agendar",        label: "Agendar",        icon: CalendarPlus  },
  { id: "calendario",     label: "Calendario",     icon: CalendarRange },
]

// Polling cada 30s — evita saturar la DB
const POLLING_MS = 30_000

export default function CoworkingSeatsPage() {
  const router  = useRouter()
  const { admin, isAdmin, logout, loading: authLoading } = useAuth()
  const { seats, loading, fetchSeats, toggleBlockAll }   = useSeats()
  const { eventoActivo }      = useEventoActivo()
  const { toast }             = useToast()

  const [isAdminMode,    setIsAdminMode]    = useState(false)
  const [mobileMenuOpen, setMobileMenuOpen] = useState(false)
  const [vista,          setVista]          = useState<Vista>("asientos")
  const [mapaOpen,       setMapaOpen]       = useState(false)
  const [agendarOpen,    setAgendarOpen]    = useState(false)

  const bloqueadoPorEventoRef = useRef<string | null>(null)

  // ── Auth guard ────────────────────────────────────────────────────────────
  useEffect(() => {
    if (!authLoading && !admin) router.push("/login")
  }, [admin, authLoading, router])

  // ── Carga inicial UNA sola vez ────────────────────────────────────────────
  useEffect(() => {
    fetchSeats()
    // fetchSeats es estable (useCallback con []) → este effect solo corre al montar
  }, [fetchSeats])

  // ── Polling cada 30s — controlado ────────────────────────────────────────
  useEffect(() => {
    const id = setInterval(fetchSeats, POLLING_MS)
    return () => clearInterval(id)
  }, [fetchSeats]) // fetchSeats es estable → el interval se crea una sola vez

  // ── Auto-bloqueo por evento del calendario ────────────────────────────────
  useEffect(() => {
    const eventoId = eventoActivo?.id ?? null
    if (eventoId === bloqueadoPorEventoRef.current) return

    if (eventoId !== null && bloqueadoPorEventoRef.current === null) {
      bloqueadoPorEventoRef.current = eventoId
      toggleBlockAll(true).catch(() => {})
    } else if (eventoId === null && bloqueadoPorEventoRef.current !== null) {
      bloqueadoPorEventoRef.current = null
      toggleBlockAll(false).catch(() => {})
    } else if (eventoId !== null && eventoId !== bloqueadoPorEventoRef.current) {
      bloqueadoPorEventoRef.current = eventoId
    }
  }, [eventoActivo, toggleBlockAll])

  // ── Handlers ──────────────────────────────────────────────────────────────
  const handleRefresh = async () => {
    await fetchSeats()
    toast({ title: "Datos actualizados" })
  }

  const handleVista = (v: Vista) => {
    if (v === "mapa")    { setMapaOpen(true);   return }
    if (v === "agendar") { setAgendarOpen(true); return }
    setVista(v)
  }

  const bloqueadoPorEvento = eventoActivo !== null
  const bloqueadoManual    = !bloqueadoPorEvento && seats.length > 0 && seats.every((s) => s.status === "occupied")
  const isBlocked          = bloqueadoPorEvento || bloqueadoManual
  const occupiedCount      = seats.filter((s) => s.status === "occupied").length
  const availableCount     = seats.filter((s) => s.status === "available").length

  if (authLoading) {
    return (
      <div className="min-h-screen flex items-center justify-center">
        <Loader2 className="w-8 h-8 animate-spin text-primary" />
      </div>
    )
  }
  if (!admin) return null

  if (loading && seats.length === 0) {
    return (
      <div className="min-h-screen flex items-center justify-center px-4">
        <div className="text-center space-y-3">
          <Loader2 className="w-8 h-8 animate-spin mx-auto text-primary" />
          <p className="text-muted-foreground text-sm">Cargando áreas...</p>
        </div>
      </div>
    )
  }

  return (
    <div className="min-h-screen bg-gradient-to-b from-background to-secondary">

      {/* ══ Header ══════════════════════════════════════════════════ */}
      <div className="sticky top-0 z-40 bg-white/80 backdrop-blur-md border-b border-border/50 shadow-sm">
        <div className="max-w-2xl mx-auto px-4 py-3">

          <div className="hidden md:flex items-center justify-between">
            <div className="flex items-center gap-3">
              <div className="w-9 h-9 bg-blue-50 rounded-xl flex items-center justify-center">
                <Armchair className="w-5 h-5 text-primary" />
              </div>
              <div>
                <h1 className="text-base font-bold leading-tight">Coworking</h1>
                <p className="text-xs text-muted-foreground">{admin.email}</p>
              </div>
            </div>
            <div className="flex items-center gap-3">
              <Button variant="ghost" size="icon" onClick={handleRefresh} disabled={loading} className="h-8 w-8">
                <RefreshCw className={`w-4 h-4 ${loading ? "animate-spin" : ""}`} />
              </Button>
              {isAdmin && (
                <div className="flex items-center gap-2">
                  <Switch id="admin-mode" checked={isAdminMode} onCheckedChange={setIsAdminMode} />
                  <Label htmlFor="admin-mode" className="text-sm cursor-pointer">Admin</Label>
                </div>
              )}
              <Button variant="ghost" size="icon" onClick={logout} className="h-8 w-8 text-muted-foreground">
                <LogOut className="w-4 h-4" />
              </Button>
            </div>
          </div>

          <div className="flex md:hidden items-center justify-between">
            <div className="flex items-center gap-2">
              <div className="w-8 h-8 bg-blue-50 rounded-lg flex items-center justify-center">
                <Armchair className="w-4 h-4 text-primary" />
              </div>
              <span className="font-bold text-sm">Coworking</span>
            </div>
            <div className="flex items-center gap-1">
              <Button variant="ghost" size="icon" onClick={handleRefresh} disabled={loading} className="h-8 w-8">
                <RefreshCw className={`w-4 h-4 ${loading ? "animate-spin" : ""}`} />
              </Button>
              <Sheet open={mobileMenuOpen} onOpenChange={setMobileMenuOpen}>
                <SheetTrigger asChild>
                  <Button variant="ghost" size="icon" className="h-8 w-8">
                    <Menu className="w-4 h-4" />
                  </Button>
                </SheetTrigger>
                <SheetContent side="right" className="w-72">
                  <div className="space-y-3 pt-4">
                    <div className="pb-3 border-b">
                      <p className="font-semibold">{admin.nombre}</p>
                      <p className="text-xs text-muted-foreground">{admin.email}</p>
                    </div>
                    <Button variant="outline" className="w-full justify-start gap-2"
                      onClick={() => { handleRefresh(); setMobileMenuOpen(false) }}>
                      <RefreshCw className="w-4 h-4" /> Actualizar
                    </Button>
                    {isAdmin && (
                      <div className="flex items-center gap-2 py-1">
                        <Switch id="admin-mode-mobile" checked={isAdminMode} onCheckedChange={setIsAdminMode} />
                        <Label htmlFor="admin-mode-mobile" className="cursor-pointer">Modo Admin</Label>
                      </div>
                    )}
                    <Button variant="outline"
                      className="w-full justify-start gap-2 text-destructive hover:text-destructive"
                      onClick={logout}>
                      <LogOut className="w-4 h-4" /> Cerrar sesión
                    </Button>
                  </div>
                </SheetContent>
              </Sheet>
            </div>
          </div>

        </div>
      </div>

      {/* ══ Contenido ════════════════════════════════════════════════ */}
      <div className="max-w-2xl mx-auto px-4 py-6 space-y-4 pb-24">

        {eventoActivo && <EventoActivoBanner evento={eventoActivo} />}

        <div className="grid grid-cols-3 gap-3">
          <div className="bg-white rounded-xl border border-border p-3 md:p-4 text-center shadow-sm">
            <p className="text-xl md:text-2xl font-bold text-foreground">{seats.length}</p>
            <p className="text-[10px] md:text-xs text-muted-foreground mt-0.5">Total</p>
          </div>
          <div className="bg-white rounded-xl border border-green-100 p-3 md:p-4 text-center shadow-sm">
            <p className="text-xl md:text-2xl font-bold text-green-500">{availableCount}</p>
            <p className="text-[10px] md:text-xs text-muted-foreground mt-0.5">Libres</p>
          </div>
          <div className="bg-white rounded-xl border border-red-100 p-3 md:p-4 text-center shadow-sm">
            <p className="text-xl md:text-2xl font-bold text-red-500">{occupiedCount}</p>
            <p className="text-[10px] md:text-xs text-muted-foreground mt-0.5">Ocupados</p>
          </div>
        </div>

        {isAdminMode && isAdmin && !bloqueadoPorEvento && (
          <AdminPanel isBlocked={bloqueadoManual} onToggleBlock={toggleBlockAll} />
        )}

        {isAdminMode && isAdmin && bloqueadoPorEvento && (
          <div className="rounded-xl border border-orange-200 bg-orange-50 px-4 py-3 text-xs text-orange-700">
            El panel de administración está deshabilitado mientras haya un evento activo.
            Las áreas se liberarán automáticamente cuando el evento termine.
          </div>
        )}

        <div className="bg-white rounded-xl border border-primary/10 shadow-sm overflow-hidden">
          <div className="border-b border-border px-4 pt-4 pb-0">
            <div className="flex gap-1 overflow-x-auto scrollbar-none">
              {VISTAS.map(({ id, label, icon: Icon }) => {
                const isModal  = id === "mapa" || id === "agendar"
                const isActive = !isModal && vista === id
                return (
                  <button key={id} onClick={() => handleVista(id)}
                    className={cn(
                      "flex items-center gap-1.5 px-3 py-2.5 text-sm font-medium rounded-t-lg border-b-2 transition-colors whitespace-nowrap flex-shrink-0",
                      isActive
                        ? "border-primary text-primary bg-primary/5"
                        : "border-transparent text-muted-foreground hover:text-foreground hover:bg-muted/40",
                      id === "agendar" && !isActive ? "hover:text-primary" : "",
                    )}>
                    <Icon className="w-4 h-4" />
                    <span>{label}</span>
                  </button>
                )
              })}
            </div>
          </div>

          <div className="p-4 md:p-6">
            {vista === "disponibilidad" && <DisponibilidadInline onSuccess={fetchSeats} />}
            {vista === "asientos" && (
              <div className="space-y-4">
                <div className="flex items-center justify-between">
                  <SeatLegend />
                  {isBlocked && (
                    <span className="text-xs text-destructive font-medium">
                      {bloqueadoPorEvento ? `Evento: ${eventoActivo?.titulo}` : "Bloqueado"}
                    </span>
                  )}
                </div>
                <div className="overflow-x-auto">
                  <SeatGrid seats={seats} isBlocked={isBlocked && !isAdminMode} />
                </div>
              </div>
            )}
            {vista === "calendario" && <CalendarioCoworking />}
          </div>
        </div>

      </div>

      <MapaModal    open={mapaOpen}    onOpenChange={setMapaOpen} />
      <AgendarModal open={agendarOpen} onOpenChange={setAgendarOpen} onSuccess={fetchSeats} />

    </div>
  )
}
EOF
  echo "✅  app/page.tsx"

  echo ""
  echo "🔨  Compilando frontend..."
  pnpm build

  echo ""
  echo "╔══════════════════════════════════════════════════════════════════╗"
  echo "║  ✅  FRONTEND completado                                         ║"
  echo "╚══════════════════════════════════════════════════════════════════╝"
  echo ""
  echo "  Cambios:"
  echo "    · hooks/use-seats.ts → fetchSeats useCallback([]) estable"
  echo "                           polling SOLO en app/page.tsx cada 30s"
  echo "    · app/page.tsx       → polling setInterval 30s, un solo"
  echo "                           useEffect de carga inicial"
  echo ""
fi