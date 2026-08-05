import { useEffect, useRef, useState, type FormEvent } from "react";
import {
  identifyLine,
  LineIdentificationApiError,
} from "../../line-identification/api/identifyLine";
import type { IdentifiedLine } from "../../line-identification/model/lineIdentification";
import { PalletClosePage } from "../../pallet-close/ui/PalletClosePage";
import {
  getProductionOrders,
  ProductionOrderSelectionApiError,
} from "../../production-order-selection/api/getProductionOrders";
import type { ProductionOrder } from "../../production-order-selection/model/productionOrder";
import {
  identifyEmployeeByRfid,
  RfidIdentificationApiError,
} from "../api/identifyEmployeeByRfid";
import {
  finishOperatorStop,
  getProductionTableState,
  type ProductionTableState,
  ProductionTableApiError,
  registerProductiveExit,
  startOrJoinProductionTable,
  startOperatorStop,
} from "../api/productionTable";

const steps = [
  { number: 1, short: "Línea", title: "Escanea la línea" },
  { number: 2, short: "Orden", title: "Escanea la orden" },
  { number: 3, short: "Equipo", title: "Identifica operarios" },
  { number: 4, short: "Palés", title: "Completa los palés" },
  { number: 5, short: "NAV", title: "Confirma la salida" },
  { number: 6, short: "Libre", title: "Libera la línea" },
] as const;

type FlowError = { message: string; code: string } | null;

