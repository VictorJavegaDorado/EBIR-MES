import { useEffect, useRef, useState, type FormEvent } from "react";
import { closePallet, PalletCloseApiError } from "../api/closePallet";
import {
  getPalletCloseOptions,
  PalletCloseOptionsApiError,
} from "../api/getPalletCloseOptions";
import type {
  ClosePalletCommand,
  PalletCloseOptions,
  PalletEmployeeOption,
  PalletCloseViewState,
  PartialReason,
} from "../model/palletClose";
import type { IdentifiedLine } from "../../line-identification/model/lineIdentification";
import { PalletLabelReprint } from "../../label-reprint/ui/PalletLabelReprint";
import {
  identifyEmployeeByRfid,
  RfidIdentificationApiError,
  type IdentifiedEmployee,
} from "../../production-flow/api/identifyEmployeeByRfid";

type FormValues = {
  reservationId: string;
  goodQuantity: string;
  closedByEmployeeId: string;
  authorizingSupervisorId: string;
  isPartial: boolean;
  partialReason: PartialReason | "";
};

type Attempt = {
  fingerprint: string;
  correlationId: string;
};

const initialForm: FormValues = {
  reservationId: "",
  goodQuantity: "",
  closedByEmployeeId: "",
  authorizingSupervisorId: "",
  isPartial: false,
  partialReason: "",
};

type OptionsState =
  | { status: "idle" }
  | { status: "loading" }
  | { status: "ready"; options: PalletCloseOptions }
  | { status: "error"; code: string };

type PendingClose = {
  reservationId: number;
  goodQuantity: number;
  closedByEmployeeId: number;
  isPartial: boolean;
  partialReason: PartialReason | null;
};

type SupervisorChallenge =
  | ({ status: "scanning"; credential: string; error?: string } & PendingClose)
  | ({ status: "identifying" } & PendingClose)
  | ({ status: "identified"; employee: IdentifiedEmployee } & PendingClose);

type Props = {
  line?: IdentifiedLine;
  palletFormatCode?: string;
  selectedEmployee?: PalletEmployeeOption;
  onCancel?: () => void;
  onBusyChange?: (isBusy: boolean) => void;
  onPalletClosed?: (quantity: number) => void;
};

