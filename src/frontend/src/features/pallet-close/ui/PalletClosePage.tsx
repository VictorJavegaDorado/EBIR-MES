import { useEffect, useRef, useState, type FormEvent } from "react";
import { closePallet, PalletCloseApiError } from "../api/closePallet";
import {
  getPalletCloseOptions,
  PalletCloseOptionsApiError,
} from "../api/getPalletCloseOptions";
import type {
  ClosePalletCommand,
  PalletCloseOptions,
  PalletCloseViewState,
  PartialReason,
} from "../model/palletClose";
import type { IdentifiedLine } from "../../line-identification/model/lineIdentification";

type FormValues = {
  reservationId: string;
  goodQuantity: string;
  closedByEmployeeId: string;
  authorizingSupervisorId: string;
  isPartial: boolean;
  partialReason: PartialReason;
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
  partialReason: "FIN_TURNO",
};

type OptionsState =
  | { status: "idle" }
  | { status: "loading" }
  | { status: "ready"; options: PalletCloseOptions }
  | { status: "error"; code: string };

type Props = {
  line?: IdentifiedLine;
};

export function PalletClosePage({ line }: Props = {}) {
  const [form, setForm] = useState<FormValues>(initialForm);
  const [viewState, setViewState] = useState<PalletCloseViewState>({
    status: "idle",
  });
  const [optionsState, setOptionsState] = useState<OptionsState>({
    status: "idle",
  });
  const activeRequest = useRef<AbortController | null>(null);
  const attempt = useRef<Attempt | null>(null);

  useEffect(() => {
    return () => activeRequest.current?.abort();
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
        setOptionsState({ status: "ready", options });
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
  }, [line]);

  function reloadOptions() {
    if (!line) {
      return;
    }
    const request = new AbortController();
    setOptionsState({ status: "loading" });
    getPalletCloseOptions(line.id, request.signal)
      .then((options) => setOptionsState({ status: "ready", options }))
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
      (form.authorizingSupervisorId.trim() && supervisor === null) ||
      (form.isPartial && supervisor === null)
    ) {
      setViewState({
        status: "error",
        code: "PALLET_CLOSE_INPUT_INVALID",
        message:
          form.isPartial && supervisor === null
            ? "Un cierre parcial requiere un supervisor autorizador."
            : "Revisa la reserva, la cantidad y los identificadores de empleado.",
        retryable: false,
      });
      return;
    }

    const requestWithoutCorrelation = {
      goodQuantity,
      closedByEmployeeId,
      authorizingSupervisorId: supervisor,
      isPartial: form.isPartial,
      partialReason: form.isPartial ? form.partialReason : null,
    };
    const fingerprint = JSON.stringify({
      reservationId,
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
    setViewState({ status: "loading", correlationId });

    try {
      const pallet = await closePallet(reservationId, command, request.signal);
      if (activeRequest.current !== request) {
        return;
      }

      setViewState({ status: "closed", pallet });
    } catch (error) {
      if (request.signal.aborted || activeRequest.current !== request) {
        return;
      }

      if (error instanceof PalletCloseApiError) {
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
      if (activeRequest.current === request) {
        activeRequest.current = null;
      }
    }
  }

  function prepareAnotherClose() {
    activeRequest.current?.abort();
    activeRequest.current = null;
    attempt.current = null;
    setForm(initialForm);
    setViewState({ status: "idle" });
  }

  return (
    <div className="pallet-close-page">
      <section className="pallet-close-header">
        <div>
          <p className="eyebrow">Paletización · operación manual</p>
          <h1>Cierra un palé con reintento seguro</h1>
          <p className="welcome-description">
            {line
              ? `Línea ${line.code} · ${line.name}. `
              : ""}
            Selecciona la reserva y los datos del cierre. Si la respuesta se
            pierde, vuelve a enviar sin cambiar los campos.
          </p>
        </div>
        <div className="idempotency-badge">
          <strong>Correlación protegida</strong>
          El terminal conserva la misma clave mientras la solicitud no cambie.
        </div>
      </section>

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
                Cargando reservas y empleados…
              </div>
            )}
            {optionsState.status === "error" && (
              <div className="pallet-options-status error full" role="alert">
                <span>
                  No se pueden cargar las opciones de cierre.{" "}
                  <code>{optionsState.code}</code>
                </span>
                <button type="button" onClick={reloadOptions}>
                  Reintentar carga
                </button>
              </div>
            )}
            <div className="pallet-field">
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
            </div>

            <div className="pallet-field">
              <label htmlFor="good-quantity">Cantidad buena</label>
              <input
                id="good-quantity"
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

            <div className="pallet-field">
              <label htmlFor="closed-by-employee-id">Empleado que cierra</label>
              {optionsState.status === "ready" ? (
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
              <small>Identificador MES del operario o supervisor.</small>
            </div>

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
              <small>Opcional; el backend indicará cuándo es obligatorio.</small>
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
                  <option value="FIN_TURNO">Fin de turno</option>
                  <option value="FALTA_MATERIAL">Falta de material</option>
                  <option value="ULTIMO_PALET">Último palé</option>
                </select>
              </div>
            )}
          </div>

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
                : "Confirmar cierre"}
            <span aria-hidden="true">→</span>
          </button>

          <p className="pallet-correlation">
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
          </p>
        </form>

        <aside className="pallet-close-result" aria-live="polite">
          <div className="card-heading compact">
            <span className="step-number muted">02</span>
            <div>
              <h2>Resultado</h2>
              <p>Confirmación del contrato MES</p>
            </div>
          </div>

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
                El MES ha confirmado el cierre. La interfaz no contacta NAV ni
                periféricos.
              </p>
              <code>{viewState.pallet.correlationId}</code>
              <button
                className="secondary-action"
                type="button"
                onClick={prepareAnotherClose}
              >
                Preparar otro cierre
              </button>
            </div>
          )}
        </aside>
      </section>

      <section className="pallet-safeguards" aria-label="Garantías del cierre">
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
      </section>
    </div>
  );
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
