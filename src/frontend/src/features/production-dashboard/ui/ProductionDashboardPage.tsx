import { useEffect, useMemo, useRef, useState, type CSSProperties } from "react";
import {
  getProductionDashboard,
  getProductionDashboardSupervisors,
  type ProductionDashboardLine,
  type ProductionDashboardSnapshot,
  type ProductionDashboardSupervisor,
} from "../api/productionDashboard";
import type { AuthorizedSupervisor } from "../../supervisor-access/api/authorizeSupervisorByRfid";
import { SupervisorIdentificationScreen } from "./SupervisorIdentificationScreen";
import { LineAssignmentPicker } from "./LineAssignmentPicker";

const refreshMilliseconds = 5_000;
const supervisorParameter = "jefe";
const identityStorageKey = "mes.dashboard.supervisor";
const cardLimit = 6;
const visiblePeople = 6;
const numberFormatter = new Intl.NumberFormat("es-ES", { maximumFractionDigits: 1 });
const averageFormatter = new Intl.NumberFormat("es-ES", {
  minimumFractionDigits: 2,
  maximumFractionDigits: 2,
});
const timeFormatter = new Intl.DateTimeFormat("es-ES", {
  hour: "2-digit",
  minute: "2-digit",
  second: "2-digit",
});
const clockFormatter = new Intl.DateTimeFormat("es-ES", { hour: "2-digit", minute: "2-digit" });

type Tone = "running" | "waiting" | "danger" | "idle";
type ComplianceTone = "gray" | "green" | "amber" | "red";
type ActionTone = "ok" | "wait" | "attn";

const complianceToneLabels: Record<ComplianceTone, string> = {
  gray: "sin datos",
  green: "verde",
  amber: "ámbar",
  red: "rojo",
};

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

