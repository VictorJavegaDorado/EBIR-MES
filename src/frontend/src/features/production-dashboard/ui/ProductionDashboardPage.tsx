import { useEffect, useMemo, useRef, useState } from "react";
import {
  getProductionDashboard,
  type ProductionDashboardLine,
  type ProductionDashboardSnapshot,
} from "../api/productionDashboard";

const refreshMilliseconds = 5_000;

const numberFormatter = new Intl.NumberFormat("es-ES", { maximumFractionDigits: 0 });
const timeFormatter = new Intl.DateTimeFormat("es-ES", {
  hour: "2-digit",
  minute: "2-digit",
  second: "2-digit",
});

function formatDuration(totalSeconds: number) {
  const seconds = Math.max(0, Math.floor(totalSeconds));
  const hours = Math.floor(seconds / 3600);
  const minutes = Math.floor((seconds % 3600) / 60);
  return `${String(hours).padStart(2, "0")}:${String(minutes).padStart(2, "0")}`;
}

function displayState(state: string) {
  return state.replaceAll("_", " ");
}

function isProducing(line: ProductionDashboardLine) {
  return line.table?.state === "PRODUCIENDO" && line.table.activeResources > 0;
}

function needsAttention(line: ProductionDashboardLine) {
  return line.operationalState === "BLOQUEADA" || line.navIssues > 0 || line.printIssues > 0;
}

function statusTone(line: ProductionDashboardLine) {
  if (needsAttention(line)) return "danger";
  if (isProducing(line)) return "running";
  if (line.order) return "waiting";
  return "idle";
}

function integrationLabel(state: string | null, kind: "nav" | "label") {
  if (!state) return "Sin actividad";
  if (state === "CONFIRMADA" || state === "IMPRESA" || state === "COMPLETADO") {
    return kind === "nav" ? "Registrado" : "Impresa";
  }
  if (state === "RESULTADO_DESCONOCIDO") return "Reconciliando";
  if (state === "PENDIENTE_NAV") return "Esperando NAV";
  if (state === "LISTA") return "Lista para imprimir";
  return displayState(state);
}

export function ProductionDashboardPage() {
  const [snapshot, setSnapshot] = useState<ProductionDashboardSnapshot | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [receivedAt, setReceivedAt] = useState(0);
  const [tick, setTick] = useState(0);
  const request = useRef<AbortController | null>(null);

  useEffect(() => {
    let mounted = true;
    async function refresh() {
      request.current?.abort();
      const controller = new AbortController();
      request.current = controller;
      try {
        const next = await getProductionDashboard(controller.signal);
        if (!mounted) return;
        setSnapshot(next);
        setReceivedAt(performance.now());
        setError(null);
      } catch (caught) {
        if (!mounted || controller.signal.aborted) return;
        setError(caught instanceof Error ? caught.message : "No se puede actualizar el panel.");
      }
    }
    void refresh();
    const refreshTimer = window.setInterval(() => void refresh(), refreshMilliseconds);
    const clockTimer = window.setInterval(() => setTick(value => value + 1), 1_000);
    return () => {
      mounted = false;
      request.current?.abort();
      window.clearInterval(refreshTimer);
      window.clearInterval(clockTimer);
    };
  }, []);

  const elapsedSeconds = receivedAt === 0 ? 0 : Math.max(0, (performance.now() - receivedAt) / 1000);
  const summary = useMemo(() => {
    const lines = snapshot?.lines ?? [];
    return {
      total: lines.length,
      running: lines.filter(isProducing).length,
      waiting: lines.filter(line => line.order && !isProducing(line) && !needsAttention(line)).length,
      attention: lines.filter(needsAttention).length,
    };
  }, [snapshot, tick]);

  return (
    <section className="production-dashboard">
      <header className="dashboard-heading">
        <div>
          <p className="eyebrow">Control de fabricacion</p>
          <h1>Fabricacion en tiempo real</h1>
          <p>Estado, avance y equipo activo de todas las lineas.</p>
        </div>
        <div className="dashboard-heading-actions">
          <a href="/">Ir al terminal</a>
          <div className={`dashboard-live ${error ? "stale" : ""}`}>
            <span />
            <div>
              <strong>{error ? "Sin conexion" : "En directo"}</strong>
              <small>
                {snapshot
                  ? `Actualizado ${timeFormatter.format(new Date(snapshot.serverTimeUtc))}`
                  : "Conectando..."}
              </small>
            </div>
          </div>
        </div>
      </header>

      {error && (
        <div className="dashboard-alert" role="alert">
          <strong>No se ha podido refrescar.</strong> Se conserva la ultima lectura. {error}
        </div>
      )}

      <div className="dashboard-summary" aria-label="Resumen de lineas">
        <article><span>Total</span><strong>{summary.total}</strong><small>lineas activas</small></article>
        <article className="running"><span>Produciendo</span><strong>{summary.running}</strong><small>con capacidad activa</small></article>
        <article className="waiting"><span>En espera</span><strong>{summary.waiting}</strong><small>con orden cargada</small></article>
        <article className="danger"><span>Atencion</span><strong>{summary.attention}</strong><small>bloqueos o incidencias</small></article>
      </div>

      {!snapshot && !error && <div className="dashboard-loading">Cargando lineas de fabricacion...</div>}

      <div className="dashboard-lines">
        {snapshot?.lines.map(line => (
          <LineCard key={line.lineId} line={line} elapsedSeconds={elapsedSeconds} />
        ))}
      </div>
    </section>
  );
}

