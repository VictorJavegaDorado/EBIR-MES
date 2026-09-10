import { useEffect, useRef, useState, type FormEvent } from "react";
import { getPalletCloseOptions } from "../../pallet-close/api/getPalletCloseOptions";
import type { PalletEmployeeOption } from "../../pallet-close/model/palletClose";
import { PalletLabelReprint } from "../../label-reprint/ui/PalletLabelReprint";
import {
  PalletRecoveryApiError,
  retryPalletNavReconciliation,
  type PalletRecoveryState,
} from "../api/palletRecovery";

type Props = {
  lineId: number;
  recovery: PalletRecoveryState | null;
  elapsedSeconds: number;
  refreshFailed: boolean;
};
type OpenAction = "nav" | "print" | null;

export function PalletRecoveryActions({ lineId, recovery, elapsedSeconds, refreshFailed }: Props) {
  const [openAction, setOpenAction] = useState<OpenAction>(null);
  const [supervisors, setSupervisors] = useState<PalletEmployeeOption[]>([]);
  const [supervisorId, setSupervisorId] = useState("");
  const [reason, setReason] = useState("");
  const [loadingOptions, setLoadingOptions] = useState(false);
  const [retryState, setRetryState] = useState<
    { status: "idle" | "loading" | "queued" | "error"; message?: string; code?: string }
  >({ status: "idle" });
  const request = useRef<AbortController | null>(null);
  const correlationId = useRef<string | null>(null);

  useEffect(() => () => request.current?.abort(), []);
  useEffect(() => {
    setOpenAction(null);
    setRetryState({ status: "idle" });
    correlationId.current = null;
  }, [recovery?.palletId]);

  async function open(action: Exclude<OpenAction, null>) {
    setOpenAction(action);
    if (supervisors.length > 0) return;
    request.current?.abort();
    const controller = new AbortController();
    request.current = controller;
    setLoadingOptions(true);
    try {
      const options = await getPalletCloseOptions(lineId, controller.signal);
      setSupervisors(options.supervisors);
      if (options.supervisors.length === 1) setSupervisorId(String(options.supervisors[0].id));
    } catch {
      setRetryState({ status: "error", code: "SUPERVISORS_UNAVAILABLE",
        message: "No se pueden cargar los supervisores en este momento." });
    } finally {
      if (request.current === controller) request.current = null;
      setLoadingOptions(false);
    }
  }

  async function submitRetry(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!recovery?.navOperationId) return;
    const parsedSupervisor = Number(supervisorId);
    const normalizedReason = reason.trim();
    if (!Number.isSafeInteger(parsedSupervisor) || parsedSupervisor <= 0 || !normalizedReason) {
      setRetryState({ status: "error", code: "NAV_RETRY_DATA_REQUIRED",
        message: "Selecciona el supervisor e indica el motivo." });
      return;
    }
    correlationId.current ??= createCorrelationId();
    const controller = new AbortController();
    request.current = controller;
    setRetryState({ status: "loading" });
    try {
      await retryPalletNavReconciliation(
        recovery.navOperationId, parsedSupervisor, normalizedReason,
        correlationId.current, controller.signal,
      );
      setRetryState({ status: "queued",
        message: "Conciliación activada. Solo se consultará la salida existente en NAV." });
    } catch (error) {
      if (controller.signal.aborted) return;
      setRetryState({ status: "error",
        code: error instanceof PalletRecoveryApiError ? error.code : "NAV_RETRY_UNAVAILABLE",
        message: error instanceof Error ? error.message : "No se puede activar la conciliación." });
    } finally {
      if (request.current === controller) request.current = null;
    }
  }

  if (!recovery) return null;
  const navConfirmed = recovery.navState === "CONFIRMADA";
  const labelReady = ["LISTA", "IMPRESA"].includes(recovery.labelState ?? "");
  const navNeedsAttention = recovery.navState === "ERROR_DEFINITIVO"
    || recovery.navReconciliationRetryAvailable;
  const labelNeedsAttention = recovery.labelState === "ERROR"
    || recovery.labelState === "RESULTADO_DESCONOCIDO";
  const needsAttention = navNeedsAttention || labelNeedsAttention;
  const completed = navConfirmed && labelReady;
  const headline = needsAttention
    ? "El palé necesita revisión"
    : !navConfirmed
      ? "Registrando el palé en NAV"
      : !labelReady
        ? "NAV confirmado · Preparando la etiqueta"
        : recovery.labelState === "IMPRESA"
          ? "Palé completado · Etiqueta impresa"
          : "Etiqueta enviada a impresión";

  return (
    <section className={`pallet-recovery ${needsAttention ? "has-error" : completed ? "is-complete" : "is-working"}`} aria-label="Seguimiento del último palé">
      <header>
        <div><p className="eyebrow">Último palé · {recovery.palletNumber}</p><h3>{headline}</h3></div>
        <div className="pallet-recovery-statuses">
          <span className={navNeedsAttention ? "attention" : navConfirmed ? "ok" : "working"}>NAV: {formatNavState(recovery.navState)}</span>
          <span className={labelNeedsAttention ? "attention" : labelReady ? "ok" : "working"}>Etiqueta: {formatLabelState(recovery.labelState)}</span>
        </div>
      </header>

      <ol className="pallet-progress" aria-label="Progreso del palé">
        <ProgressStep label="Palé cerrado" state="complete" />
        <ProgressStep label="Registro NAV" state={navNeedsAttention ? "error" : navConfirmed ? "complete" : "active"} />
        <ProgressStep label="Etiqueta" state={labelNeedsAttention ? "error" : labelReady ? "complete" : navConfirmed ? "active" : "pending"} />
      </ol>

      <div className="pallet-live-feedback" role="status" aria-live="polite">
        {!completed && !needsAttention && <span className="pallet-spinner" aria-hidden="true" />}
        <div>
          <strong>{headline}</strong>
          <small>Tiempo desde el cierre: {formatDuration(elapsedSeconds)} · Comprobaciones: {recovery.navAttempts}</small>
          {!completed && !needsAttention && <small>MES comprueba la misma salida; no se registra ni imprime por duplicado.</small>}
          {refreshFailed && <small className="refresh-warning">Última lectura conservada. Reintentando automáticamente…</small>}
        </div>
      </div>

      <div className="pallet-recovery-buttons">
        {recovery.navReconciliationRetryAvailable && (
          <button type="button" className="secondary-action" onClick={() => void open("nav")}>
            Reintentar conciliación NAV
          </button>
        )}
        {recovery.labelReprintAvailable && (
          <button type="button" className="secondary-action" onClick={() => void open("print")}>
            Reimprimir etiqueta
          </button>
        )}
      </div>

      {navNeedsAttention && !recovery.navReconciliationRetryAvailable && (
        <p className="pallet-recovery-info" role="status">
          La conciliación NAV está en curso o necesita revisión técnica. La salida no se vuelve a enviar.
        </p>
      )}
      {loadingOptions && <p className="pallet-recovery-info" role="status">Cargando autorización…</p>}

      {openAction === "nav" && !loadingOptions && (
        <form className="pallet-recovery-form" onSubmit={submitRetry}>
          <div><strong>Reintentar conciliación NAV</strong><small>Consulta la salida ya enviada; no registra una salida nueva.</small></div>
          <label>Supervisor<select value={supervisorId} onChange={(event) => {
            setSupervisorId(event.target.value); correlationId.current = null; setRetryState({ status: "idle" });
          }} disabled={retryState.status === "loading"}>
            <option value="">Selecciona un supervisor</option>
            {supervisors.map((supervisor) => <option key={supervisor.id} value={supervisor.id}>{supervisor.name}</option>)}
          </select></label>
          <label>Motivo<input maxLength={500} value={reason} placeholder="Ej.: NAV registrado, etiqueta pendiente"
            onChange={(event) => { setReason(event.target.value); correlationId.current = null; setRetryState({ status: "idle" }); }}
            disabled={retryState.status === "loading"} /></label>
          {retryState.message && <p className={retryState.status === "error" ? "pallet-recovery-error" : "pallet-recovery-success"}
            role={retryState.status === "error" ? "alert" : "status"}>{retryState.message} {retryState.code && <code>{retryState.code}</code>}</p>}
          <button type="submit" className="secondary-action" disabled={retryState.status === "loading"}>
            {retryState.status === "loading" ? "Activando conciliación…" : "Confirmar conciliación"}
          </button>
        </form>
      )}

      {openAction === "print" && !loadingOptions && (
        <PalletLabelReprint palletId={recovery.palletId} supervisors={supervisors} />
      )}
    </section>
  );
}

