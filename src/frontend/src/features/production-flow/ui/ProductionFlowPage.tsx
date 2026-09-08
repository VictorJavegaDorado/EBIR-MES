import { useEffect, useRef, useState, type FormEvent } from "react";
import {
  identifyLine,
  LineIdentificationApiError,
} from "../../line-identification/api/identifyLine";
import type { IdentifiedLine } from "../../line-identification/model/lineIdentification";
import { PalletClosePage } from "../../pallet-close/ui/PalletClosePage";
import { PalletRecoveryActions } from "../../pallet-recovery/ui/PalletRecoveryActions";
import {
  getProductionOrders,
  ProductionOrderSelectionApiError,
} from "../../production-order-selection/api/getProductionOrders";
import type { ProductionOrder } from "../../production-order-selection/model/productionOrder";
import {
  prepareProductionOrder,
  ProductionOrderPreparationApiError,
} from "../../production-order-selection/api/prepareProductionOrder";
import {
  identifyEmployeeByRfid,
  RfidIdentificationApiError,
} from "../api/identifyEmployeeByRfid";
import {
  completeProductionOrder,
  finishOperatorStop,
  getActiveProductionTable,
  getProductionTableState,
  type ProductionTableState,
  ProductionTableApiError,
  registerProductiveExit,
  startOrJoinProductionTable,
  startOperatorStop,
} from "../api/productionTable";
import {
  OperatorActionDialog,
  type ActiveStopReason,
  type OperatorActionKind,
} from "./OperatorActionDialog";

const screenSteps = [
  { number: 1, short: "Línea", title: "Escanea la línea" },
  { number: 2, short: "Orden", title: "Escanea la orden" },
  { number: 3, short: "Trabajo", title: "Gestiona la producción" },
] as const;