function LineCard({ line, elapsedSeconds }: { line: ProductionDashboardLine; elapsedSeconds: number }) {
  const order = line.order;
  const table = line.table;
  const progress = order && order.targetQuantity > 0
    ? Math.min(100, Math.max(0, (order.goodQuantity / order.targetQuantity) * 100))
    : 0;
  const projectedTotal = (table?.productiveSeconds ?? 0) + (isProducing(line) ? elapsedSeconds : 0);
  const navPending = line.pendingNavOutputs > 0;
  const printPending = line.pendingPrintJobs > 0;

  return (
    <article className={`dashboard-line-card ${statusTone(line)}`}>
      <header>
        <div>
          <span>{line.workCenterCode}</span>
          <h2>{line.lineCode}</h2>
          <p>{line.lineName}</p>
        </div>
        <strong className="dashboard-state">{displayState(table?.state ?? line.operationalState)}</strong>
      </header>

      {!order || !table ? (
        <div className="dashboard-empty-line">
          <strong>Linea disponible</strong>
          <span>Sin orden activa</span>
        </div>
      ) : (
        <>
          <div className="dashboard-order">
            <div>
              <span>Orden activa</span>
              <strong>{order.orderNumber}</strong>
              <small>{order.productNumber} · {order.lotNumber || "Sin lote"}</small>
            </div>
            <p>{order.productDescription}</p>
          </div>

          <div className="dashboard-progress-copy">
            <span>Avance</span>
            <strong>{numberFormatter.format(order.goodQuantity)} / {numberFormatter.format(order.targetQuantity)} uds</strong>
          </div>
          <div className="dashboard-progress" role="progressbar" aria-valuemin={0} aria-valuemax={100} aria-valuenow={Math.round(progress)}>
            <span style={{ width: `${progress}%` }} />
          </div>
          <div className="dashboard-progress-meta">
            <span>{progress.toFixed(0)}% completado</span>
            <span>{order.reservedQuantity} uds en palet actual</span>
          </div>

          <dl className="dashboard-kpis">
            <div><dt>Tiempo productivo</dt><dd>{formatDuration(projectedTotal)}</dd></div>
            <div><dt>Capacidad</dt><dd>{table.activeResources} personas</dd></div>
            <div><dt>Ritmo teorico</dt><dd>{numberFormatter.format(table.currentTheoreticalCapacityPerHour)} uds/h</dd></div>
            <div><dt>Palets cerrados</dt><dd>{line.closedPallets}</dd></div>
          </dl>

          <div className="dashboard-operators">
            <div className="dashboard-section-title"><span>Equipo activo</span><strong>{table.operators.length}</strong></div>
            {table.operators.length === 0 ? (
              <p>Sin operarios fichados.</p>
            ) : table.operators.map(operator => {
              const seconds = operator.productiveSeconds +
                (operator.status === "PRODUCIENDO" && isProducing(line) ? elapsedSeconds : 0);
              return (
                <div className="dashboard-operator" key={operator.employeeId}>
                  <span aria-hidden="true">{operator.fullName.split(/\s+/).slice(0, 2).map(part => part[0]).join("")}</span>
                  <div><strong>{operator.fullName}</strong><small>{displayState(operator.status)}</small></div>
                  <time>{formatDuration(seconds)}</time>
                </div>
              );
            })}
          </div>

          <div className="dashboard-integrations">
            <div className={line.navIssues ? "danger" : navPending ? "pending" : "ok"}>
              <span>NAV</span><strong>{integrationLabel(line.latestNavState, "nav")}</strong>
            </div>
            <div className={line.printIssues ? "danger" : printPending ? "pending" : "ok"}>
              <span>Etiqueta</span><strong>{integrationLabel(line.latestLabelState, "label")}</strong>
            </div>
            <div><span>Formato</span><strong>{table.palletFormatCode} · {table.unitsPerPallet} uds</strong></div>
          </div>
        </>
      )}

      {line.blockReason && <p className="dashboard-block-reason">{line.blockReason}</p>}
    </article>
  );
}
