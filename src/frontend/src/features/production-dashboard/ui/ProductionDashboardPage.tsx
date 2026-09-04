import { useEffect, useMemo, useRef, useState, type CSSProperties } from "react";
import {
  getProductionDashboard,
  type ProductionDashboardLine,
  type ProductionDashboardSnapshot,
} from "../api/productionDashboard";

const refreshMilliseconds = 5_000;
const numberFormatter = new Intl.NumberFormat("es-ES", { maximumFractionDigits: 1 });
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

function performanceTone(performance: number | null) {
  if (performance === null) return "neutral";
  if (performance >= 95) return "good";
  if (performance >= 80) return "watch";
  return "low";
}

function signedUnits(value: number) {
  const rounded = Math.round(value * 10) / 10;
  return `${rounded >= 0 ? "+" : ""}${numberFormatter.format(rounded)} uds`;
}

function initials(fullName: string) {
  return fullName.split(/\s+/).filter(Boolean).slice(0, 2)
    .map(part => part[0]).join("").toLocaleUpperCase("es-ES");
}

function seatStyle(index: number, total: number): CSSProperties {
  const angle = -Math.PI / 2 + (index * Math.PI * 2) / Math.max(total, 1);
  return {
    "--seat-x": `${50 + Math.cos(angle) * 43}%`,
    "--seat-y": `${50 + Math.sin(angle) * 39}%`,
  } as CSSProperties;
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
          <p className="eyebrow">Control de fabricación</p>
          <h1>Planta en tiempo real</h1>
          <p>Mesas, personas y rendimiento frente a la ruta NAV.</p>
        </div>
        <div className="dashboard-heading-actions">
          <a href="/">Ir al terminal</a>
          <div className={`dashboard-live ${error ? "stale" : ""}`}>
            <span />
            <div>
              <strong>{error ? "Sin conexión" : "En directo"}</strong>
              <small>{snapshot ? `Actualizado ${timeFormatter.format(new Date(snapshot.serverTimeUtc))}` : "Conectando..."}</small>
            </div>
          </div>
        </div>
      </header>

      {error && (
        <div className="dashboard-alert" role="alert">
          <strong>No se ha podido refrescar.</strong> Se conserva la última lectura. {error}
        </div>
      )}

      <div className="dashboard-summary" aria-label="Resumen de líneas">
        <article><span>Total</span><strong>{summary.total}</strong><small>líneas activas</small></article>
        <article className="running"><span>Produciendo</span><strong>{summary.running}</strong><small>con capacidad activa</small></article>
        <article className="waiting"><span>En espera</span><strong>{summary.waiting}</strong><small>con orden cargada</small></article>
        <article className="danger"><span>Atención</span><strong>{summary.attention}</strong><small>bloqueos o incidencias</small></article>
      </div>

      {!snapshot && !error && <div className="dashboard-loading">Cargando líneas de fabricación...</div>}
      <div className="dashboard-lines">
        {snapshot?.lines.map(line => (
          <LineCard key={line.lineId} line={line} elapsedSeconds={elapsedSeconds} snapshotTimeUtc={snapshot.serverTimeUtc} />
        ))}
      </div>
    </section>
  );
}