export function ProductionFlowPage() {
  const [activeStep, setActiveStep] = useState(1);
  const [lineCode, setLineCode] = useState("");
  const [line, setLine] = useState<IdentifiedLine | null>(null);
  const [orders, setOrders] = useState<ProductionOrder[]>([]);
  const [orderCode, setOrderCode] = useState("");
  const [order, setOrder] = useState<ProductionOrder | null>(null);
  const [rfidCredential, setRfidCredential] = useState("");
  const [table, setTable] = useState<ProductionTableState | null>(null);
  const [clock, setClock] = useState(() => Date.now());
  const [busy, setBusy] = useState(false);
  const [operatorAction, setOperatorAction] = useState<string | null>(null);
  const [error, setError] = useState<FlowError>(null);
  const [notice, setNotice] = useState("");
  const request = useRef<AbortController | null>(null);
  const refreshRequest = useRef<AbortController | null>(null);
  const pendingCorrelations = useRef(new Map<string, string>());

  useEffect(() => () => {
    request.current?.abort();
    refreshRequest.current?.abort();
  }, []);
  useEffect(() => {
    if (!table || table.state !== "PRODUCIENDO" || table.activeResources === 0) return;
    const interval = window.setInterval(() => setClock(Date.now()), 1_000);
    return () => window.clearInterval(interval);
  }, [table]);

  useEffect(() => {
    if (!table || !order || !line) return;

    const refresh = async () => {
      refreshRequest.current?.abort();
      const controller = new AbortController();
      refreshRequest.current = controller;
      try {
        const currentTable = await getProductionTableState(
          order.productionOrderId,
          line.id,
          controller.signal,
        );
        if (currentTable) {
          setTable(currentTable);
          setClock(Date.now());
        }
      } catch {
        // Keep the last confirmed snapshot visible. The next refresh retries safely.
      } finally {
        if (refreshRequest.current === controller) refreshRequest.current = null;
      }
    };

    const interval = window.setInterval(refresh, 10_000);
    return () => {
      window.clearInterval(interval);
      refreshRequest.current?.abort();
      refreshRequest.current = null;
    };
  }, [table?.lineSessionId, order?.productionOrderId, line?.id]);

  const elapsedSinceSnapshot = table
    ? Math.max(0, Math.floor((clock - Date.parse(table.serverTimeUtc)) / 1_000))
    : 0;
  const productiveSeconds = table
    ? table.productiveSeconds
      + (table.state === "PRODUCIENDO" && table.activeResources > 0 ? elapsedSinceSnapshot : 0)
    : 0;
  const isProducing = table?.state === "PRODUCIENDO" && table.activeResources > 0;

  async function submitLine(event: FormEvent) {
    event.preventDefault();
    const normalized = lineCode.trim().toUpperCase();
    if (!normalized) {
      setError({ message: "Escanea el código de la línea.", code: "LINE_CODE_REQUIRED" });
      return;
    }

    setBusy(true);
    setError(null);
    setNotice("");
    request.current?.abort();
    const controller = new AbortController();
    request.current = controller;
    try {
      const identified = await identifyLine(normalized, controller.signal);
      const availableOrders = await getProductionOrders(controller.signal);
      setLine(identified);
      setLineCode(identified.code);
      setOrders(availableOrders);
      setActiveStep(2);
      setNotice(`Línea ${identified.code} preparada. Escanea ahora la orden.`);
    } catch (caught) {
      if (controller.signal.aborted) return;
      if (caught instanceof LineIdentificationApiError) {
        setError({ message: caught.message, code: caught.code });
      } else if (caught instanceof ProductionOrderSelectionApiError) {
        setError({
          message: "La línea es válida, pero no se pueden cargar las órdenes.",
          code: caught.code,
        });
      } else {
        setError({
          message: "No se puede contactar con el servicio MES.",
          code: "PRODUCTION_FLOW_UNAVAILABLE",
        });
      }
    } finally {
      if (request.current === controller) request.current = null;
      setBusy(false);
    }
  }

  async function submitOrder(event: FormEvent) {
    event.preventDefault();
    const normalized = orderCode.trim().toUpperCase();
    const match = orders.find(
      (candidate) => candidate.orderNumber.trim().toUpperCase() === normalized,
    );
    if (!match) {
      setError({
        message: "La orden escaneada no está disponible para producción.",
        code: "PRODUCTION_ORDER_NOT_AVAILABLE",
      });
      return;
    }

    setOrder(match);
    setTable(null);
    setOrderCode(match.orderNumber);
    setError(null);
    setNotice(`Orden ${match.orderNumber} seleccionada. Identifica el equipo.`);
    setActiveStep(3);

    setBusy(true);
    request.current?.abort();
    const controller = new AbortController();
    request.current = controller;
    try {
      if (!line) throw new ProductionTableApiError("PRODUCTION_CONTEXT_REQUIRED");
      const currentTable = await getProductionTableState(
        match.productionOrderId,
        line.id,
        controller.signal,
      );
      if (currentTable) {
        setTable(currentTable);
        setClock(Date.now());
        setNotice(`Mesa de ${match.orderNumber} recuperada desde el servidor.`);
      }
    } catch (caught) {
      if (controller.signal.aborted) return;
      setError({
        message: "No se puede recuperar el estado de la mesa en este momento.",
        code: caught instanceof ProductionTableApiError
          ? caught.code
          : "PRODUCTION_TABLE_UNAVAILABLE",
      });
    } finally {
      if (request.current === controller) request.current = null;
      setBusy(false);
    }
  }

  async function submitRfid(event: FormEvent) {
    event.preventDefault();
    const credential = rfidCredential.trim();
    setRfidCredential("");
    if (!credential) {
      setError({ message: "Acerca una tarjeta al lector.", code: "RFID_REQUIRED" });
      return;
    }

    setBusy(true);
    setError(null);
    setNotice("");
    request.current?.abort();
    refreshRequest.current?.abort();
    refreshRequest.current = null;
    const controller = new AbortController();
    request.current = controller;
    try {
      if (!line || !order) throw new ProductionTableApiError("PRODUCTION_CONTEXT_REQUIRED");
      const employee = await identifyEmployeeByRfid(credential, controller.signal);
      const operationKey = `${order.productionOrderId}:${line.id}:${employee.employeeId}`;
      const correlationId = pendingCorrelations.current.get(operationKey) ?? createCorrelationId();
      pendingCorrelations.current.set(operationKey, correlationId);
      await startOrJoinProductionTable(
        order.productionOrderId,
        line.id,
        employee.employeeId,
        correlationId,
        controller.signal,
      );
      const currentTable = await getProductionTableState(
        order.productionOrderId,
        line.id,
        controller.signal,
      );
      if (!currentTable) throw new ProductionTableApiError("PRODUCTION_TABLE_NOT_ACTIVE");
      setTable(currentTable);
      pendingCorrelations.current.delete(operationKey);
      setClock(Date.now());
      setNotice(
        currentTable.operators.length === 1
          ? `${employee.fullName} ha iniciado la producción.`
          : `${employee.fullName} se ha incorporado a la producción.`,
      );
    } catch (caught) {
      if (controller.signal.aborted) return;
      setError({
        message: caught instanceof ProductionTableApiError
          ? caught.message
          : "Tarjeta no identificada. Prueba de nuevo o avisa al supervisor.",
        code:
          caught instanceof RfidIdentificationApiError || caught instanceof ProductionTableApiError
            ? caught.code
            : "RFID_IDENTIFICATION_UNAVAILABLE",
      });
    } finally {
      if (request.current === controller) request.current = null;
      setBusy(false);
    }
  }

  async function runOperatorAction(
    employeeId: number,
    action: "EXIT" | "STOP_WC" | "STOP_HEAT" | "RESUME",
  ) {
    if (!table || !order || !line) {
      setError({ message: "No hay una mesa activa para esta acción.", code: "PRODUCTION_CONTEXT_REQUIRED" });
      return;
    }

    const operationKey = `${table.lineSessionId}:${employeeId}:${action}`;
    const correlationId = pendingCorrelations.current.get(operationKey) ?? createCorrelationId();
    pendingCorrelations.current.set(operationKey, correlationId);
    request.current?.abort();
    refreshRequest.current?.abort();
    refreshRequest.current = null;
    const controller = new AbortController();
    request.current = controller;
    setOperatorAction(operationKey);
    setBusy(true);
    setError(null);
    setNotice("");
    try {
      if (action === "EXIT") {
        await registerProductiveExit(
          table.lineSessionId, employeeId, correlationId, controller.signal,
        );
      } else if (action === "RESUME") {
        await finishOperatorStop(
          table.lineSessionId, employeeId, correlationId, controller.signal,
        );
      } else {
        await startOperatorStop(
          table.lineSessionId,
          employeeId,
          action === "STOP_WC" ? "WC" : "PAUSA_CALOR",
          correlationId,
          controller.signal,
        );
      }

      const currentTable = await getProductionTableState(
        order.productionOrderId, line.id, controller.signal,
      );
      if (!currentTable) throw new ProductionTableApiError("PRODUCTION_TABLE_NOT_ACTIVE");
      setTable(currentTable);
      setClock(Date.now());
      pendingCorrelations.current.delete(operationKey);
      setNotice(operatorActionNotice(action));
    } catch (caught) {
      if (controller.signal.aborted) return;
      setError({
        message: caught instanceof ProductionTableApiError
          ? caught.message
          : "No se ha podido actualizar el estado del operario.",
        code: caught instanceof ProductionTableApiError
          ? caught.code
          : "OPERATOR_ACTION_UNAVAILABLE",
      });
    } finally {
      if (request.current === controller) request.current = null;
      setOperatorAction(null);
      setBusy(false);
    }
  }

  function resetFlow() {
    request.current?.abort();
    refreshRequest.current?.abort();
    refreshRequest.current = null;
    setActiveStep(1);
    setLineCode("");
    setLine(null);
    setOrders([]);
    setOrderCode("");
    setOrder(null);
    setRfidCredential("");
    setTable(null);
    setOperatorAction(null);
    pendingCorrelations.current.clear();
    setError(null);
    setNotice("");
  }

  return (
    <div className="production-flow">
      <header className="flow-heading">
        <div>
          <p className="eyebrow">Puesto de producción</p>
          <h1>{steps[activeStep - 1].title}</h1>
          <p>Un único recorrido, de la línea libre a la salida terminada.</p>
        </div>
        {(line || order) && (
          <button className="flow-reset" type="button" onClick={resetFlow}>
            Cambiar de línea
          </button>
        )}
      </header>

      <ol className="flow-progress" aria-label="Progreso de la orden">
        {steps.map((step) => {
          const state = step.number < activeStep ? "complete" : step.number === activeStep ? "active" : "pending";
          return (
            <li className={state} key={step.number} aria-current={state === "active" ? "step" : undefined}>
              <span>{state === "complete" ? "✓" : step.number}</span>
              <strong>{step.short}</strong>
            </li>
          );
        })}
      </ol>

      <div className="flow-layout">
        <main className="flow-stage">
          {activeStep === 1 && (
            <ScanStage
              kicker="Paso 1 de 6"
              title="Escanea el código de línea"
              description="La pistola escribe el código y continúa automáticamente con Enter."
              value={lineCode}
              onChange={setLineCode}
              onSubmit={submitLine}
              label="Código de línea"
              placeholder="LINEA-TEST-01"
              button="Validar línea"
              busy={busy}
              autoFocus
            />
          )}

          {activeStep === 2 && (
            <ScanStage
              kicker="Paso 2 de 6"
              title="Escanea la orden de fabricación"
              description={`${orders.length} orden${orders.length === 1 ? "" : "es"} disponible${orders.length === 1 ? "" : "s"} para esta operación.`}
              value={orderCode}
              onChange={setOrderCode}
              onSubmit={submitOrder}
              label="Orden de fabricación"
              placeholder="Escanea la orden"
              button="Cargar orden"
              busy={busy}
              autoFocus
            />
          )}

          {activeStep === 3 && (
            <section className="flow-card rfid-stage">
              <div className="stage-number">03</div>
              <div className="stage-copy">
                <p className="eyebrow">Equipo de la orden</p>
                <h2>Acerca las tarjetas RFID</h2>
                <p>Escanea una tarjeta por persona. La credencial se valida y se descarta inmediatamente.</p>
              </div>
              <form className="scan-form" onSubmit={submitRfid}>
                <label htmlFor="rfid-credential">Lector RFID</label>
                <div className="scan-control rfid-control">
                  <span aria-hidden="true">RF</span>
                  <input
                    id="rfid-credential"
                    autoComplete="off"
                    autoFocus
                    value={rfidCredential}
                    onChange={(event) => setRfidCredential(event.target.value)}
                    placeholder="Esperando tarjeta…"
                    aria-describedby="rfid-privacy"
                  />
                  <button type="submit" disabled={busy}>{busy ? "Validando…" : "Identificar"}</button>
                </div>
                <small id="rfid-privacy">El valor de la tarjeta no aparece en pantalla ni se conserva.</small>
              </form>

              <div
                className={`production-status${isProducing ? " active" : table ? " initialized" : ""}`}
                role="status"
                aria-live="polite"
              >
                <div className="production-state">
                  <span className="production-pulse" aria-hidden="true" />
                  <div><small>Estado de mesa</small><strong>{table ? formatTableState(table.state) : "ESPERANDO PRIMER OPERARIO"}</strong></div>
                </div>
                <div className="production-metric"><small>Tiempo productivo total</small><strong>{formatDuration(productiveSeconds)}</strong></div>
                <div className="production-metric"><small>Capacidad actual</small><strong>{table ? `${table.activeResources} pers. · ${formatCapacity(table.currentTheoreticalCapacityPerHour)} u/h` : "0 pers."}</strong></div>
                <div className="production-metric"><small>Paletizado</small><strong>{table ? `${table.palletFormatCode} · ${table.unitsPerPallet} uds.` : "Pendiente"}</strong></div>
              </div>

              {table && (
                <p className="production-sync">
                  Inicio {formatTimestamp(table.startedAtUtc)} · Última confirmación del servidor {formatTimestamp(table.serverTimeUtc)} · Actualización automática cada 10 s
                </p>
              )}

              <div className="employee-list" aria-live="polite">
                {!table || table.operators.length === 0 ? (
                  <div className="empty-team">Todavía no hay personas identificadas.</div>
                ) : (
                  table.operators.map((employee) => (
                    <div className={`employee-chip ${employee.status === "EN_PAUSA" ? "paused" : "producing"}`} key={employee.employeeId}>
                      <span className="employee-state-icon" aria-hidden="true">{employee.status === "EN_PAUSA" ? "Ⅱ" : "✓"}</span>
                      <div className="employee-identity">
                        <strong>{employee.fullName}</strong>
                        <small>
                          {employee.navEmployeeCode} · {employee.status === "EN_PAUSA" ? "En pausa" : "Produciendo"} · {formatDuration(
                            employee.productiveSeconds
                            + (employee.status === "PRODUCIENDO" && isProducing ? elapsedSinceSnapshot : 0),
                          )}
                        </small>
                      </div>
                      <div className="employee-actions">
                        {employee.status === "EN_PAUSA" ? (
                          <button
                            type="button"
                            disabled={operatorAction !== null}
                            aria-label={`Reanudar a ${employee.fullName}`}
                            onClick={() => runOperatorAction(employee.employeeId, "RESUME")}
                          >
                            Reanudar
                          </button>
                        ) : (
                          <>
                            <button
                              type="button"
                              disabled={operatorAction !== null}
                              aria-label={`Pausa WC de ${employee.fullName}`}
                              onClick={() => runOperatorAction(employee.employeeId, "STOP_WC")}
                            >
                              WC
                            </button>
                            <button
                              type="button"
                              disabled={operatorAction !== null}
                              aria-label={`Pausa calor de ${employee.fullName}`}
                              onClick={() => runOperatorAction(employee.employeeId, "STOP_HEAT")}
                            >
                              Calor
                            </button>
                            <button
                              type="button"
                              disabled={operatorAction !== null}
                              aria-label={`Registrar salida de ${employee.fullName}`}
                              onClick={() => runOperatorAction(employee.employeeId, "EXIT")}
                            >
                              Salir
                            </button>
                          </>
                        )}
                      </div>
                    </div>
                  ))
                )}
              </div>

              <button
                className="continue-action"
                type="button"
                disabled={!table || table.activeResources === 0}
                onClick={() => { setActiveStep(4); setError(null); setNotice("Equipo validado. Revisa los palés activos."); }}
              >
                Continuar a palés <span aria-hidden="true">→</span>
              </button>
            </section>
          )}

          {activeStep === 4 && line && (
            <section className="pallet-stage">
              <div className="stage-intro">
                <div className="stage-number">04</div>
                <div><p className="eyebrow">Paletización</p><h2>Completa y cierra los palés</h2><p>Solo se muestran reservas activas de esta línea.</p></div>
              </div>
              <PalletClosePage line={line} />
              <button className="continue-action secondary" type="button" onClick={() => { setActiveStep(5); setError(null); setNotice(""); }}>
                Revisar cierre de orden <span aria-hidden="true">→</span>
              </button>
            </section>
          )}

          {activeStep === 5 && (
            <section className="flow-card blocked-stage">
              <div className="stage-number">05</div>
              <p className="eyebrow">NAV y salida de fábrica</p>
              <h2>Confirmación final pendiente de integración</h2>
              <p>Este paso quedará habilitado cuando el backend confirme el registro en NAV y la etiqueta de salida. La interfaz no simula una confirmación ni envía impresiones.</p>
              <div className="blocked-notice"><span aria-hidden="true">!</span><div><strong>Acción bloqueada de forma segura</strong><small>Falta el contrato de cierre de orden y confirmación NAV.</small></div></div>
              <button className="continue-action" type="button" disabled>Confirmar NAV y liberar línea</button>
            </section>
          )}

          {error && <div className="flow-message error" role="alert"><strong>{error.message}</strong><code>{error.code}</code></div>}
          {notice && !error && <div className="flow-message success" role="status">{notice}</div>}
        </main>

        <aside className="flow-summary" aria-label="Resumen de la operación">
          <div className="summary-title"><span className="environment-dot" /><div><strong>Operación actual</strong><small>Actualización en tiempo real</small></div></div>
          <SummaryRow label="Línea" value={line?.code ?? "Pendiente"} complete={Boolean(line)} />
          <SummaryRow label="Orden" value={order?.orderNumber ?? "Pendiente"} complete={Boolean(order)} />
          <SummaryRow label="Producción" value={table ? `${formatDuration(productiveSeconds)} · ${table.activeResources} pers.` : "Pendiente"} complete={Boolean(table)} />
          <SummaryRow label="Palés" value={activeStep > 4 ? "Revisados" : "Pendiente"} complete={activeStep > 4} />
          <SummaryRow label="NAV / salida" value="Pendiente" complete={false} />
          <div className="summary-order">
            <span>Producto</span>
            <strong>{order?.productDescription ?? "Se mostrará al escanear la orden"}</strong>
            {order && <small>{order.productNumber} · Lote {order.lotNumber}</small>}
          </div>
        </aside>
      </div>
    </div>
  );
}

