import { useEffect, useRef, useState, type FormEvent } from "react";
import type { ProductionTableOperator } from "../api/productionTable";

export type OperatorActionKind = "STOP" | "RESUME" | "EXIT";
export type ActiveStopReason = "WC" | "PAUSA_CALOR";

type Props = {
  action: OperatorActionKind;
  employee: ProductionTableOperator;
  busy: boolean;
  serverError: { message: string; code: string } | null;
  onCancel: () => void;
  onConfirm: (credential: string, reason?: ActiveStopReason) => Promise<void>;
};

const stopReasons = [
  { code: "WC", label: "WC", enabled: true },
  { code: "PAUSA_CALOR", label: "Pausa de calor", enabled: true },
  ...Array.from({ length: 8 }, (_, index) => ({
    code: `MOTIVO_${index + 3}`,
    label: `Motivo ${index + 3}`,
    enabled: false,
  })),
] as const;

export function OperatorActionDialog({
  action,
  employee,
  busy,
  serverError,
  onCancel,
  onConfirm,
}: Props) {
  const [reason, setReason] = useState<ActiveStopReason | null>(null);
  const [credential, setCredential] = useState("");
  const [localError, setLocalError] = useState("");
  const dialogRef = useRef<HTMLElement | null>(null);
  const credentialRef = useRef<HTMLInputElement | null>(null);
  const busyRef = useRef(busy);
  const cancelRef = useRef(onCancel);
  busyRef.current = busy;
  cancelRef.current = onCancel;
  const requiresReason = action === "STOP";
  const asksForCredential = !requiresReason || reason !== null;

  useEffect(() => {
    const previousOverflow = document.body.style.overflow;
    document.body.style.overflow = "hidden";
    const focusTimer = window.setTimeout(() => {
      const firstButton = dialogRef.current?.querySelector<HTMLButtonElement>(
        "button:not([disabled])",
      );
      firstButton?.focus();
    }, 0);

    function handleKeyDown(event: KeyboardEvent) {
      if (event.key === "Escape" && !busyRef.current) {
        event.preventDefault();
        cancelRef.current();
        return;
      }
      if (event.key !== "Tab" || !dialogRef.current) return;
      const focusable = Array.from(dialogRef.current.querySelectorAll<HTMLElement>(
        'button:not([disabled]), input:not([disabled]), [tabindex]:not([tabindex="-1"])',
      ));
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
    }

    document.addEventListener("keydown", handleKeyDown);
    return () => {
      window.clearTimeout(focusTimer);
      document.body.style.overflow = previousOverflow;
      document.removeEventListener("keydown", handleKeyDown);
    };
  }, []);

  useEffect(() => {
    if (!asksForCredential) return;
    window.setTimeout(() => credentialRef.current?.focus(), 0);
  }, [asksForCredential]);

  async function submit(event: FormEvent) {
    event.preventDefault();
    const rawCredential = credential.trim();
    setCredential("");
    if (!rawCredential) {
      setLocalError("Acerca la tarjeta RFID del operario seleccionado.");
      credentialRef.current?.focus();
      return;
    }
    setLocalError("");
    await onConfirm(rawCredential, reason ?? undefined);
  }

  const title = action === "STOP"
    ? "Registrar un paro"
    : action === "RESUME"
      ? "Reincorporar al operario"
      : "Salir de la mesa";
  const instruction = action === "EXIT"
    ? "Acerca la tarjeta del propio operario para confirmar su salida."
    : action === "RESUME"
      ? "Acerca la tarjeta del propio operario para finalizar el paro."
      : "Selecciona el motivo y confirma con la tarjeta del propio operario.";

  return (
    <div className="operator-dialog-backdrop" role="presentation">
      <section
        className="operator-dialog"
        ref={dialogRef}
        role="dialog"
        aria-modal="true"
        aria-labelledby="operator-dialog-title"
      >
        <header className="operator-dialog-header">
          <div>
            <p className="eyebrow">{employee.fullName}</p>
            <h3 id="operator-dialog-title">{title}</h3>
            <p>{instruction}</p>
          </div>
          <button
            type="button"
            className="operator-dialog-close"
            aria-label="Cancelar acción"
            onClick={onCancel}
            disabled={busy}
          >
            ×
          </button>
        </header>

        {requiresReason && (
          <div className="stop-reason-grid" aria-label="Motivo del paro">
            {stopReasons.map((item) => (
              <button
                key={item.code}
                type="button"
                className={reason === item.code ? "selected" : ""}
                disabled={!item.enabled || busy}
                aria-pressed={reason === item.code}
                title={item.enabled ? undefined : "Pendiente de definir"}
                onClick={() => setReason(item.code as ActiveStopReason)}
              >
                <strong>{item.label}</strong>
                {!item.enabled && <small>Pendiente de definir</small>}
              </button>
            ))}
          </div>
        )}

        {asksForCredential && (
          <form className="operator-rfid-confirmation" onSubmit={submit}>
            <label htmlFor="operator-action-rfid">Confirmación RFID</label>
            <div className="operator-rfid-control">
              <span aria-hidden="true">RF</span>
              <input
                id="operator-action-rfid"
                ref={credentialRef}
                type="password"
                autoComplete="off"
                value={credential}
                onChange={(event) => {
                  setCredential(event.target.value);
                  setLocalError("");
                }}
                placeholder="Acerca la tarjeta…"
                disabled={busy}
              />
              <button type="submit" disabled={busy}>
                {busy ? "Validando…" : "Confirmar"}
              </button>
            </div>
            <small>La credencial se borra inmediatamente y nunca se muestra ni se conserva.</small>
            {localError && <p className="operator-dialog-error" role="alert">{localError}</p>}
            {serverError && (
              <p className="operator-dialog-error" role="alert">
                {serverError.message} <code>{serverError.code}</code>
              </p>
            )}
          </form>
        )}
      </section>
    </div>
  );
}