function formatNavState(state: string | null) {
  if (state === "CONFIRMADA") return "confirmado";
  if (state === "RESULTADO_DESCONOCIDO") return "comprobando";
  if (state === "ERROR_REINTENTABLE") return "reintentando";
  if (state === "ERROR_DEFINITIVO") return "requiere revisión";
  return state ? state.toLowerCase().replaceAll("_", " ") : "pendiente";
}

function formatLabelState(state: string | null) {
  if (state === "PENDIENTE_NAV") return "esperando NAV";
  if (state === "LISTA") return "enviada";
  if (state === "IMPRESA") return "impresa";
  if (state === "ERROR" || state === "RESULTADO_DESCONOCIDO") return "requiere revisión";
  return state ? state.toLowerCase().replaceAll("_", " ") : "pendiente";
}

function formatDuration(totalSeconds: number) {
  const safe = Math.max(0, Math.floor(totalSeconds));
  const hours = Math.floor(safe / 3_600);
  const minutes = Math.floor((safe % 3_600) / 60);
  const seconds = safe % 60;
  return [hours, minutes, seconds].map((value) => String(value).padStart(2, "0")).join(":");
}

function ProgressStep({ label, state }: { label: string; state: "pending" | "active" | "complete" | "error" }) {
  return <li className={state}><span>{state === "complete" ? "✓" : state === "error" ? "!" : ""}</span><strong>{label}</strong></li>;
}

function createCorrelationId(): string {
  if (typeof crypto.randomUUID === "function") return crypto.randomUUID();
  const bytes = new Uint8Array(16); crypto.getRandomValues(bytes);
  bytes[6] = (bytes[6] & 0x0f) | 0x40; bytes[8] = (bytes[8] & 0x3f) | 0x80;
  const hex = Array.from(bytes, (value) => value.toString(16).padStart(2, "0"));
  return `${hex.slice(0, 4).join("")}-${hex.slice(4, 6).join("")}-${hex.slice(6, 8).join("")}-${hex.slice(8, 10).join("")}-${hex.slice(10).join("")}`;
}