export function PalletClosePage({
  line,
  palletFormatCode = "POK",
  selectedEmployee,
  onCancel,
  onBusyChange,
  onPalletClosed,
}: Props = {}) {
  const [form, setForm] = useState<FormValues>(initialForm);
  const [viewState, setViewState] = useState<PalletCloseViewState>({
    status: "idle",
  });
  const [optionsState, setOptionsState] = useState<OptionsState>({
    status: "idle",
  });
  const [supervisorChallenge, setSupervisorChallenge] =
    useState<SupervisorChallenge | null>(null);
  const activeRequest = useRef<AbortController | null>(null);
  const attempt = useRef<Attempt | null>(null);
  const onBusyChangeRef = useRef(onBusyChange);

  useEffect(() => {
    onBusyChangeRef.current = onBusyChange;
  }, [onBusyChange]);

  useEffect(() => {
    return () => {
      activeRequest.current?.abort();
      onBusyChangeRef.current?.(false);
    };
  }, []);

  useEffect(() => {
    if (!line) {
      setOptionsState({ status: "idle" });
      return;
    }

    const request = new AbortController();
    setOptionsState({ status: "loading" });
    getPalletCloseOptions(line.id, request.signal)
      .then((options) => {
        acceptOptions(options);
      })
      .catch((error: unknown) => {
        if (request.signal.aborted) {
          return;
        }
        setOptionsState({
          status: "error",
          code:
            error instanceof PalletCloseOptionsApiError
              ? error.code
              : "PALLET_CLOSE_OPTIONS_UNAVAILABLE",
        });
      });
    return () => request.abort();
  }, [line, selectedEmployee?.id]);

  function acceptOptions(options: PalletCloseOptions) {
    if (line && options.reservations.length > 1) {
      setOptionsState({ status: "error", code: "PALLET_CLOSE_OPTIONS_AMBIGUOUS" });
      return;
    }

    if (
      selectedEmployee
      && !options.employees.some((employee) => employee.id === selectedEmployee.id)
    ) {
      setOptionsState({
        status: "error",
        code: "PALLET_CLOSE_EMPLOYEE_NOT_AVAILABLE",
      });
      setForm((current) => ({ ...current, closedByEmployeeId: "" }));
      return;
    }

    const reservation = options.reservations[0];
    setOptionsState({ status: "ready", options });
    setForm((current) => ({
      ...current,
      reservationId: reservation ? String(reservation.id) : "",
      goodQuantity: reservation ? String(reservation.reservedQuantity) : "",
      closedByEmployeeId: selectedEmployee
        ? String(selectedEmployee.id)
        : options.employees.some(
            (employee) => String(employee.id) === current.closedByEmployeeId,
          )
          ? current.closedByEmployeeId
          : options.employees.length === 1
            ? String(options.employees[0].id)
            : "",
      authorizingSupervisorId: "",
      isPartial: false,
      partialReason: "",
    }));
  }

  function reloadOptions() {
    if (!line) {
      return;
    }
    const request = new AbortController();
    setOptionsState({ status: "loading" });
    getPalletCloseOptions(line.id, request.signal)
      .then(acceptOptions)
      .catch((error: unknown) =>
        setOptionsState({
          status: "error",
          code:
            error instanceof PalletCloseOptionsApiError
              ? error.code
              : "PALLET_CLOSE_OPTIONS_UNAVAILABLE",
        }),
      );
  }

  function updateForm(patch: Partial<FormValues>) {
    activeRequest.current?.abort();
    activeRequest.current = null;
    attempt.current = null;
    setForm((current) => ({ ...current, ...patch }));
    setViewState({ status: "idle" });
  }

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();

    const reservationId = parsePositiveInteger(form.reservationId);
    const goodQuantity = parsePositiveInteger(form.goodQuantity);
    const closedByEmployeeId = parsePositiveInteger(form.closedByEmployeeId);
    const supervisor = form.authorizingSupervisorId.trim()
      ? parsePositiveInteger(form.authorizingSupervisorId)
      : null;

    if (
      reservationId === null ||
      goodQuantity === null ||
      closedByEmployeeId === null ||
      (form.authorizingSupervisorId.trim() && supervisor === null)
    ) {
      setViewState({
        status: "error",
        code: "PALLET_CLOSE_INPUT_INVALID",
        message: line
          ? "Revisa la cantidad y el operario que cierra el palet."
          : "Revisa la reserva, la cantidad y los identificadores de empleado.",
        retryable: false,
      });
      return;
    }

    const selected = optionsState.status === "ready"
      ? optionsState.options.reservations.find(
          (reservation) => reservation.id === reservationId,
        )
      : null;
    const isPartial = line && selected
      ? goodQuantity !== selected.reservedQuantity
      : form.isPartial;
    if (isPartial && !form.partialReason) {
      setViewState({
        status: "error",
        code: "PALLET_PARTIAL_REASON_REQUIRED",
        message: "Selecciona el motivo de la cantidad distinta.",
        retryable: false,
      });
      return;
    }

    await executeClose({
      reservationId,
      goodQuantity,
      closedByEmployeeId,
      isPartial,
      partialReason: isPartial ? form.partialReason as PartialReason : null,
    }, supervisor);
  }

  async function executeClose(
    pending: PendingClose,
    supervisor: number | null,
  ) {
    const requestWithoutCorrelation = {
      goodQuantity: pending.goodQuantity,
      closedByEmployeeId: pending.closedByEmployeeId,
      authorizingSupervisorId: supervisor,
      isPartial: pending.isPartial,
      partialReason: pending.partialReason,
    };
    const fingerprint = JSON.stringify({
      reservationId: pending.reservationId,
      ...requestWithoutCorrelation,
    });

    if (!attempt.current || attempt.current.fingerprint !== fingerprint) {
      attempt.current = {
        fingerprint,
        correlationId: createCorrelationId(),
      };
    }

    const correlationId = attempt.current.correlationId;
    const command: ClosePalletCommand = {
      ...requestWithoutCorrelation,
      correlationId,
    };

    activeRequest.current?.abort();
    const request = new AbortController();
    activeRequest.current = request;
    onBusyChangeRef.current?.(true);
    setViewState({ status: "loading", correlationId });
    let keepOuterDialogBusy = false;

    try {
      const pallet = await closePallet(
        pending.reservationId,
        command,
        request.signal,
      );
      if (activeRequest.current !== request) {
        return;
      }

      setSupervisorChallenge(null);
      setViewState({ status: "closed", pallet });
      onPalletClosed?.(pending.goodQuantity);
    } catch (error) {
      if (request.signal.aborted || activeRequest.current !== request) {
        return;
      }

      if (error instanceof PalletCloseApiError) {
        if (
          line
          && supervisor === null
          && error.code === "PALLET_CLOSE_SUPERVISOR_REQUIRED"
        ) {
          attempt.current = null;
          keepOuterDialogBusy = true;
          setViewState({ status: "idle" });
          setSupervisorChallenge({
            status: "scanning",
            credential: "",
            ...pending,
          });
          return;
        }

        setViewState({
          status: "error",
          code: error.code,
          message: error.message,
          retryable: error.retryable,
          correlationId,
        });
        return;
      }

      setViewState({
        status: "error",
        code: "PALLET_CLOSE_UNAVAILABLE",
        message:
          "No se puede contactar con el servicio de cierre. Reintenta la misma solicitud.",
        retryable: true,
        correlationId,
      });
    } finally {
      if (!keepOuterDialogBusy) {
        onBusyChangeRef.current?.(false);
      }
      if (activeRequest.current === request) {
        activeRequest.current = null;
      }
    }
  }

  async function handleSupervisorScan(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!supervisorChallenge || supervisorChallenge.status !== "scanning") {
      return;
    }

    const credential = supervisorChallenge.credential.trim();
    if (!credential) {
      setSupervisorChallenge({
        ...supervisorChallenge,
        error: "Acerca la tarjeta RFID del supervisor.",
      });
      return;
    }

    const pending = asPendingClose(supervisorChallenge);
    const request = new AbortController();
    activeRequest.current?.abort();
    activeRequest.current = request;
    setSupervisorChallenge({ status: "identifying", ...pending });

    try {
      const employee = await identifyEmployeeByRfid(
        credential,
        request.signal,
      );
      if (activeRequest.current !== request) {
        return;
      }

      const isActiveSupervisor = optionsState.status === "ready"
        && optionsState.options.supervisors.some(
          (supervisorOption) => supervisorOption.id === employee.employeeId,
        );
      if (!isActiveSupervisor) {
        setSupervisorChallenge({
          status: "scanning",
          credential: "",
          error: "La tarjeta no pertenece a un supervisor activo.",
          ...pending,
        });
        return;
      }

      setSupervisorChallenge({
        status: "identified",
        employee,
        ...pending,
      });
    } catch (error) {
      if (request.signal.aborted || activeRequest.current !== request) {
        return;
      }

      setSupervisorChallenge({
        status: "scanning",
        credential: "",
        error: error instanceof RfidIdentificationApiError
          ? `No se ha podido validar la tarjeta. ${error.code}`
          : "No se puede contactar con el lector RFID. Prueba de nuevo.",
        ...pending,
      });
    } finally {
      if (activeRequest.current === request) {
        activeRequest.current = null;
      }
    }
  }

  function cancelSupervisorChallenge() {
    activeRequest.current?.abort();
    activeRequest.current = null;
    setSupervisorChallenge(null);
    setViewState({ status: "idle" });
    onBusyChangeRef.current?.(false);
  }

  async function confirmSupervisorClose() {
    if (!supervisorChallenge || supervisorChallenge.status !== "identified") {
      return;
    }

    const pending = asPendingClose(supervisorChallenge);
    const supervisorId = supervisorChallenge.employee.employeeId;
    setForm((current) => ({
      ...current,
      authorizingSupervisorId: String(supervisorId),
    }));
    setSupervisorChallenge(null);
    attempt.current = null;
    await executeClose(pending, supervisorId);
  }

  function prepareAnotherClose() {
    activeRequest.current?.abort();
    activeRequest.current = null;
    attempt.current = null;
    setForm(initialForm);
    setViewState({ status: "idle" });
    reloadOptions();
  }

  const selectedReservation = optionsState.status === "ready"
    ? optionsState.options.reservations.find(
        (reservation) => String(reservation.id) === form.reservationId,
      ) ?? null
    : null;
  const previewQuantity = parsePositiveInteger(form.goodQuantity)
    ?? selectedReservation?.reservedQuantity
    ?? null;

  return (
    <div className="pallet-close-page">
      {!line && <section className="pallet-close-header">
        <div>
          <p className="eyebrow">Paletización · operación manual</p>
          <h1>Cierra un palé con reintento seguro</h1>
          <p className="welcome-description">
            Selecciona la reserva y los datos del cierre. Si la respuesta se
            pierde, vuelve a enviar sin cambiar los campos.
          </p>
        </div>
        <div className="idempotency-badge">
          <strong>Correlación protegida</strong>
          El terminal conserva la misma clave mientras la solicitud no cambie.
        </div>
      </section>}

      <section className="pallet-close-layout">
        <form
          className="pallet-close-form"
          onSubmit={handleSubmit}
          aria-busy={viewState.status === "loading"}
        >
          <div className="card-heading">
            <span className="step-number">01</span>
            <div>
              <h2>Datos del cierre</h2>
              <p>Identificadores MES y cantidad buena confirmada.</p>
            </div>
          </div>

          <div className="pallet-close-fields">
            {optionsState.status === "loading" && (
              <div className="pallet-options-status full" role="status">
                Preparando el palet y los operarios…
              </div>
            )}
            {optionsState.status === "error" && (
              <div className="pallet-options-status error full" role="alert">
                <span>
                  No se puede preparar el cierre del palet.{" "}
                  <code>{optionsState.code}</code>
                </span>
                <button type="button" onClick={reloadOptions}>
                  Reintentar carga
                </button>
              </div>
            )}
            {line ? (
              <div className="pallet-field pallet-current-summary">
                <span>Formato y cantidad propuesta</span>
                {selectedReservation ? (
                  <strong>{palletFormatCode} · {selectedReservation.reservedQuantity} unidades</strong>
                ) : (
                  <strong>Sin palet pendiente</strong>
                )}
                <small>MES prepara automáticamente el siguiente palet.</small>
              </div>
            ) : <div className="pallet-field">
              <label htmlFor="reservation-id">Reserva de palé</label>
              {optionsState.status === "ready" ? (
                <select
                  id="reservation-id"
                  value={form.reservationId}
                  onChange={(event) => {
                    const reservation = optionsState.options.reservations.find(
                      (item) => String(item.id) === event.target.value,
                    );
                    updateForm({
                      reservationId: event.target.value,
                      goodQuantity: reservation
                        ? String(reservation.reservedQuantity)
                        : "",
                    });
                  }}
                  aria-required="true"
                >
                  <option value="">Selecciona una reserva</option>
                  {optionsState.options.reservations.map((reservation) => (
                    <option key={reservation.id} value={reservation.id}>
                      {reservation.orderNumber} · Reserva {reservation.id} ·{" "}
                      {reservation.reservedQuantity} uds.
                    </option>
                  ))}
                </select>
              ) : (
                <input
                  id="reservation-id"
                  inputMode="numeric"
                  min="1"
                  step="1"
                  value={form.reservationId}
                  onChange={(event) =>
                    updateForm({ reservationId: event.target.value })
                  }
                  aria-required="true"
                  disabled={Boolean(line)}
                />
              )}
              <small>Identificador de la reserva activa.</small>
            </div>}

            <div className="pallet-field">
              <label htmlFor="good-quantity">Cantidad buena</label>
              <input
                id="good-quantity"
                autoFocus={Boolean(selectedEmployee)}
                inputMode="numeric"
                min="1"
                step="1"
                value={form.goodQuantity}
                onChange={(event) =>
                  updateForm({ goodQuantity: event.target.value })
                }
                aria-required="true"
              />
              <small>Unidades verificadas por el operario.</small>
            </div>

            <div
              className="pallet-field"
              role={selectedEmployee ? "group" : undefined}
              aria-labelledby={selectedEmployee ? "closed-by-employee-label" : undefined}
            >
              {selectedEmployee ? (
                <span className="pallet-field-label" id="closed-by-employee-label">
                  Empleado que cierra
                </span>
              ) : (
                <label htmlFor="closed-by-employee-id">Empleado que cierra</label>
              )}
              {selectedEmployee ? (
                <div
                  className="pallet-selected-employee"
                  aria-describedby="closed-by-employee-help"
                >
                  <span aria-hidden="true">
                    {selectedEmployee.name
                      .split(/\s+/)
                      .filter(Boolean)
                      .slice(0, 2)
                      .map((part) => part[0]?.toUpperCase())
                      .join("") || "OP"}
                  </span>
                  <div>
                    <strong>{selectedEmployee.name}</strong>
                    <small>{selectedEmployee.code}</small>
                  </div>
                </div>
              ) : optionsState.status === "ready" ? (
                <select
                  id="closed-by-employee-id"
                  value={form.closedByEmployeeId}
                  onChange={(event) =>
                    updateForm({ closedByEmployeeId: event.target.value })
                  }
                  aria-required="true"
                >
                  <option value="">Selecciona un empleado</option>
                  {optionsState.options.employees.map((employee) => (
                    <option key={employee.id} value={employee.id}>
                      {employee.name} · {employee.code}
                    </option>
                  ))}
                </select>
              ) : (
                <input
                  id="closed-by-employee-id"
                  inputMode="numeric"
                  min="1"
                  step="1"
                  value={form.closedByEmployeeId}
                  onChange={(event) =>
                    updateForm({ closedByEmployeeId: event.target.value })
                  }
                  aria-required="true"
                  disabled={Boolean(line)}
                />
              )}
              <small id={selectedEmployee ? "closed-by-employee-help" : undefined}>
                {selectedEmployee
                  ? "El cierre quedará asociado a este operario."
                  : "Cualquier operario activo de la mesa puede cerrarlo."}
              </small>
            </div>

            {line ? <>
              {selectedReservation
                && previewQuantity !== selectedReservation.reservedQuantity && (
                <details className="pallet-advanced full" open>
                  <summary>Cantidad distinta</summary>
                  <div className="pallet-field">
                    <label htmlFor="partial-reason">Motivo de la cantidad distinta</label>
                    <select
                      id="partial-reason"
                      value={form.partialReason}
                      onChange={(event) => updateForm({
                        partialReason: event.target.value as PartialReason,
                      })}
                    >
                      <option value="">Selecciona un motivo</option>
                      <option value="FIN_TURNO">Fin de turno</option>
                      <option value="FALTA_MATERIAL">Falta de material</option>
                      <option value="ULTIMO_PALET">Último palet</option>
                    </select>
                  </div>
                </details>
              )}
            </> : <>
            <div className="pallet-field">
              <label htmlFor="supervisor-id">Supervisor autorizador</label>
              {optionsState.status === "ready" ? (
                <select
                  id="supervisor-id"
                  value={form.authorizingSupervisorId}
                  onChange={(event) =>
                    updateForm({
                      authorizingSupervisorId: event.target.value,
                    })
                  }
                >
                  <option value="">Sin supervisor</option>
                  {optionsState.options.supervisors.map((employee) => (
                    <option key={employee.id} value={employee.id}>
                      {employee.name} · {employee.code}
                    </option>
                  ))}
                </select>
              ) : (
                <input
                  id="supervisor-id"
                  inputMode="numeric"
                  min="1"
                  step="1"
                  value={form.authorizingSupervisorId}
                  onChange={(event) =>
                    updateForm({
                      authorizingSupervisorId: event.target.value,
                    })
                  }
                  disabled={Boolean(line)}
                />
              )}
              <small>El servidor lo exige únicamente para el último palé.</small>
            </div>

            <label className="partial-toggle" htmlFor="is-partial">
              <span>
                Cierre parcial
                <small>Actívalo si la reserva no se completa.</small>
              </span>
              <input
                id="is-partial"
                type="checkbox"
                checked={form.isPartial}
                onChange={(event) =>
                  updateForm({ isPartial: event.target.checked })
                }
              />
            </label>

            {form.isPartial && (
              <div className="pallet-field full">
                <label htmlFor="partial-reason">Motivo del cierre parcial</label>
                <select
                  id="partial-reason"
                  value={form.partialReason}
                  onChange={(event) =>
                    updateForm({
                      partialReason: event.target.value as PartialReason,
                    })
                  }
                >
                  <option value="">Selecciona un motivo</option>
                  <option value="FIN_TURNO">Fin de turno</option>
                  <option value="FALTA_MATERIAL">Falta de material</option>
                  <option value="ULTIMO_PALET">Último palé</option>
                </select>
              </div>
            )}
            </>}
          </div>

          <div className="pallet-form-actions">
            {onCancel && (
              <button
                type="button"
                className="pallet-cancel-action"
                onClick={onCancel}
                disabled={viewState.status === "loading"}
              >
                Cancelar
              </button>
            )}
            <button
              className="primary-action pallet-submit"
              type="submit"
              disabled={
                viewState.status === "loading" ||
                (Boolean(line) && optionsState.status !== "ready") ||
                (viewState.status === "error" && !viewState.retryable)
              }
            >
              {viewState.status === "loading"
                ? "Cerrando palé…"
                : viewState.status === "error" && viewState.retryable
                  ? "Reintentar cierre"
                  : viewState.status === "error"
                    ? "Revisa los datos para continuar"
                  : line ? "Cerrar palet" : "Confirmar cierre"}
              <span aria-hidden="true">→</span>
            </button>
          </div>

          {!line && <p className="pallet-correlation">
            {viewState.status === "idle"
              ? "La correlación se generará al confirmar."
              : "Correlación del intento: "}
            {viewState.status !== "idle" && (
              <code>
                {viewState.status === "closed"
                  ? viewState.pallet.correlationId
                  : viewState.correlationId}
              </code>
            )}
          </p>}
        </form>

        <aside className="pallet-close-result" aria-live="polite">
          <div className="card-heading compact">
            <span className="step-number muted">02</span>
            <div>
              <h2>Resultado</h2>
              <p>Confirmación y estado de fondo</p>
            </div>
          </div>

          {selectedReservation && previewQuantity && (
            <PalletLabelPreview
              reservation={selectedReservation}
              quantity={previewQuantity}
            />
          )}

          {viewState.status === "idle" && (
            <div className="pallet-result-panel">
              <span aria-hidden="true">P</span>
              <strong>Esperando confirmación</strong>
              <p>Completa los datos para solicitar el cierre.</p>
            </div>
          )}

          {viewState.status === "loading" && (
            <div className="pallet-result-panel" role="status">
              <span className="loading-mark" aria-hidden="true" />
              <strong>Cierre en curso</strong>
              <p>No cambies los datos mientras se confirma la operación.</p>
            </div>
          )}

          {viewState.status === "error" && (
            <div className="pallet-result-panel error" role="alert">
              <span aria-hidden="true">!</span>
              <strong>No se ha confirmado el cierre</strong>
              <p>{viewState.message}</p>
              <code>{viewState.code}</code>
            </div>
          )}

          {viewState.status === "closed" && (
            <div className="pallet-result-panel success">
              <span aria-hidden="true">✓</span>
              <strong>Palé {viewState.pallet.id} cerrado</strong>
              <p>
                El MES ha confirmado el cierre. NAV y la impresión continúan
                en segundo plano.
              </p>
              <code>{viewState.pallet.correlationId}</code>
              <PalletLabelReprint
                palletId={viewState.pallet.id}
                supervisors={
                  optionsState.status === "ready"
                    ? optionsState.options.supervisors
                    : []
                }
                defaultSupervisorId={
                  selectedEmployee
                    && optionsState.status === "ready"
                    && optionsState.options.supervisors.some(
                      (supervisor) => supervisor.id === selectedEmployee.id,
                    )
                    ? selectedEmployee.id
                    : undefined
                }
              />
              <div className="pallet-result-actions">
                {onCancel && (
                  <button
                    className="secondary-action"
                    type="button"
                    onClick={onCancel}
                  >
                    Volver a la mesa
                  </button>
                )}
                <button
                  className="secondary-action"
                  type="button"
                  onClick={prepareAnotherClose}
                >
                  Cerrar siguiente palet
                </button>
              </div>
            </div>
          )}
        </aside>
      </section>

      {supervisorChallenge && (
        <div className="supervisor-rfid-backdrop">
          <section
            className="supervisor-rfid-dialog"
            role="dialog"
            aria-modal="true"
            aria-labelledby="supervisor-rfid-title"
          >
            <header>
              <p className="eyebrow">Autorización obligatoria</p>
              <h2 id="supervisor-rfid-title">Último palet</h2>
              <p>
                Acerca la tarjeta RFID de un supervisor para autorizar el
                cierre definitivo de la orden.
              </p>
            </header>

            {supervisorChallenge.status === "scanning" && (
              <form onSubmit={handleSupervisorScan}>
                <label htmlFor="supervisor-rfid-credential">
                  Tarjeta RFID del supervisor
                </label>
                <input
                  id="supervisor-rfid-credential"
                  type="password"
                  autoComplete="off"
                  autoFocus
                  value={supervisorChallenge.credential}
                  onChange={(event) => {
                    const credential = event.target.value;
                    setSupervisorChallenge((current) =>
                      current?.status === "scanning"
                        ? { ...current, credential, error: undefined }
                        : current,
                    );
                  }}
                />
                <small>
                  La credencial no se muestra ni se incluye en el cierre.
                </small>
                {supervisorChallenge.error && (
                  <p className="supervisor-rfid-error" role="alert">
                    {supervisorChallenge.error}
                  </p>
                )}
                <div className="supervisor-rfid-actions">
                  <button type="button" onClick={cancelSupervisorChallenge}>
                    Cancelar
                  </button>
                  <button className="primary-action" type="submit">
                    Validar tarjeta
                  </button>
                </div>
              </form>
            )}

            {supervisorChallenge.status === "identifying" && (
              <div className="supervisor-rfid-status" role="status">
                <span className="loading-mark" aria-hidden="true" />
                <strong>Validando supervisor…</strong>
              </div>
            )}

            {supervisorChallenge.status === "identified" && (
              <div className="supervisor-rfid-confirmation">
                <p>Supervisor identificado</p>
                <strong>{supervisorChallenge.employee.fullName}</strong>
                <span>{supervisorChallenge.employee.navEmployeeCode}</span>
                <div className="supervisor-rfid-actions">
                  <button type="button" onClick={cancelSupervisorChallenge}>
                    Cancelar
                  </button>
                  <button
                    className="primary-action"
                    type="button"
                    onClick={() => void confirmSupervisorClose()}
                  >
                    Autorizar y cerrar palet
                  </button>
                </div>
              </div>
            )}
          </section>
        </div>
      )}

      {!line && <section className="pallet-safeguards" aria-label="Garantías del cierre">
        <div>
          <strong>Reintento seguro</strong>
          Misma solicitud, misma correlación.
        </div>
        <div>
          <strong>Sin periféricos directos</strong>
          La interfaz no contacta NAV ni impresoras.
        </div>
        <div>
          <strong>Errores controlados</strong>
          Se muestran mensajes funcionales sin detalles SQL.
        </div>
      </section>}
    </div>
  );
}