type ScanStageProps = {
  kicker: string;
  title: string;
  description: string;
  value: string;
  onChange: (value: string) => void;
  onSubmit: (event: FormEvent) => void;
  label: string;
  placeholder: string;
  button: string;
  busy: boolean;
  autoFocus?: boolean;
};

function ScanStage(props: ScanStageProps) {
  const inputId = `scan-${props.label.toLowerCase().replaceAll(/[^a-z0-9]+/g, "-")}`;
  return (
    <section className="flow-card scan-stage">
      <div className="stage-number">{props.kicker.match(/\d+/)?.[0]?.padStart(2, "0")}</div>
      <div className="stage-copy"><p className="eyebrow">{props.kicker}</p><h2>{props.title}</h2><p>{props.description}</p></div>
      <form className="scan-form" onSubmit={props.onSubmit}>
        <label htmlFor={inputId}>{props.label}</label>
        <div className="scan-control">
          <span aria-hidden="true">⌁</span>
          <input
            id={inputId}
            autoComplete="off"
            autoFocus={props.autoFocus}
            value={props.value}
            onChange={(event) => props.onChange(event.target.value)}
            placeholder={props.placeholder}
          />
          <button type="submit" disabled={props.busy}>{props.busy ? "Validando…" : props.button}</button>
        </div>
        <small>Compatible con lector USB HID y terminador Enter.</small>
      </form>
    </section>
  );
}

