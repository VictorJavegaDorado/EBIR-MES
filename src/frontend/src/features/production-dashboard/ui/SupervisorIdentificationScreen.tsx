import { useRef, useState, type FormEvent } from "react";
import {
  authorizeSupervisorByRfid,
  SupervisorAccessApiError,
  type AuthorizedSupervisor,
} from "../../supervisor-access/api/authorizeSupervisorByRfid";

type Props = {
  onIdentified: (supervisor: AuthorizedSupervisor) => void;
  onSkip: () => void;
};

export function SupervisorIdentificationScreen({ onIdentified, onSkip }: Props) {
  const [credential, setCredential] = useState("");
  const [status, setStatus] = useState<"idle" | "validating">("idle");
  const [error, setError] = useState("");
  const request = useRef<AbortController | null>(null);

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const rawCredential = credential.trim();
    setCredential("");
    setError("");
    if (!rawCredential) {
      setError("Acerca tu tarjeta RFID de jefe de línea.");
      return;
    }

    request.current?.abort();
    const controller = new AbortController();
    request.current = controller;
    setStatus("validating");
    try {
      const supervisor = await authorizeSupervisorByRfid(rawCredential, controller.signal);
      if (request.current === controller) onIdentified(supervisor);
    } catch (caught) {
      if (controller.signal.aborted || request.current !== controller) return;
      setError(caught instanceof SupervisorAccessApiError
        ? identificationError(caught.code)
        : "No se puede contactar con el servicio RFID. Prueba de nuevo.");
    } finally {
      if (request.current === controller) {
        request.current = null;
        setStatus("idle");
      }
    }
  }

  return (
    <section className="dashboard-identify-page">
      <div
        className="dashboard-identify-card"
        role="dialog"
        aria-modal="true"
        aria-labelledby="dashboard-identify-title"
      >
        <p className="eyebrow">Panel de fabricación</p>
        <h1 id="dashboard-identify-title">Identifícate como jefe de línea</h1>
        <p>Acerca tu tarjeta RFID al lector para elegir las mesas que quieres ver.</p>
        <form onSubmit={submit}>
          <label htmlFor="dashboard-identify-rfid">Tarjeta RFID</label>
          <input
            id="dashboard-identify-rfid"
            type="password"
            autoComplete="off"
            autoFocus
            value={credential}
            onChange={(event) => setCredential(event.target.value)}
            disabled={status === "validating"}
          />
          <small>La credencial se elimina del terminal inmediatamente.</small>
          {error && <p className="dashboard-identify-error" role="alert">{error}</p>}
          <div className="dashboard-identify-actions">
            <button type="button" className="dashboard-identify-skip" onClick={onSkip}>
              Ver toda la planta sin identificarme
            </button>
            <button type="submit" disabled={status === "validating"}>
              {status === "validating" ? "Validando…" : "Identificarme"}
            </button>
          </div>
        </form>
      </div>
    </section>
  );
}

function identificationError(code: string): string {
  if (code === "RFID_SUPERVISOR_NOT_AUTHORIZED")
    return "La tarjeta no pertenece a un jefe de línea vigente.";
  if (code === "RFID_CREDENTIAL_INVALID")
    return "Acerca una tarjeta RFID válida.";
  return "No se puede identificar en este momento. Prueba de nuevo.";
}
