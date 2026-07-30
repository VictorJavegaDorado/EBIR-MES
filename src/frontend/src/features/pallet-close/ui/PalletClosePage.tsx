import { useEffect, useRef, useState, type FormEvent } from "react";
import { closePallet, PalletCloseApiError } from "../api/closePallet";
import type {
  ClosePalletCommand,
  PalletCloseViewState,
  PartialReason,
} from "../model/palletClose";

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

export function PalletClosePage() {
  const [form, setForm] = useState<FormValues>(initialForm);
  const [viewState, setViewState] = useState<PalletCloseViewState>({
    status: "idle",
  });
  const activeRequest = useRef<AbortController | null>(null);
  const attempt = useRef<Attempt | null>(null);

  useEffect(() => {
    return () => activeRequest.current?.abort();
  }, []);

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
        message:
          "Revisa la reserva, la cantidad y los identificadores de empleado.",
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
        correlationId: globalThis.crypto.randomUUID(),
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
          correlationId,
        });
        return;
      }

      setViewState({
        status: "error",
        code: "PALLET_CLOSE_UNAVAILABLE",
        message:
          "No se puede contactar con el servicio de cierre. Reintenta la misma solicitud.",
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
            Introduce la reserva y los datos del cierre. Si la respuesta se
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
            <div className="pallet-field">
              <label htmlFor="reservation-id">Reserva de palé</label>
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
              />
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
              />
              <small>Identificador MES del operario o supervisor.</small>
            </div>

            <div className="pallet-field">
              <label htmlFor="supervisor-id">Supervisor autorizador</label>
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
              />
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
            disabled={viewState.status === "loading"}
          >
            {viewState.status === "loading"
              ? "Cerrando palé…"
              : viewState.status === "error" && viewState.correlationId
                ? "Reintentar cierre"
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