function formatDuration(totalSeconds: number): string {
  const seconds = Math.max(0, Math.floor(totalSeconds));
  const hours = Math.floor(seconds / 3_600);
  const minutes = Math.floor((seconds % 3_600) / 60);
  const remainder = seconds % 60;
  return [hours, minutes, remainder].map((value) => String(value).padStart(2, "0")).join(":");
}

function formatCapacity(value: number): string {
  return new Intl.NumberFormat("es-ES", { maximumFractionDigits: 2 }).format(value);
}

function formatTableState(state: string): string {
  return state.replaceAll("_", " ");
}

function formatTimestamp(value: string | null): string {
  if (!value) return "pendiente";
  const timestamp = Date.parse(value);
  if (!Number.isFinite(timestamp)) return "no disponible";
  return new Intl.DateTimeFormat("es-ES", {
    hour: "2-digit",
    minute: "2-digit",
    second: "2-digit",
  }).format(timestamp);
}

function operatorActionNotice(action: "EXIT" | "STOP_WC" | "STOP_HEAT" | "RESUME"): string {
  if (action === "EXIT") return "Salida registrada. Capacidad actualizada por el servidor.";
  if (action === "RESUME") return "Operario reincorporado. El tiempo individual vuelve a avanzar.";
  return "Pausa registrada. El acumulado individual queda detenido.";
}

function createCorrelationId(): string {
  if (typeof globalThis.crypto.randomUUID === "function") {
    return globalThis.crypto.randomUUID();
  }

  const bytes = globalThis.crypto.getRandomValues(new Uint8Array(16));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  const hex = Array.from(bytes, (byte) => byte.toString(16).padStart(2, "0")).join("");
  return [hex.slice(0, 8), hex.slice(8, 12), hex.slice(12, 16), hex.slice(16, 20), hex.slice(20)].join("-");
}

function SummaryRow({ label, value, complete }: { label: string; value: string; complete: boolean }) {
  return <div className={`summary-row${complete ? " complete" : ""}`}><span>{complete ? "✓" : "·"}</span><div><small>{label}</small><strong>{value}</strong></div></div>;
}
