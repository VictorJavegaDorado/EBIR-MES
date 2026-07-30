import { useEffect, useRef, useState, type FormEvent } from "react";
import {
  identifyLine,
  LineIdentificationApiError,
} from "../api/identifyLine";
import type { IdentificationViewState } from "../model/lineIdentification";

export function LineIdentificationPage() {
  const [lineCode, setLineCode] = useState("");
  const [viewState, setViewState] = useState<IdentificationViewState>({
    status: "idle",
  });
  const activeRequest = useRef<AbortController | null>(null);

  useEffect(() => {
    return () => activeRequest.current?.abort();
  }, []);

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const normalizedCode = lineCode.trim().toUpperCase();

    if (!normalizedCode) {
      setViewState({
        status: "error",
        code: "LINE_CODE_REQUIRED",
        message: "Introduce el código de la línea para continuar.",
      });
      return;
    }

    activeRequest.current?.abort();
    const request = new AbortController();
    activeRequest.current = request;
    setLineCode(normalizedCode);
    setViewState({ status: "loading", code: normalizedCode });

    try {
      const line = await identifyLine(normalizedCode, request.signal);
      if (activeRequest.current !== request) {
        return;
      }

      setViewState({ status: "found", line });
    } catch (error) {
      if (request.signal.aborted || activeRequest.current !== request) {
        return;
      }

      if (error instanceof LineIdentificationApiError) {
        setViewState({
          status: "error",
          code: error.code,
          message: error.message,
        });
        return;
      }

      setViewState({
        status: "error",
        code: "LINE_IDENTIFICATION_UNAVAILABLE",
        message:
          "No se puede contactar con el servicio de identificación. Inténtalo de nuevo.",
      });
    } finally {
      if (activeRequest.current === request) {
        activeRequest.current = null;
      }
    }
  }

  return (
    <div className="identification-page">
      <section className="welcome-panel">
        <div className="welcome-copy">
          <p className="eyebrow">Inicio de operación</p>
          <h1>Identifica tu línea</h1>
          <p className="welcome-description">
            Introduce el código visible en el puesto para consultar su estado e
            iniciar la sesión de trabajo.
          </p>
        </div>

        <div className="shift-card">
          <span>Horario operativo</span>
          <strong>06:00 — 22:00</strong>
          <small>MAÑANA · TARDE</small>
        </div>
      </section>

      <section className="workspace-grid">
        <form
          className="identification-card"
          onSubmit={handleSubmit}
          aria-busy={viewState.status === "loading"}
        >
          <div className="card-heading">
            <span className="step-number">01</span>
            <div>
              <h2>Código de línea</h2>
              <p>Escribe el código visible en el puesto.</p>
            </div>
          </div>

          <label className="line-input-label" htmlFor="line-code">
            Línea de fabricación
          </label>
          <div className="line-input-wrap">
            <span aria-hidden="true">#</span>
            <input
              id="line-code"
              name="lineCode"
              autoComplete="off"
              autoFocus
              maxLength={20}
              placeholder="Ej. L-01"
              value={lineCode}
              onChange={(event) => {
                activeRequest.current?.abort();
                activeRequest.current = null;
                setLineCode(event.target.value);
                setViewState({ status: "idle" });
              }}
              aria-describedby="line-code-help"
            />
          </div>

          <button
            className="primary-action"
            type="submit"
            disabled={viewState.status === "loading"}
          >
            {viewState.status === "loading" ? "Consultando…" : "Consultar línea"}
            <span aria-hidden="true">→</span>
          </button>

          <p className="connection-note" id="line-code-help">
            <span aria-hidden="true">i</span>
            La consulta no abre sesiones ni modifica producción.
          </p>
        </form>

        <aside className="line-result-card" aria-live="polite">
          <div className="card-heading compact">
            <span className="step-number muted">02</span>
            <div>
              <h2>Resultado</h2>
              <p>Estado actual de la línea</p>
            </div>
          </div>

          {viewState.status === "idle" && (
            <div className="result-placeholder">
              <span aria-hidden="true">#</span>
              <strong>Esperando identificación</strong>
              <p>Introduce un código para consultar la línea configurada.</p>
            </div>
          )}

          {viewState.status === "loading" && (
            <div className="result-placeholder loading" role="status">
              <span className="loading-mark" aria-hidden="true" />
              <strong>Consultando {viewState.code}</strong>
              <p>Comprobando configuración y estado operativo.</p>
            </div>
          )}

          {viewState.status === "error" && (
            <div className="result-error" role="alert">
              <span aria-hidden="true">!</span>
              <strong>No se puede continuar</strong>
              <p>{viewState.message}</p>
              <small>{viewState.code}</small>
            </div>
          )}

          {viewState.status === "found" && (
            <div className="identified-line">
              <div className="identified-line-code">
                <span>Línea identificada</span>
                <strong>{viewState.line.code}</strong>
              </div>
              <dl>
                <div>
                  <dt>Descripción</dt>
                  <dd>{viewState.line.name}</dd>
                </div>
                <div>
                  <dt>Centro de trabajo</dt>
                  <dd>
                    {viewState.line.workCenterName}
                    <small>{viewState.line.workCenterCode}</small>
                  </dd>
                </div>
                <div>
                  <dt>Estado operativo</dt>
                  <dd>
                    <span className="operational-status">
                      {viewState.line.operationalStatus.replaceAll("_", " ")}
                    </span>
                  </dd>
                </div>
              </dl>
              <button className="secondary-action" type="button" disabled>
                Abrir sesión · próximo paso
              </button>
            </div>
          )}
        </aside>
      </section>

      <section className="process-strip" aria-label="Pasos del proceso">
        <div className="process-step active">
          <span>1</span>
          <strong>Identificar línea</strong>
        </div>
        <div className="process-line" />
        <div className="process-step">
          <span>2</span>
          <strong>Abrir sesión</strong>
        </div>
        <div className="process-line" />
        <div className="process-step">
          <span>3</span>
          <strong>Iniciar producción</strong>
        </div>
      </section>
    </div>
  );
}