function LineCard({ line, elapsedSeconds, snapshotTimeUtc }: {
  line: ProductionDashboardLine;
  elapsedSeconds: number;
  snapshotTimeUtc: string;
}) {
  const order = line.order;
  const table = line.table;
  const progress = order && order.targetQuantity > 0
    ? Math.min(100, Math.max(0, (order.goodQuantity / order.targetQuantity) * 100))
    : 0;
  const projectedTotal = (table?.productiveSeconds ?? 0) + (isProducing(line) ? elapsedSeconds : 0);
  const openedSeconds = table?.startedAtUtc
    ? Math.max(0, (new Date(snapshotTimeUtc).getTime() - new Date(table.startedAtUtc).getTime()) / 1000 + elapsedSeconds)
    : 0;
  const theoreticalUnits = line.theoreticalUnitsToDate +
    (isProducing(line) ? (table?.currentTheoreticalCapacityPerHour ?? 0) * elapsedSeconds / 3600 : 0);
  const performance = order && theoreticalUnits > 0 ? order.goodQuantity / theoreticalUnits * 100 : null;
  const performanceDisplay = performance === null ? "—" : `${Math.round(performance)}%`;
  const performanceArc = Math.min(100, Math.max(0, performance ?? 0));
  const theoreticalTotalSeconds = order && table && table.currentTheoreticalCapacityPerHour > 0
    ? order.targetQuantity / table.currentTheoreticalCapacityPerHour * 3600 : null;
  const estimatedRemainingSeconds = order && table && table.currentTheoreticalCapacityPerHour > 0
    ? Math.max(0, order.targetQuantity - order.goodQuantity) / table.currentTheoreticalCapacityPerHour * 3600 : null;
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
        <strong className="dashboard-state"><i aria-hidden="true" />{displayState(table?.state ?? line.operationalState)}</strong>
      </header>

      {!order || !table ? (
        <div className="dashboard-empty-line">
          <div className="empty-table-shape"><span /></div>
          <strong>Línea disponible</strong>
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

          <div className="factory-table-scene" aria-label={`Mesa ${line.lineCode}`}>
            <div className="factory-table">
              <span className="factory-table-label">TIEMPO GLOBAL DE MESA</span>
              <time>{formatDuration(projectedTotal)}</time>
              <small>Abierta hace {formatDuration(openedSeconds)}</small>
              <div className="factory-table-output">
                <strong>{numberFormatter.format(order.goodQuantity)}</strong>
                <span>de {numberFormatter.format(order.targetQuantity)} uds</span>
              </div>
              <div className="dashboard-progress" role="progressbar" aria-valuemin={0} aria-valuemax={100} aria-valuenow={Math.round(progress)}>
                <span style={{ width: `${progress}%` }} />
              </div>
              <b>{progress.toFixed(0)}% completado</b>
            </div>

            {table.operators.length === 0 ? (
              <div className="factory-no-operators">Sin operarios</div>
            ) : table.operators.slice(0, 10).map((operator, index) => {
              const seconds = operator.productiveSeconds +
                (operator.status === "PRODUCIENDO" && isProducing(line) ? elapsedSeconds : 0);
              return (
                <div
                  className={`factory-person ${operator.status === "PRODUCIENDO" ? "producing" : "paused"}`}
                  style={seatStyle(index, Math.min(table.operators.length, 10))}
                  key={operator.employeeId}
                  title={`${operator.fullName}: ${displayState(operator.status)}`}
                >
                  <div className="factory-avatar"><span aria-hidden="true">{initials(operator.fullName)}</span><i aria-hidden="true" /></div>
                  <strong>{operator.fullName}</strong>
                  <time>{formatDuration(seconds)}</time>
                  <small>{operator.status === "PRODUCIENDO" ? "Produciendo" : "En pausa"}</small>
                </div>
              );
            })}
            {table.operators.length > 10 && <div className="factory-overflow">+{table.operators.length - 10}</div>}
          </div>

          <div className="dashboard-performance">
            <div
              className={`performance-ring ${performanceTone(performance)}`}
              style={{ "--performance": `${performanceArc * 3.6}deg` } as CSSProperties}
              aria-label={`Productividad frente a ruta ${performanceDisplay}`}
            >
              <span><strong>{performanceDisplay}</strong><small>vs. ruta</small></span>
            </div>
            <div className="performance-copy">
              <span>Productividad frente al tiempo teórico NAV</span>
              <strong>{performance === null ? "Pendiente de datos" : `${performanceDisplay} de rendimiento`}</strong>
              <small>
                {numberFormatter.format(order.goodQuantity)} uds reales frente a {numberFormatter.format(theoreticalUnits)} uds teóricas
                {performance !== null && ` · ${signedUnits(order.goodQuantity - theoreticalUnits)}`}
              </small>
            </div>
            <dl>
              <div><dt>Ritmo teórico actual</dt><dd>{numberFormatter.format(table.currentTheoreticalCapacityPerHour)} uds/h</dd></div>
              <div><dt>Tiempo teórico orden</dt><dd>{theoreticalTotalSeconds === null ? "—" : formatDuration(theoreticalTotalSeconds)}</dd></div>
              <div><dt>Estimación restante</dt><dd>{estimatedRemainingSeconds === null ? "—" : formatDuration(estimatedRemainingSeconds)}</dd></div>
            </dl>
          </div>

          <dl className="dashboard-kpis">
            <div><dt>Personas activas</dt><dd>{table.activeResources}</dd></div>
            <div><dt>Palés cerrados</dt><dd>{line.closedPallets}</dd></div>
            <div><dt>Palé actual</dt><dd>{order.reservedQuantity} uds</dd></div>
            <div><dt>Formato</dt><dd>{table.palletFormatCode} · {table.unitsPerPallet}</dd></div>
          </dl>

          <div className="dashboard-integrations">
            <div className={line.navIssues ? "danger" : navPending ? "pending" : "ok"}>
              <span>NAV</span><strong>{integrationLabel(line.latestNavState, "nav")}</strong>
            </div>
            <div className={line.printIssues ? "danger" : printPending ? "pending" : "ok"}>
              <span>Etiqueta</span><strong>{integrationLabel(line.latestLabelState, "label")}</strong>
            </div>
            <div><span>Estado orden</span><strong>{displayState(order.state)}</strong></div>
          </div>
        </>
      )}

      {line.blockReason && <p className="dashboard-block-reason">{line.blockReason}</p>}
    </article>
  );
}