const productionPhases = [
  "Línea y orden",
  "Identificación",
  "Producción y palés",
  "NAV e impresión",
  "Finalización",
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
  const [snapshotReceivedAt, setSnapshotReceivedAt] = useState(() => performance.now());
  const [clock, setClock] = useState(() => performance.now());
  const [busy, setBusy] = useState(false);
  const [operatorAction, setOperatorAction] = useState<string | null>(null);
  const [operatorDialog, setOperatorDialog] = useState<{
    employee: ProductionTableState["operators"][number];
    action: OperatorActionKind;
  } | null>(null);
  const operatorTriggerRef = useRef<HTMLButtonElement | null>(null);
  const [palletOperator, setPalletOperator] = useState<
    ProductionTableState["operators"][number] | null
  >(null);
  const palletModalRef = useRef<HTMLElement | null>(null);
  const palletTriggerRef = useRef<HTMLButtonElement | null>(null);
  const palletBusyRef = useRef(false);
  const [error, setError] = useState<FlowError>(null);
  const [notice, setNotice] = useState("");
  const request = useRef<AbortController | null>(null);
  const refreshRequest = useRef<AbortController | null>(null);
  const pendingCorrelations = useRef(new Map<string, string>());

  function acceptTableSnapshot(snapshot: ProductionTableState) {
    const receivedAt = performance.now();
    setTable(snapshot);
    setSnapshotReceivedAt(receivedAt);
    setClock(receivedAt);
  }

  useEffect(() => () => {
    request.current?.abort();
    refreshRequest.current?.abort();
  }, []);
  useEffect(() => {
    if (!table) return;
    const interval = window.setInterval(() => setClock(performance.now()), 1_000);
    return () => window.clearInterval(interval);
  }, [table]);

  useEffect(() => {
    if (!table || !order || !line) return;

    const refresh = async () => {
      refreshRequest.current?.abort();
      const controller = new AbortController();
      refreshRequest.current = controller;
      try {
        const active = await getActiveProductionTable(line.id, controller.signal);
        if (
          active
          && active.order.productionOrderId === order.productionOrderId
          && active.table.orderId === order.productionOrderId
          && active.table.lineId === line.id
        ) {
          setOrder(active.order);
          acceptTableSnapshot(active.table);
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

  useEffect(() => {
    if (!palletOperator) return;

    const currentOperator = table?.operators.find(
      (operator) => operator.employeeId === palletOperator.employeeId,
    );
    if (!currentOperator) {
      palletBusyRef.current = false;
      setPalletOperator(null);
      window.setTimeout(() => palletTriggerRef.current?.focus(), 0);
    }
  }, [table, palletOperator]);

  useEffect(() => {
    if (!operatorDialog) return;
    const currentOperator = table?.operators.find(
      (operator) => operator.employeeId === operatorDialog.employee.employeeId,
    );
    if (!currentOperator) {
      setOperatorDialog(null);
      window.setTimeout(() => operatorTriggerRef.current?.focus(), 0);
    }
  }, [table, operatorDialog]);

  useEffect(() => {
    if (!palletOperator) return;

    const previousOverflow = document.body.style.overflow;
    document.body.style.overflow = "hidden";
    const focusTimer = window.setTimeout(() => {
      const quantity = palletModalRef.current?.querySelector<HTMLInputElement>(
        "#good-quantity",
      );
      quantity?.focus();
      quantity?.select();
    }, 0);

    const handleKeyDown = (event: KeyboardEvent) => {
      if (event.key === "Escape" && !palletBusyRef.current) {
        event.preventDefault();
        closePalletModal();
        return;
      }
      if (event.key !== "Tab" || !palletModalRef.current) return;

      const focusable = Array.from(
        palletModalRef.current.querySelectorAll<HTMLElement>(
          'button:not([disabled]), input:not([disabled]), select:not([disabled]), summary, [tabindex]:not([tabindex="-1"])',
        ),
      );
      if (focusable.length === 0) return;
      const first = focusable[0];
      const last = focusable[focusable.length - 1];
      if (event.shiftKey && document.activeElement === first) {
        event.preventDefault();
        last.focus();
      } else if (!event.shiftKey && document.activeElement === last) {
        event.preventDefault();
        first.focus();
      }
    };

    document.addEventListener("keydown", handleKeyDown);
    return () => {
      window.clearTimeout(focusTimer);
      document.body.style.overflow = previousOverflow;
      document.removeEventListener("keydown", handleKeyDown);
    };
  }, [palletOperator]);

  const elapsedSinceSnapshot = table
    ? Math.max(0, Math.floor((clock - snapshotReceivedAt) / 1_000))
    : 0;
  const productiveSeconds = table
    ? table.productiveSeconds
      + (table.state === "PRODUCIENDO" && table.activeResources > 0 ? elapsedSinceSnapshot : 0)
    : 0;
  const isProducing = table?.state === "PRODUCIENDO" && table.activeResources > 0;
  const totalElapsedSeconds = table?.startedAtUtc
    ? secondsBetween(table.startedAtUtc, table.serverTimeUtc) + elapsedSinceSnapshot
    : 0;
  const stoppedSeconds = Math.max(0, totalElapsedSeconds - productiveSeconds);
  const productionPhase = getProductionPhase(activeStep, order, table);

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
    if (!normalized) {
      setError({
        message: "Escanea el número de la orden de fabricación.",
        code: "PRODUCTION_ORDER_NUMBER_REQUIRED",
      });
      return;
    }
    const match = orders.find(
      (candidate) => candidate.orderNumber.trim().toUpperCase() === normalized,
    );
    if (!match) {
      if (!line) {
        setError({
          message: "Vuelve a identificar la línea antes de cargar la orden.",
          code: "PRODUCTION_CONTEXT_REQUIRED",
        });
        return;
      }

      setBusy(true);
      setError(null);
      setNotice("");
      request.current?.abort();
      const controller = new AbortController();
      request.current = controller;
      try {
        const active = await getActiveProductionTable(line.id, controller.signal);
        if (
          active
          && active.order.orderNumber.trim().toUpperCase() === normalized
          && active.table.lineId === line.id
          && active.table.orderId === active.order.productionOrderId
        ) {
          setOrder(active.order);
          setOrderCode(active.order.orderNumber);
          acceptTableSnapshot(active.table);
          setActiveStep(3);
          setNotice(
            `Mesa pendiente de ${active.order.orderNumber} recuperada. Retira al operario antes de iniciar otra orden.`,
          );
          return;
        }

        const operationKey = `prepare-order:${normalized}`;
        const correlationId = pendingCorrelations.current.get(operationKey)
          ?? createCorrelationId();
        pendingCorrelations.current.set(operationKey, correlationId);
        setNotice(`Preparando la orden ${normalized} desde NAV…`);
        const prepared = await prepareProductionOrder(
          normalized,
          correlationId,
          controller.signal,
        );
        pendingCorrelations.current.delete(operationKey);
        setOrders((current) => [
          prepared,
          ...current.filter(
            (candidate) => candidate.productionOrderId !== prepared.productionOrderId,
          ),
        ]);
        setOrder(prepared);
        setOrderCode(prepared.orderNumber);
        setTable(null);
        setActiveStep(3);
        setNotice(
          `Orden ${prepared.orderNumber} preparada desde NAV. Identifica el equipo.`,
        );
      } catch (caught) {
        if (controller.signal.aborted) return;
        setError({
          message: caught instanceof ProductionOrderPreparationApiError
            ? caught.message
            : "No se puede comprobar ni preparar la orden en este momento.",
          code: caught instanceof ProductionTableApiError
            || caught instanceof ProductionOrderPreparationApiError
            ? caught.code
            : "PRODUCTION_ORDER_PREPARATION_UNAVAILABLE",
        });
      } finally {
        if (request.current === controller) request.current = null;
        setBusy(false);
      }
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
        acceptTableSnapshot(currentTable);
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
      acceptTableSnapshot(currentTable);
      pendingCorrelations.current.delete(operationKey);
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
    action: OperatorActionKind,
    credential: string,
    reason?: ActiveStopReason,
  ) {
    if (!table || !order || !line) {
      setError({ message: "No hay una mesa activa para esta acción.", code: "PRODUCTION_CONTEXT_REQUIRED" });
      return;
    }

    const operationKey = `${table.lineSessionId}:${employeeId}:${action}:${reason ?? ""}`;
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
          table.lineSessionId, employeeId, credential, correlationId, controller.signal,
        );
      } else if (action === "RESUME") {
        await finishOperatorStop(
          table.lineSessionId, employeeId, credential, correlationId, controller.signal,
        );
      } else {
        if (!reason) throw new ProductionTableApiError("STOP_REASON_REQUIRED");
        await startOperatorStop(
          table.lineSessionId,
          employeeId,
          reason,
          credential,
          correlationId,
          controller.signal,
        );
      }

      const currentTable = await getProductionTableState(
        order.productionOrderId, line.id, controller.signal,
      );
      if (!currentTable) throw new ProductionTableApiError("PRODUCTION_TABLE_NOT_ACTIVE");
      acceptTableSnapshot(currentTable);
      pendingCorrelations.current.delete(operationKey);
      setNotice(operatorActionNotice(action));
      setOperatorDialog(null);
      window.setTimeout(() => operatorTriggerRef.current?.focus(), 0);
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
    setOperatorDialog(null);
    palletBusyRef.current = false;
    setPalletOperator(null);
    pendingCorrelations.current.clear();
    setError(null);
    setNotice("");
  }

  async function startNewOrder() {
    if (!line) return;
    const completedOrderNumber = table && order?.state === "PENDIENTE_CIERRE"
      ? order.orderNumber
      : null;
    if (table && table.activeResources > 0) {
      setError({
        message: "Retira a los operarios antes de cargar una nueva orden.",
        code: "ACTIVE_OPERATORS_PREVENT_NEW_ORDER",
      });
      return;
    }

    if (table && order?.state === "PENDIENTE_CIERRE") {
      const operationKey = `complete-order:${table.lineSessionId}`;
      const correlationId = pendingCorrelations.current.get(operationKey)
        ?? createCorrelationId();
      pendingCorrelations.current.set(operationKey, correlationId);
      setBusy(true);
      setError(null);
      setNotice("");
      request.current?.abort();
      refreshRequest.current?.abort();
      refreshRequest.current = null;
      const controller = new AbortController();
      request.current = controller;
      try {
        await completeProductionOrder(
          table.lineSessionId,
          correlationId,
          controller.signal,
        );
        pendingCorrelations.current.delete(operationKey);
      } catch (caught) {
        if (controller.signal.aborted) return;
        setError({
          message: caught instanceof ProductionTableApiError
            ? caught.message
            : "No se ha podido finalizar la orden y liberar la línea.",
          code: caught instanceof ProductionTableApiError
            ? caught.code
            : "ORDER_COMPLETION_UNAVAILABLE",
        });
        return;
      } finally {
        if (request.current === controller) request.current = null;
        setBusy(false);
      }
    }

    request.current?.abort();
    refreshRequest.current?.abort();
    refreshRequest.current = null;
    setActiveStep(2);
    setOrderCode("");
    setOrder(null);
    setRfidCredential("");
    setTable(null);
    setOperatorAction(null);
    setOperatorDialog(null);
    palletBusyRef.current = false;
    setPalletOperator(null);
    pendingCorrelations.current.clear();
    setError(null);
    setNotice(completedOrderNumber
      ? `Orden ${completedOrderNumber} finalizada. Línea ${line.code} libre para una nueva orden.`
      : `Línea ${line.code} conservada. Escanea la nueva orden.`);
  }

  function openPalletModal(
    employee: ProductionTableState["operators"][number],
    trigger: HTMLButtonElement,
  ) {
    palletTriggerRef.current = trigger;
    palletBusyRef.current = false;
    setPalletOperator(employee);
  }

  function closePalletModal() {
    if (palletBusyRef.current) return;
    palletBusyRef.current = false;
    setPalletOperator(null);
    window.setTimeout(() => palletTriggerRef.current?.focus(), 0);
  }

  return (
    <div className="production-flow">
      <header className="flow-heading">
        <div>
          <p className="eyebrow">Puesto de producción</p>
          <h1>{screenSteps[activeStep - 1].title}</h1>
          <p>Línea, orden y todo el trabajo en una única mesa.</p>
        </div>
        {line && (
          <div className="flow-heading-actions">
            {order && order.state !== "PENDIENTE_CIERRE" && (
              <button
                className="flow-new-order"
                type="button"
                onClick={startNewOrder}
                disabled={busy}
              >
                Nueva orden
              </button>
            )}
            <button className="flow-reset" type="button" onClick={resetFlow}>
              Cambiar de línea
            </button>
          </div>
        )}
      </header>

      {error && (
        <div className="flow-message flow-feedback error" role="alert">
          <strong>{error.message}</strong><code>{error.code}</code>
        </div>
      )}
      {notice && !error && (
        <div className="flow-message flow-feedback success" role="status">
          <strong>{notice}</strong>
        </div>
      )}

      <ol className="flow-progress" aria-label="Progreso de la orden">
        {productionPhases.map((phase, index) => {
          const number = index + 1;
          const state = number < productionPhase
            ? "complete"
            : number === productionPhase ? "active" : "pending";
          return (
            <li className={state} key={phase} aria-current={state === "active" ? "step" : undefined}>
              <span>{state === "complete" ? "✓" : number}</span>
              <strong>{phase}</strong>
            </li>
          );
        })}
      </ol>

      <div className={`flow-layout${activeStep === 3 ? " working" : ""}`}>
        <main className="flow-stage">
          {activeStep === 1 && (
            <ScanStage
              kicker="Paso 1 de 3"
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
              kicker="Paso 2 de 3"
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
              {order && (
                <ProductionOrderHero
                  order={order}
                  table={table}
                  phase={productionPhase}
                  onComplete={startNewOrder}
                  busy={busy}
                />
              )}

              <form className="operator-entry-strip" onSubmit={submitRfid}>
                <div>
                  <strong>Incorporar operario</strong>
                  <small>Acerca su tarjeta RFID al lector.</small>
                </div>
                <div className="scan-control rfid-control compact">
                  <span aria-hidden="true">RF</span>
                  <input
                    id="rfid-credential"
                    autoComplete="off"
                    autoFocus
                    value={rfidCredential}
                    onChange={(event) => setRfidCredential(event.target.value)}
                    placeholder="Esperando tarjeta…"
                    aria-label="Lector RFID"
                    aria-describedby="rfid-privacy"
                  />
                  <button type="submit" disabled={busy}>{busy ? "Validando…" : "Identificar"}</button>
                </div>
                <small id="rfid-privacy">El valor de la tarjeta no aparece en pantalla ni se conserva.</small>
              </form>

              {order && (
                <ProductionTimeStrip
                  table={table}
                  order={order}
                  totalElapsedSeconds={totalElapsedSeconds}
                  productiveSeconds={productiveSeconds}
                  stoppedSeconds={stoppedSeconds}
                />
              )}

              {table && (
                <p className="production-sync">
                  Inicio {formatTimestamp(table.startedAtUtc)} · Última confirmación del servidor {formatTimestamp(table.serverTimeUtc)} · Actualización automática cada 10 s
                </p>
              )}

              <div className="employee-list" aria-live="polite">
                {!table || table.operators.length === 0 ? (
                  <div className="empty-team">Todavía no hay personas identificadas.</div>
                ) : (
                  table.operators.map((employee) => {
                    const initials = employee.fullName
                      .split(/\s+/)
                      .filter(Boolean)
                      .slice(0, 2)
                      .map((part) => part[0]?.toUpperCase())
                      .join("");

                    const currentEntrySeconds = secondsBetween(
                      employee.entryAtUtc,
                      table.serverTimeUtc,
                    ) + elapsedSinceSnapshot;
                    const visibleProductiveSeconds = employee.productiveSeconds
                      + (employee.status === "PRODUCIENDO" && isProducing
                        ? elapsedSinceSnapshot
                        : 0);

                    return (
                      <div
                        className={`employee-chip ${employee.status === "EN_PAUSA" ? "paused" : "producing"}`}
                        key={employee.employeeId}
                      >
                        <div className="employee-avatar" aria-hidden="true">
                          {initials || "OP"}
                        </div>

                        <div className="employee-identity">
                          <div className="employee-name-row">
                            <strong>{employee.fullName}</strong>
                            <span
                              className="employee-state-icon"
                              aria-hidden="true"
                              title={employee.status === "EN_PAUSA" ? "En pausa" : "Produciendo"}
                            >
                              {employee.status === "EN_PAUSA" ? "Ⅱ" : "✓"}
                            </span>
                          </div>
                          <small>
                            {employee.navEmployeeCode}
                          </small>
                        </div>

                        <div className="employee-current-state">
                          <small>{employee.status === "EN_PAUSA" ? "Paro activo" : "Estado actual"}</small>
                          <strong>{employee.status === "EN_PAUSA" ? "EN PARO" : "PRODUCIENDO"}</strong>
                          <span>{formatDuration(visibleProductiveSeconds)}</span>
                          <em>{employee.status === "EN_PAUSA" ? "Productivo acumulado" : "Tiempo productivo"}</em>
                        </div>

                        <div className="employee-time-grid">
                          <div><small>Desde entrada</small><strong>{formatDuration(currentEntrySeconds)}</strong></div>
                          <div><small>Productivo</small><strong>{formatDuration(visibleProductiveSeconds)}</strong></div>
                          <div><small>Parado</small><strong>{employee.status === "EN_PAUSA" ? "En curso" : "—"}</strong></div>
                        </div>

                        <div className="employee-actions">
                          {employee.status === "EN_PAUSA" ? (
                            <button
                              type="button"
                              className="employee-resume-action"
                              disabled={operatorAction !== null}
                              aria-label={`Reanudar a ${employee.fullName}`}
                              onClick={(event) => {
                                operatorTriggerRef.current = event.currentTarget;
                                setError(null);
                                setNotice("");
                                setOperatorDialog({ employee, action: "RESUME" });
                              }}
                            >
                              Reincorporar
                            </button>
                          ) : (
                            <>
                              <button
                                type="button"
                                className="employee-stop-action"
                                disabled={operatorAction !== null}
                                aria-label={`Registrar paro de ${employee.fullName}`}
                                onClick={(event) => {
                                  operatorTriggerRef.current = event.currentTarget;
                                  setError(null);
                                  setNotice("");
                                  setOperatorDialog({ employee, action: "STOP" });
                                }}
                              >
                                PARO
                              </button>
                              <button
                                type="button"
                                className="employee-exit-action"
                                disabled={operatorAction !== null}
                                aria-label={`Registrar salida de ${employee.fullName}`}
                                onClick={(event) => {
                                  operatorTriggerRef.current = event.currentTarget;
                                  setError(null);
                                  setNotice("");
                                  setOperatorDialog({ employee, action: "EXIT" });
                                }}
                              >
                                Salir de la mesa
                              </button>
                              <button
                                type="button"
                                className="employee-pallet-action"
                                disabled={!table || operatorAction !== null}
                                aria-label={`Cerrar palet como ${employee.fullName}`}
                                onClick={(event) => openPalletModal(employee, event.currentTarget)}
                              >
                                <PalletIcon />
                                Cerrar palet
                              </button>
                            </>
                          )}
                        </div>
                      </div>
                    );
                  })
                )}
              </div>

              {!table && (
                <div className="work-pallet-empty">
                  Identifica al primer operario para preparar el palet.
                </div>
              )}

              {table && (
                <section className="production-integration-band" aria-label="Estado de NAV e impresión">
                  <header>
                    <div>
                      <p className="eyebrow">Confirmación del último palé</p>
                      <h3>NAV e impresión</h3>
                    </div>
                    {!table.latestPalletRecovery && <span className="integration-waiting">Sin palés cerrados</span>}
                  </header>
                  {table.latestPalletRecovery ? (
                    <PalletRecoveryActions
                      lineId={table.lineId}
                      recovery={table.latestPalletRecovery}
                    />
                  ) : (
                    <p className="integration-empty">La conciliación y la etiqueta aparecerán aquí al cerrar el primer palé.</p>
                  )}
                </section>
              )}

              {operatorDialog && (
                <OperatorActionDialog
                  action={operatorDialog.action}
                  employee={operatorDialog.employee}
                  busy={operatorAction !== null}
                  serverError={error}
                  onCancel={() => {
                    if (operatorAction !== null) return;
                    setOperatorDialog(null);
                    window.setTimeout(() => operatorTriggerRef.current?.focus(), 0);
                  }}
                  onConfirm={(credential, reason) => runOperatorAction(
                    operatorDialog.employee.employeeId,
                    operatorDialog.action,
                    credential,
                    reason,
                  )}
                />
              )}

              {palletOperator && table && (
                <div
                  className="pallet-modal-backdrop"
                  role="presentation"
                  onMouseDown={(event) => {
                    if (event.target === event.currentTarget) closePalletModal();
                  }}
                >
                  <section
                    className="pallet-modal"
                    ref={palletModalRef}
                    role="dialog"
                    aria-modal="true"
                    aria-labelledby="pallet-modal-title"
                  >
                    <header className="pallet-modal-header">
                      <div>
                        <p className="eyebrow">Palet en curso</p>
                        <h3 id="pallet-modal-title">Cerrar palet</h3>
                        <p>
                          {palletOperator.fullName} · {palletOperator.navEmployeeCode}
                        </p>
                        <span className="pallet-modal-nav-status">
                          NAV se procesa en segundo plano
                        </span>
                      </div>
                      <button
                        type="button"
                        className="pallet-modal-close"
                        aria-label="Cerrar formulario"
                        onClick={closePalletModal}
                      >
                        ×
                      </button>
                    </header>

                    <PalletClosePage
                      line={line ?? undefined}
                      palletFormatCode={table.palletFormatCode}
                      selectedEmployee={{
                        id: palletOperator.employeeId,
                        code: palletOperator.navEmployeeCode,
                        name: palletOperator.fullName,
                      }}
                      onCancel={closePalletModal}
                      onBusyChange={(isBusy) => {
                        palletBusyRef.current = isBusy;
                      }}
                      onPalletClosed={(quantity) => {
                        setNotice(`Palet cerrado con ${quantity} unidades por ${palletOperator.fullName}. NAV queda pendiente en segundo plano.`);
                      }}
                    />
                  </section>
                </div>
              )}
            </section>
          )}

        </main>

        {activeStep !== 3 && <aside className="flow-summary" aria-label="Resumen de la operación">
          <div className="summary-title"><span className="environment-dot" /><div><strong>Operación actual</strong><small>Actualización en tiempo real</small></div></div>
          <SummaryRow label="Línea" value={line?.code ?? "Pendiente"} complete={Boolean(line)} />
          <SummaryRow label="Orden" value={order?.orderNumber ?? "Pendiente"} complete={Boolean(order)} />
          <SummaryRow label="Trabajo" value={table ? `${formatDuration(productiveSeconds)} · ${table.activeResources} pers.` : "Pendiente"} complete={Boolean(table)} />
          <SummaryRow label="NAV" value="Segundo plano" complete={false} />
          <div className="summary-order">
            <span>Producto</span>
            <strong>{order?.productDescription ?? "Se mostrará al escanear la orden"}</strong>
            {order && <small>{order.productNumber} · Lote {order.lotNumber}</small>}
          </div>
        </aside>}
      </div>
    </div>
  );
}

type ProductionOrderHeroProps = {
  order: ProductionOrder;
  table: ProductionTableState | null;
  phase: number;
  busy: boolean;
  onComplete: () => void;
};

function ProductionOrderHero({
  order,
  table,
  phase,
  busy,
  onComplete,
}: ProductionOrderHeroProps) {
  const remaining = Math.max(0, order.targetQuantity - order.goodQuantity);
  const progress = order.targetQuantity > 0
    ? Math.min(100, Math.round(order.goodQuantity * 100 / order.targetQuantity))
    : 0;
  const totalPallets = table?.unitsPerPallet
    ? Math.max(1, Math.ceil(order.targetQuantity / table.unitsPerPallet))
    : null;
  const completedPallets = table?.latestPalletRecovery?.palletNumber ?? 0;
  const palletLabel = totalPallets
    ? `${Math.min(completedPallets + (remaining > 0 ? 1 : 0), totalPallets)} de ${totalPallets}`
    : "Pendiente";
  const instruction = getProductionInstruction(order, table, palletLabel);
  const tone = getTableTone(order, table);

  return (
    <section className={`production-order-hero ${tone}`} aria-label="Orden activa">
      <div className="production-order-main">
        <div>
          <p className="eyebrow">Orden activa · Fase {phase} de 5</p>
          <h2>{order.orderNumber}</h2>
          <p>{order.productNumber} · {order.productDescription} · Lote {order.lotNumber}</p>
        </div>
        <div className="production-order-progress" aria-label={`${progress} por ciento completado`}>
          <strong>{order.goodQuantity}<small> / {order.targetQuantity} uds.</small></strong>
          <span>{progress}%</span>
        </div>
      </div>

      <div className="order-progress-track" aria-hidden="true">
        <span style={{ width: `${progress}%` }} />
      </div>

      <div className="production-order-facts">
        <div><small>Palé actual</small><strong>{palletLabel}</strong></div>
        <div><small>Unidades restantes</small><strong>{remaining}</strong></div>
        <div><small>Formato</small><strong>{table ? `${table.palletFormatCode} · ${table.unitsPerPallet} uds.` : "Pendiente"}</strong></div>
        <div><small>Línea</small><strong>{table ? formatTableState(table.state) : "Identificando equipo"}</strong></div>
      </div>

      <div className="production-next-action" role="status" aria-live="polite">
        <span className="production-pulse" aria-hidden="true" />
        <div><small>Estado y siguiente acción</small><strong>{instruction}</strong></div>
        {order.state === "PENDIENTE_CIERRE" && (
          <button type="button" onClick={onComplete} disabled={busy}>
            {busy ? "Finalizando…" : "Finalizar orden"}
          </button>
        )}
      </div>
    </section>
  );
}

function ProductionTimeStrip({
  table,
  order,
  totalElapsedSeconds,
  productiveSeconds,
  stoppedSeconds,
}: {
  table: ProductionTableState | null;
  order: ProductionOrder;
  totalElapsedSeconds: number;
  productiveSeconds: number;
  stoppedSeconds: number;
}) {
  return (
    <section className="production-time-strip" aria-label="Tiempos de producción">
      <div className="primary-time"><small>Tiempo global de mesa</small><strong>{formatDuration(totalElapsedSeconds)}</strong></div>
      <div><small>Productivo</small><strong>{formatDuration(productiveSeconds)}</strong></div>
      <div><small>Parado</small><strong>{formatDuration(stoppedSeconds)}</strong></div>
      <div><small>Ruta NAV</small><strong>{formatMinutes(order.runTimeMinutes)}</strong></div>
      <div><small>Comparación</small><strong>{formatRouteComparison(productiveSeconds, order.runTimeMinutes)}</strong></div>
      <div><small>Ritmo teórico actual</small><strong>{table ? `${formatCapacity(table.currentTheoreticalCapacityPerHour)} u/h` : "—"}</strong></div>
    </section>
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

function secondsBetween(start: string, end: string): number {
  const startMs = Date.parse(start);
  const endMs = Date.parse(end);
  if (!Number.isFinite(startMs) || !Number.isFinite(endMs)) return 0;
  return Math.max(0, Math.floor((endMs - startMs) / 1_000));
}

function formatMinutes(value: number): string {
  if (!Number.isFinite(value) || value <= 0) return "No disponible";
  const totalSeconds = Math.round(value * 60);
  const hours = Math.floor(totalSeconds / 3_600);
  const minutes = Math.floor((totalSeconds % 3_600) / 60);
  return hours > 0 ? `${hours} h ${String(minutes).padStart(2, "0")} min` : `${minutes} min`;
}

function formatRouteComparison(productive: number, routeMinutes: number): string {
  const target = routeMinutes * 60;
  if (!Number.isFinite(target) || target <= 0) return "No disponible";
  const percentage = Math.round(productive * 100 / target);
  return `${percentage}% del tiempo NAV`;
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

function operatorActionNotice(action: OperatorActionKind): string {
  if (action === "EXIT") return "Salida registrada. Capacidad actualizada por el servidor.";
  if (action === "RESUME") return "Operario reincorporado. El tiempo individual vuelve a avanzar.";
  return "Pausa registrada. El acumulado individual queda detenido.";
}

function getProductionPhase(
  activeStep: number,
  order: ProductionOrder | null,
  table: ProductionTableState | null,
): number {
  if (activeStep < 3) return 1;
  if (!table) return 2;
  if (order?.state === "PENDIENTE_CIERRE") return 5;
  const recovery = table.latestPalletRecovery;
  if (
    recovery
    && (recovery.navState !== "CONFIRMADA"
      || !["LISTA", "IMPRESA"].includes(recovery.labelState ?? ""))
  ) return 4;
  return table.operators.length === 0 && order?.goodQuantity === 0 ? 2 : 3;
}

function getProductionInstruction(
  order: ProductionOrder,
  table: ProductionTableState | null,
  palletLabel: string,
): string {
  if (order.state === "PENDIENTE_CIERRE") {
    return "Todos los palés están completados. Finaliza la orden para liberar la línea.";
  }
  if (!table) return "Esperando operarios · Acerca la primera tarjeta RFID.";
  const recovery = table.latestPalletRecovery;
  if (recovery?.navState === "RESULTADO_DESCONOCIDO" || recovery?.labelState === "ERROR") {
    return "El último palé necesita revisión · Utiliza las acciones de recuperación.";
  }
  if (recovery && recovery.navState !== "CONFIRMADA") {
    return `Palé ${recovery.palletNumber} cerrado · Conciliando con NAV sin reenviar la salida.`;
  }
  if (recovery && !["LISTA", "IMPRESA"].includes(recovery.labelState ?? "")) {
    return `NAV confirmado para el palé ${recovery.palletNumber} · Preparando la etiqueta.`;
  }
  if (table.activeResources === 0) {
    return "Mesa sin operarios · Identifica un operario para continuar.";
  }
  return `Produciendo · El siguiente paso es cerrar el palé ${palletLabel}.`;
}

function getTableTone(
  order: ProductionOrder,
  table: ProductionTableState | null,
): "green" | "amber" | "blue" | "red" | "gray" {
  if (order.state === "PENDIENTE_CIERRE") return "amber";
  if (!table) return "gray";
  const recovery = table.latestPalletRecovery;
  if (recovery?.navState === "RESULTADO_DESCONOCIDO" || recovery?.labelState === "ERROR") return "red";
  if (recovery && (recovery.navState !== "CONFIRMADA"
    || !["LISTA", "IMPRESA"].includes(recovery.labelState ?? ""))) return "blue";
  if (table.activeResources === 0) return "gray";
  return "green";
}

function PalletIcon() {
  return (
    <svg
      className="pallet-action-icon"
      viewBox="0 0 24 24"
      aria-hidden="true"
      focusable="false"
    >
      <path d="M4 5h16v4H4zM5 11h4v5H5zm5 0h4v5h-4zm5 0h4v5h-4zM3 18h18v2H3z" />
    </svg>
  );
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