function PalletLabelPreview({
  reservation,
  quantity,
}: {
  reservation: PalletCloseOptions["reservations"][number];
  quantity: number;
}) {
  return (
    <section className="pallet-label-preview" aria-label="Previsualización de etiqueta de palé">
      <p className="pallet-label-preview-title">Previsualización · 150 × 100 mm</p>
      <div className="pallet-label-sheet">
        <header>
          <strong className="pallet-label-logo">EBIR</strong>
          <strong className="pallet-label-group">{reservation.productPostingGroup}</strong>
        </header>
        <dl>
          <div><dt>Código</dt><dd>{reservation.productNumber}</dd></div>
          <div><dt>Artículo</dt><dd>{reservation.productDescription}</dd></div>
          <div><dt>Nº orden</dt><dd>{reservation.orderNumber}</dd></div>
          <div><dt>Cantidad</dt><dd>{quantity}</dd></div>
          <div><dt>Línea</dt><dd>{reservation.lineName}</dd></div>
        </dl>
      </div>
      <small>Vista segura: no envía trabajos a la impresora.</small>
    </section>
  );
}

function asPendingClose(challenge: SupervisorChallenge): PendingClose {
  return {
    reservationId: challenge.reservationId,
    goodQuantity: challenge.goodQuantity,
    closedByEmployeeId: challenge.closedByEmployeeId,
    isPartial: challenge.isPartial,
    partialReason: challenge.partialReason,
  };
}

function parsePositiveInteger(value: string): number | null {
  const normalized = value.trim();
  if (!/^\d+$/.test(normalized)) {
    return null;
  }

  const parsed = Number(normalized);
  return Number.isSafeInteger(parsed) && parsed > 0 ? parsed : null;
}

function createCorrelationId(): string {
  if (typeof globalThis.crypto.randomUUID === "function") {
    return globalThis.crypto.randomUUID();
  }

  const bytes = globalThis.crypto.getRandomValues(new Uint8Array(16));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  const hex = Array.from(bytes, (byte) =>
    byte.toString(16).padStart(2, "0"),
  ).join("");
  return [
    hex.slice(0, 8),
    hex.slice(8, 12),
    hex.slice(12, 16),
    hex.slice(16, 20),
    hex.slice(20),
  ].join("-");
}
