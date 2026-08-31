import { useEffect, useRef, useState, type FormEvent } from "react";
import {
  LabelReprintApiError,
  reprintPalletLabel,
} from "../api/reprintPalletLabel";
import type {
  LabelReprintSupervisor,
  QueuedLabelReprint,
} from "../model/labelReprint";

type Props = {
  palletId: number;
  supervisors: LabelReprintSupervisor[];
  defaultSupervisorId?: number;
};

type ViewState =
  | { status: "idle" }
  | { status: "loading" }
  | { status: "queued"; reprint: QueuedLabelReprint }
  | { status: "error"; code: string; message: string; retryable: boolean };

type Attempt = { fingerprint: string; correlationId: string };

export function PalletLabelReprint({
  palletId,
  supervisors,
  defaultSupervisorId,
}: Props) {
  const initialSupervisor = supervisors.some(
    (supervisor) => supervisor.id === defaultSupervisorId,
  ) ? String(defaultSupervisorId) : supervisors.length === 1
    ? String(supervisors[0].id)
    : "";
  const [supervisorId, setSupervisorId] = useState(initialSupervisor);
  const [reason, setReason] = useState("");
  const [viewState, setViewState] = useState<ViewState>({ status: "idle" });
  const activeRequest = useRef<AbortController | null>(null);
  const attempt = useRef<Attempt | null>(null);

  useEffect(() => () => activeRequest.current?.abort(), []);

  function edit(patch: { supervisorId?: string; reason?: string }) {
    activeRequest.current?.abort();
    activeRequest.current = null;
    attempt.current = null;
    if (patch.supervisorId !== undefined) setSupervisorId(patch.supervisorId);
    if (patch.reason !== undefined) setReason(patch.reason);
    setViewState({ status: "idle" });
  }

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const parsedSupervisor = Number(supervisorId);
    const normalizedReason = reason.trim();
    if (!Number.isSafeInteger(parsedSupervisor) || parsedSupervisor <= 0) {
      setViewState({
        status: "error",
        code: "REPRINT_SUPERVISOR_ID_INVALID",
        message: "Selecciona el supervisor que autoriza la copia.",
        retryable: false,
      });
      return;
    }
    if (!normalizedReason) {
      setViewState({
        status: "error",
        code: "REPRINT_REASON_REQUIRED",
        message: "Indica por qué se necesita otra etiqueta.",
        retryable: false,
      });
      return;
    }

    const fingerprint = JSON.stringify({
      palletId,
      requestedBySupervisorId: parsedSupervisor,
      reason: normalizedReason,
    });
    if (!attempt.current || attempt.current.fingerprint !== fingerprint) {
      attempt.current = { fingerprint, correlationId: createCorrelationId() };
    }

    const request = new AbortController();
    activeRequest.current = request;
    setViewState({ status: "loading" });
    try {
      const reprint = await reprintPalletLabel(
        palletId,
        {
          requestedBySupervisorId: parsedSupervisor,
          reason: normalizedReason,
          correlationId: attempt.current.correlationId,
        },
        request.signal,
      );
      if (activeRequest.current === request) {
        setViewState({ status: "queued", reprint });
      }
    } catch (error) {
      if (request.signal.aborted || activeRequest.current !== request) return;
      if (error instanceof LabelReprintApiError) {
        setViewState({
          status: "error",
          code: error.code,
          message: error.message,
          retryable: error.retryable,
        });
      } else {
        setViewState({
          status: "error",
          code: "PALLET_LABEL_REPRINT_UNAVAILABLE",
          message: "No se puede contactar con el servicio de reimpresión.",
          retryable: true,
        });
      }
    } finally {
      if (activeRequest.current === request) activeRequest.current = null;
    }
  }

  if (viewState.status === "queued") {
    return (
      <div className="label-reprint-success" role="status">
        <strong>Copia solicitada</strong>
        <span>Trabajo {viewState.reprint.id}. Espera a que salga la etiqueta.</span>
      </div>
    );
  }

  return (
    <form className="label-reprint" onSubmit={submit}>
      <div className="label-reprint-heading">
        <strong>¿Necesitas otra etiqueta?</strong>
        <span>Requiere supervisor y queda auditada.</span>
      </div>
      <label>
        Supervisor autorizador
        <select
          value={supervisorId}
          onChange={(event) => edit({ supervisorId: event.target.value })}
          disabled={viewState.status === "loading"}
        >
          <option value="">Selecciona un supervisor</option>
          {supervisors.map((supervisor) => (
            <option key={supervisor.id} value={supervisor.id}>
              {supervisor.name}
            </option>
          ))}
        </select>
      </label>
      <label>
        Motivo de la copia
        <textarea
          maxLength={500}
          value={reason}
          onChange={(event) => edit({ reason: event.target.value })}
          placeholder="Ej.: etiqueta dañada o no legible"
          disabled={viewState.status === "loading"}
        />
      </label>
      {viewState.status === "error" && (
        <div className="label-reprint-error" role="alert">
          <span>{viewState.message}</span>
          <code>{viewState.code}</code>
        </div>
      )}
      <button
        className="secondary-action"
        type="submit"
        disabled={
          viewState.status === "loading"
          || (viewState.status === "error" && !viewState.retryable)
        }
      >
        {viewState.status === "loading"
          ? "Solicitando copia…"
          : viewState.status === "error" && viewState.retryable
            ? "Reintentar copia"
            : "Reimprimir etiqueta"}
      </button>
    </form>
  );
}

function createCorrelationId(): string {
  if (typeof crypto.randomUUID === "function") return crypto.randomUUID();
  const bytes = new Uint8Array(16);
  crypto.getRandomValues(bytes);
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  const hex = Array.from(bytes, (value) => value.toString(16).padStart(2, "0"));
  return `${hex.slice(0, 4).join("")}-${hex.slice(4, 6).join("")}-${hex.slice(6, 8).join("")}-${hex.slice(8, 10).join("")}-${hex.slice(10).join("")}`;
}
