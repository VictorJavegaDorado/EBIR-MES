import { useEffect, useRef, useState, type FormEvent } from "react";
import {
  getMaterialRequestOptions, MaterialRequestApiError, requestMaterial,
  type MaterialRequestOption,
} from "../api/materialRequest";

type Props = {
  sessionId: number;
  employee: { employeeId: number; fullName: string; navEmployeeCode: string };
  onCancel: () => void;
  onCreated: (navRequestId: number, componentCode: string, quantity: number) => void;
};

export function MaterialRequestDialog({ sessionId, employee, onCancel, onCreated }: Props) {
  const [options, setOptions] = useState<MaterialRequestOption[]>([]);
  const [selected, setSelected] = useState<number | null>(null);
  const [quantity, setQuantity] = useState("1");
  const [loading, setLoading] = useState(true);
  const [sending, setSending] = useState(false);
  const [error, setError] = useState<{ message: string; code: string } | null>(null);
  const correlationId = useRef(createCorrelationId());

  useEffect(() => {
    const controller = new AbortController();
    getMaterialRequestOptions(sessionId, controller.signal)
      .then((items) => { setOptions(items); setSelected(items[0]?.orderComponentId ?? null); })
      .catch((caught) => {
        if (controller.signal.aborted) return;
        setError({ message: caught instanceof MaterialRequestApiError ? caught.message
          : "No se pueden cargar los componentes.", code: caught instanceof MaterialRequestApiError
          ? caught.code : "MATERIAL_OPTIONS_FAILED" });
      }).finally(() => { if (!controller.signal.aborted) setLoading(false); });
    return () => controller.abort();
  }, [sessionId]);

  async function submit(event: FormEvent) {
    event.preventDefault();
    const parsed = Number(quantity);
    if (!selected || !Number.isInteger(parsed) || parsed <= 0) {
      setError({ message: "Selecciona un componente e indica una cantidad entera positiva.",
        code: "MATERIAL_REQUEST_INVALID" });
      return;
    }
    const component = options.find((item) => item.orderComponentId === selected)!;
    setSending(true); setError(null);
    try {
      const result = await requestMaterial(sessionId, selected, parsed, employee.employeeId,
        correlationId.current);
      onCreated(result.navRequestId, component.componentCode, parsed);
    } catch (caught) {
      setError({ message: caught instanceof MaterialRequestApiError ? caught.message
        : "No se puede contactar con el servicio MES.", code: caught instanceof MaterialRequestApiError
        ? caught.code : "MATERIAL_REQUEST_UNAVAILABLE" });
    } finally { setSending(false); }
  }

  return <div className="material-modal-backdrop" role="presentation">
    <section className="material-modal" role="dialog" aria-modal="true"
      aria-labelledby="material-modal-title">
      <header><div><p className="eyebrow">Reaprovisionamiento</p>
        <h3 id="material-modal-title">Solicitar material</h3>
        <p>{employee.fullName} · {employee.navEmployeeCode} · Motivo: FALTA</p></div>
        <button type="button" aria-label="Cerrar solicitud" onClick={onCancel} disabled={sending}>×</button>
      </header>
      <form onSubmit={submit}>
        {loading && <p>Cargando componentes…</p>}
        {!loading && options.length === 0 && !error && <p>No hay componentes disponibles.</p>}
        <div className="material-options" role="radiogroup" aria-label="Componente solicitado">
          {options.map((item) => <label key={item.orderComponentId}
            className={selected === item.orderComponentId ? "selected" : ""}>
            <input type="radio" name="component" value={item.orderComponentId}
              checked={selected === item.orderComponentId}
              onChange={() => setSelected(item.orderComponentId)} />
            <span><strong>{item.componentCode}</strong><small>{item.description}</small>
              {item.openRequestCount > 0 && <em>{item.openRequestCount} solicitud abierta</em>}</span>
          </label>)}
        </div>
        <label className="material-quantity">Cantidad
          <input type="number" min="1" step="1" inputMode="numeric" value={quantity}
            onChange={(event) => setQuantity(event.target.value)} /></label>
        {error && <div className="material-error" role="alert"><strong>{error.message}</strong>
          <code>{error.code}</code></div>}
        <div className="material-actions"><button type="button" onClick={onCancel}
          disabled={sending}>Cancelar</button><button type="submit"
          disabled={loading || sending || options.length === 0}>
          {sending ? "Enviando…" : "Enviar solicitud"}</button></div>
      </form>
    </section>
  </div>;
}

function createCorrelationId() {
  return globalThis.crypto.randomUUID();
}