function statusTone(line: ProductionDashboardLine): Tone {
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

function initials(fullName: string) {
  return fullName.split(/\s+/).filter(Boolean).slice(0, 2)
    .map(part => part[0]).join("").toLocaleUpperCase("es-ES");
}

function readSupervisorFromUrl(): string | null {
  const value = new URLSearchParams(window.location.search).get(supervisorParameter)?.trim();
  return value ? value : null;
}

function writeSupervisorToUrl(code: string | null) {
  const url = new URL(window.location.href);
  if (code) url.searchParams.set(supervisorParameter, code);
  else url.searchParams.delete(supervisorParameter);
  window.history.replaceState(null, "", url);
}

function readStoredIdentity(): AuthorizedSupervisor | null {
  try {
    const raw = window.sessionStorage.getItem(identityStorageKey);
    if (!raw) return null;
    const parsed = JSON.parse(raw) as Partial<AuthorizedSupervisor>;
    if (
      typeof parsed.employeeId === "number"
      && typeof parsed.navEmployeeCode === "string"
      && typeof parsed.fullName === "string"
    ) {
      return { employeeId: parsed.employeeId, navEmployeeCode: parsed.navEmployeeCode, fullName: parsed.fullName };
    }
    return null;
  } catch {
    return null;
  }
}

function writeStoredIdentity(identity: AuthorizedSupervisor | null) {
  try {
    if (identity) window.sessionStorage.setItem(identityStorageKey, JSON.stringify(identity));
    else window.sessionStorage.removeItem(identityStorageKey);
  } catch {
    // A private window or blocked site data just skips persistence.
  }
}

type LineMetrics = {
  progress: number;
  projectedTotal: number;
  openedSeconds: number;
  compliance: number | null;
  complianceTone: ComplianceTone;
  averageOperators: number | null;
  remainingSeconds: number | null;
  palletLabel: string;
};

function lineMetrics(
  line: ProductionDashboardLine,
  elapsedSeconds: number,
  snapshotTimeUtc: string,
): LineMetrics {
  const order = line.order;
  const table = line.table;
  const producing = isProducing(line);
  const progress = order && order.targetQuantity > 0
    ? Math.min(100, Math.max(0, (order.goodQuantity / order.targetQuantity) * 100))
    : 0;
  const projectedTotal = (table?.productiveSeconds ?? 0) + (producing ? elapsedSeconds : 0);
  const openedSeconds = table?.startedAtUtc
    ? Math.max(0, (new Date(snapshotTimeUtc).getTime() - new Date(table.startedAtUtc).getTime()) / 1000 + elapsedSeconds)
    : 0;
  const theoreticalUnits = line.theoreticalUnitsToDate
    + (producing ? (table?.currentTheoreticalCapacityPerHour ?? 0) * elapsedSeconds / 3600 : 0);
  const compliance = order && order.goodQuantity > 0 && theoreticalUnits > 0
    ? order.goodQuantity / theoreticalUnits * 100
    : null;
  const resourceSeconds = line.resourceSeconds
    + (producing ? (table?.activeResources ?? 0) * elapsedSeconds : 0);
  const averageOperators = openedSeconds > 0 ? resourceSeconds / openedSeconds : null;
  const remainingSeconds = order && table && table.currentTheoreticalCapacityPerHour > 0
    ? Math.max(0, order.targetQuantity - order.goodQuantity) / table.currentTheoreticalCapacityPerHour * 3600
    : null;
  const totalPallets = order && table?.unitsPerPallet
    ? Math.max(1, Math.ceil(order.targetQuantity / table.unitsPerPallet))
    : null;
  const remainingUnits = order ? Math.max(0, order.targetQuantity - order.goodQuantity) : 0;
  const palletLabel = totalPallets
    ? remainingUnits > 0
      ? `${Math.min(line.closedPallets + 1, totalPallets)} de ${totalPallets}`
      : "todos cerrados"
    : "—";

  let complianceTone: ComplianceTone = "gray";
  if (compliance !== null) {
    if (needsAttention(line)) complianceTone = "red";
    else if (table && table.activeResources === 0 && order?.state !== "PENDIENTE_CIERRE") complianceTone = "red";
    else if (compliance >= 95) complianceTone = "green";
    else if (compliance >= 80) complianceTone = "amber";
    else complianceTone = "red";
  }

  return {
    progress,
    projectedTotal,
    openedSeconds,
    compliance,
    complianceTone,
    averageOperators,
    remainingSeconds,
    palletLabel,
  };
}

function lineAction(
  line: ProductionDashboardLine,
  metrics: LineMetrics,
): { tone: ActionTone; text: string } | null {
  if (!line.order || !line.table) return null;
  if (line.navIssues > 0) return { tone: "attn", text: "Revisar: conciliación NAV pendiente." };
  if (line.printIssues > 0) return { tone: "attn", text: "Revisar: incidencia de impresión pendiente." };
  if (line.operationalState === "BLOQUEADA") return { tone: "attn", text: "Línea bloqueada · revisar antes de continuar." };
  if (line.order.state === "PENDIENTE_CIERRE") return { tone: "wait", text: "Finalizar la orden en la mesa." };
  if (isProducing(line)) {
    return metrics.complianceTone === "red"
      ? { tone: "wait", text: "Ritmo por debajo del 80 % del teórico." }
      : { tone: "ok", text: "Sin acción · dentro de ritmo." };
  }
  if (line.table.activeResources === 0) {
    const since = line.table.startedAtUtc
      ? ` desde las ${clockFormatter.format(new Date(line.table.startedAtUtc))}`
      : "";
    return { tone: "wait", text: `Esperando operarios${since}.` };
  }
  return { tone: "ok", text: "Sin acción." };
}

type Stage = "viewing" | "identify" | "pick";

export function ProductionDashboardPage() {
  const [identity, setIdentity] = useState<AuthorizedSupervisor | null>(readStoredIdentity);
  const [pendingIdentity, setPendingIdentity] = useState<AuthorizedSupervisor | null>(null);
  const [stage, setStage] = useState<Stage>("viewing");
  const [supervisor, setSupervisor] = useState<string | null>(
    () => readStoredIdentity()?.navEmployeeCode ?? readSupervisorFromUrl(),
  );
  const [supervisors, setSupervisors] = useState<ProductionDashboardSupervisor[]>([]);
  const [snapshot, setSnapshot] = useState<ProductionDashboardSnapshot | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [receivedAt, setReceivedAt] = useState(0);
  const [tick, setTick] = useState(0);
  const request = useRef<AbortController | null>(null);

  function handleIdentified(newIdentity: AuthorizedSupervisor) {
    setPendingIdentity(newIdentity);
    setStage("pick");
  }

  function handlePickerCancel() {
    setPendingIdentity(null);
    setStage("viewing");
  }

  function handlePickerSaved() {
    if (pendingIdentity) {
      setIdentity(pendingIdentity);
      writeStoredIdentity(pendingIdentity);
      setSupervisor(pendingIdentity.navEmployeeCode);
      writeSupervisorToUrl(pendingIdentity.navEmployeeCode);
    }
    setPendingIdentity(null);
    setStage("viewing");
  }

  function beginChangeSelection() {
    if (!identity) return;
    setPendingIdentity(identity);
    setStage("pick");
  }

  function exitIdentity() {
    setIdentity(null);
    writeStoredIdentity(null);
    setSupervisor(null);
    writeSupervisorToUrl(null);
    setStage("viewing");
  }

  useEffect(() => {
    const controller = new AbortController();
    getProductionDashboardSupervisors(controller.signal)
      .then(setSupervisors)
      .catch(() => {
        // The selector keeps only "Toda la planta" until the list is available.
      });
    return () => controller.abort();
  }, []);

  useEffect(() => {
    let mounted = true;
    setSnapshot(null);
    async function refresh() {
      request.current?.abort();
      const controller = new AbortController();
      request.current = controller;
      try {
        const next = await getProductionDashboard(supervisor, controller.signal);
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
  }, [supervisor]);

  function selectSupervisor(code: string | null) {
    setSupervisor(code);
    writeSupervisorToUrl(code);
  }

  const lines = snapshot?.lines ?? [];
  const elapsedSeconds = receivedAt === 0 ? 0 : Math.max(0, (performance.now() - receivedAt) / 1000);
  const summary = useMemo(() => ({
    total: lines.length,
    running: lines.filter(isProducing).length,
    waiting: lines.filter(line => line.order && !isProducing(line) && !needsAttention(line)).length,
    attention: lines.filter(needsAttention).length,
  }), [lines, tick]);
  const supervisorRecord = snapshot?.supervisor
    ?? supervisors.find(item => item.navEmployeeCode === supervisor)
    ?? null;
  const plantView = supervisor === null && lines.length > cardLimit;
  const compact = !plantView && lines.length > cardLimit;
  const columns = plantView ? 5 : lines.length <= 4 ? 2 : lines.length <= cardLimit ? 3 : 4;
  const identified = identity !== null && supervisor === identity.navEmployeeCode;
  const scopeName = identified ? identity!.fullName : supervisorRecord?.fullName ?? supervisor;

  if (stage === "identify") {
    return (
      <SupervisorIdentificationScreen
        onIdentified={handleIdentified}
        onSkip={() => setStage("viewing")}
      />
    );
  }

  if (stage === "pick" && pendingIdentity) {
    return (
      <LineAssignmentPicker
        supervisor={pendingIdentity}
        onSaved={handlePickerSaved}
        onCancel={handlePickerCancel}
      />
    );
  }

  return (
    <section
      className={`production-dashboard${plantView ? " plant" : ""}${compact ? " compact" : ""}`}
      style={{ "--dashboard-columns": columns } as CSSProperties}
    >
      <h1 className="sr-only">Planta en tiempo real</h1>

      <header className="dashboard-summary" aria-label="Resumen de líneas">
        <div className="dashboard-scope">
          <div>
            <small>{supervisor ? "Jefe de línea" : "Vista"}</small>
            <strong>{supervisor ? scopeName : "Toda la planta"}</strong>
          </div>
          {identified ? (
            <div className="dashboard-scope-identity-actions">
              <button type="button" className="dashboard-scope-link" onClick={beginChangeSelection}>
                Cambiar selección
              </button>
              <button type="button" className="dashboard-scope-link" onClick={exitIdentity}>
                Salir
              </button>
            </div>
          ) : (
            <>
              <label className="sr-only" htmlFor="dashboard-supervisor">Jefe de línea</label>
              <select
                id="dashboard-supervisor"
                value={supervisor ?? ""}
                onChange={event => selectSupervisor(event.target.value || null)}
              >
                <option value="">Toda la planta</option>
                {supervisors.map(item => (
                  <option key={item.navEmployeeCode} value={item.navEmployeeCode}>
                    {item.fullName} · {item.lines.length} {item.lines.length === 1 ? "línea" : "líneas"}
                  </option>
                ))}
                {supervisor && !supervisors.some(item => item.navEmployeeCode === supervisor) && (
                  <option value={supervisor}>{supervisorRecord?.fullName ?? supervisor}</option>
                )}
              </select>
              <button type="button" className="dashboard-scope-link" onClick={() => setStage("identify")}>
                Soy jefe de línea
              </button>
            </>
          )}
        </div>
        <article><span>{supervisor ? "Mis líneas" : "Líneas"}</span><strong>{summary.total}</strong></article>
        <article className="running"><span>Produciendo</span><strong>{summary.running}</strong></article>
        <article className="waiting"><span>En espera</span><strong>{summary.waiting}</strong></article>
        <article className="danger"><span>Atención</span><strong>{summary.attention}</strong></article>
        <div className={`dashboard-live ${error ? "stale" : ""}`}>
          <span />
          <div>
            <strong>{error ? "Sin conexión" : "En directo"}</strong>
            <small>{snapshot ? `Actualizado ${timeFormatter.format(new Date(snapshot.serverTimeUtc))}` : "Conectando..."}</small>
          </div>
        </div>
      </header>

      {error && (
        <div className="dashboard-alert" role="alert">
          <strong>No se ha podido refrescar.</strong> Se conserva la última lectura. {error}
        </div>
      )}

      {!snapshot && !error && <div className="dashboard-loading">Cargando líneas de fabricación...</div>}
      {snapshot && supervisor && lines.length === 0 && (
        <div className="dashboard-loading">Este jefe de línea no tiene líneas asignadas.</div>
      )}

      <div className="dashboard-lines">
        {lines.map(line => plantView
          ? <LineTile key={line.lineId} line={line} elapsedSeconds={elapsedSeconds} snapshotTimeUtc={snapshot!.serverTimeUtc} />
          : <LineCard key={line.lineId} line={line} elapsedSeconds={elapsedSeconds} snapshotTimeUtc={snapshot!.serverTimeUtc} />)}
      </div>
    </section>
  );
}

type LineProps = {
  line: ProductionDashboardLine;
  elapsedSeconds: number;
  snapshotTimeUtc: string;
};

function LineCard({ line, elapsedSeconds, snapshotTimeUtc }: LineProps) {
  const order = line.order;
  const table = line.table;
  const tone = statusTone(line);
  const metrics = lineMetrics(line, elapsedSeconds, snapshotTimeUtc);
  const action = lineAction(line, metrics);
  const navPending = line.pendingNavOutputs > 0;
  const printPending = line.pendingPrintJobs > 0;

  return (
    <article className={`dashboard-line-card ${tone}`}>
      <header>
        <div>
          <span>{line.workCenterCode}</span>
          <h2>{line.lineCode}</h2>
          <p>{line.lineName}</p>
        </div>
        <strong className="dashboard-state">
          <StateIcon tone={tone} />
          <i aria-hidden="true" />{displayState(table?.state ?? line.operationalState)}
        </strong>
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
              <small>{order.productNumber} · {order.lotNumber || "Sin lote"} · {order.productDescription}</small>
            </div>
            <div className="dashboard-units">
              <strong>{numberFormatter.format(order.goodQuantity)}</strong>
              <span>de {numberFormatter.format(order.targetQuantity)} uds</span>
              <b>{metrics.progress.toFixed(0)}%</b>
            </div>
          </div>
          <div className="dashboard-progress" role="progressbar" aria-valuemin={0} aria-valuemax={100} aria-valuenow={Math.round(metrics.progress)}>
            <span style={{ width: `${metrics.progress}%` }} />
          </div>

          <div className="dashboard-mesa" aria-label={`Mesa ${line.lineCode}`}>
            <div className="factory-table">
              <span className="factory-table-label">TIEMPO GLOBAL DE MESA</span>
              <time>{formatDuration(metrics.projectedTotal)}</time>
              <small>Palé {metrics.palletLabel} · {table.palletFormatCode} {table.unitsPerPallet}</small>
            </div>
            <div className="factory-people">
              {table.operators.length === 0 ? (
                <div className="factory-no-operators">Sin operarios</div>
              ) : table.operators.slice(0, visiblePeople).map(operator => {
                const seconds = operator.productiveSeconds
                  + (operator.status === "PRODUCIENDO" && isProducing(line) ? elapsedSeconds : 0);
                return (
                  <div
                    className={`factory-person ${operator.status === "PRODUCIENDO" ? "producing" : "paused"}`}
                    key={operator.employeeId}
                    title={`${operator.fullName}: ${displayState(operator.status)}`}
                  >
                    <div className="factory-avatar"><span aria-hidden="true">{initials(operator.fullName)}</span><i aria-hidden="true" /></div>
                    <strong>{operator.fullName}</strong>
                    <time>{formatDuration(seconds)}</time>
                  </div>
                );
              })}
              {table.operators.length > visiblePeople && (
                <div className="factory-overflow">+{table.operators.length - visiblePeople}</div>
              )}
            </div>
          </div>

          <dl className="dashboard-kpis">
            <div className="dashboard-kpi-light">
              <span
                className={`traffic-light ${metrics.complianceTone}`}
                role="img"
                aria-label={`Semáforo de productividad: ${complianceToneLabels[metrics.complianceTone]}`}
              >
                <i /><i /><i />
              </span>
            </div>
            <div className={`compliance ${metrics.complianceTone}`}>
              <dt>Cumplimiento</dt>
              <dd>{metrics.compliance === null ? "Pendiente del 1.er palé" : `${Math.round(metrics.compliance)} %`}</dd>
            </div>
            <div><dt>Ritmo actual</dt><dd>{numberFormatter.format(table.currentTheoreticalCapacityPerHour)} u/h</dd></div>
            <div><dt>Promedio operarios</dt><dd>{metrics.averageOperators === null ? "—" : averageFormatter.format(metrics.averageOperators)}</dd></div>
            <div><dt>Restante estimado</dt><dd>{metrics.remainingSeconds === null ? "—" : formatDuration(metrics.remainingSeconds)}</dd></div>
          </dl>

          <div className="dashboard-integrations">
            <div className={line.navIssues ? "danger" : navPending ? "pending" : "ok"}>
              <span>NAV</span><strong>{integrationLabel(line.latestNavState, "nav")}</strong>
            </div>
            <div className={line.printIssues ? "danger" : printPending ? "pending" : "ok"}>
              <span>Etiqueta</span><strong>{integrationLabel(line.latestLabelState, "label")}</strong>
            </div>
          </div>

          {action && (
            <div className={`dashboard-action ${action.tone}`}>
              <StateIcon tone={action.tone === "attn" ? "danger" : action.tone === "wait" ? "waiting" : "running"} />
              {action.text}
            </div>
          )}
        </>
      )}

      {line.blockReason && <p className="dashboard-block-reason">{line.blockReason}</p>}
    </article>
  );
}

function LineTile({ line, elapsedSeconds, snapshotTimeUtc }: LineProps) {
  const tone = statusTone(line);
  const metrics = lineMetrics(line, elapsedSeconds, snapshotTimeUtc);
  const action = lineAction(line, metrics);
  const owner = line.supervisorName?.split(/\s+/)[0] ?? null;
  const people = line.table?.operators.length ?? 0;

  return (
    <article className={`dashboard-tile ${tone}`}>
      {owner && <span className="dashboard-tile-owner" title={line.supervisorName ?? undefined}>{owner}</span>}
      <header>
        <h2>{line.lineCode}</h2>
        <span className="dashboard-tile-state"><StateIcon tone={tone} />{displayState(line.table?.state ?? line.operationalState)}</span>
      </header>
      {line.order && line.table ? (
        <>
          <div className="dashboard-tile-order">
            <strong>{line.order.orderNumber}</strong>
            <span>{metrics.progress.toFixed(0)}%</span>
          </div>
          <div className="dashboard-progress" role="progressbar" aria-valuemin={0} aria-valuemax={100} aria-valuenow={Math.round(metrics.progress)}>
            <span style={{ width: `${metrics.progress}%` }} />
          </div>
          <div className="dashboard-tile-foot">
            <span>{isProducing(line) ? `Palé ${metrics.palletLabel} · ${people} pers.` : action?.text ?? ""}</span>
            <b className={metrics.complianceTone}>
              {metrics.compliance === null ? "Pendiente" : `${Math.round(metrics.compliance)} %`}
            </b>
          </div>
        </>
      ) : (
        <div className="dashboard-tile-empty"><strong>Línea disponible</strong><span>Sin orden activa</span></div>
      )}
    </article>
  );
}

function StateIcon({ tone }: { tone: Tone }) {
  const common = {
    className: "state-icon",
    viewBox: "0 0 24 24",
    fill: "none" as const,
    stroke: "currentColor",
    strokeWidth: 2.4,
    strokeLinecap: "round" as const,
    strokeLinejoin: "round" as const,
    "aria-hidden": true,
    focusable: false,
  };

  if (tone === "running") return <svg {...common}><path d="M5 12.5l4.5 4.5L19 7" /></svg>;
  if (tone === "danger") return <svg {...common}><path d="M12 8v5M12 16.5h.01" /><circle cx="12" cy="12" r="9" /></svg>;
  if (tone === "waiting") return <svg {...common}><circle cx="12" cy="12" r="8" /><path d="M12 8v4l3 2" /></svg>;
  return <svg {...common}><circle cx="12" cy="12" r="8" strokeDasharray="3 3" /></svg>;
}
