import { useRef, useState, type FormEvent, type ReactNode } from "react";
import {
  authorizeSupervisorByRfid,
  SupervisorAccessApiError,
} from "../api/authorizeSupervisorByRfid";

export function SupervisorAccessGate({ children }: { children: ReactNode }) {
  const [authorized, setAuthorized] = useState(false);
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
      setError("Acerca la tarjeta RFID de un supervisor.");
      return;
    }

    request.current?.abort();
    const controller = new AbortController();
    request.current = controller;
    setStatus("validating");
    try {
      await authorizeSupervisorByRfid(rawCredential, controller.signal);
      if (request.current === controller) setAuthorized(true);
    } catch (caught) {
      if (controller.signal.aborted || request.current !== controller) return;
      setError(caught instanceof SupervisorAccessApiError
        ? accessError(caught.code)
        : "No se puede contactar con el servicio RFID. Prueba de nuevo.");
    } finally {
      if (request.current === controller) {
        request.current = null;
        setStatus("idle");
      }
    }
  }

  if (authorized) return <>{children}</>;

  return (
    <section className="supervisor-access-page">
      <div
        className="supervisor-access-card"
        role="dialog"
        aria-modal="true"
        aria-labelledby="supervisor-access-title"
      >
        <div className="supervisor-access-lock" aria-hidden="true">RFID</div>
        <p className="eyebrow">Área supervisada</p>
        <h1 id="supervisor-access-title">Control de etiquetas</h1>
        <p>
          Acerca la tarjeta RFID de un supervisor vigente para consultar y
          reimprimir etiquetas.
        </p>
        <form onSubmit={submit}>
          <label htmlFor="supervisor-access-rfid">Tarjeta RFID del supervisor</label>
          <input
            id="supervisor-access-rfid"
            type="password"
            autoComplete="off"
            autoFocus
            value={credential}
            onChange={(event) => setCredential(event.target.value)}
            disabled={status === "validating"}
          />
          <small>La credencial se elimina del terminal inmediatamente.</small>
          {error && <p className="supervisor-access-error" role="alert">{error}</p>}
          <div className="supervisor-access-actions">
            <a href="/">Volver a producción</a>
            <button className="primary-action" type="submit" disabled={status === "validating"}>
              {status === "validating" ? "Validando…" : "Validar supervisor"}
            </button>
          </div>
        </form>
      </div>
    </section>
  );
}

function accessError(code: string): string {
  if (code === "RFID_SUPERVISOR_NOT_AUTHORIZED")
    return "La tarjeta no pertenece a un supervisor vigente.";
  if (code === "RFID_CREDENTIAL_INVALID")
    return "Acerca una tarjeta RFID válida.";
  return "No se puede validar el supervisor en este momento. Prueba de nuevo.";
}
