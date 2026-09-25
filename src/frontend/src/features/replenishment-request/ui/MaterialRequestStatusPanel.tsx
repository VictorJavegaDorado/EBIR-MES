import type { MaterialRequestStatus } from "../api/materialRequest";

type Props = { requests: MaterialRequestStatus[] };

const labels: Record<MaterialRequestStatus["state"], string> = {
  PENDING: "Pendiente de almacén",
  PREPARING: "Material en preparación",
  SENT: "Material enviado",
  ERROR: "Requiere revisión",
};

export function MaterialRequestStatusPanel({ requests }: Props) {
  if (requests.length === 0) return null;

  return <section className="material-status-panel" aria-label="Estado de solicitudes de material"
    aria-live="polite">
    <header><div><span>Solicitudes de material</span><strong>Seguimiento de almacén</strong></div>
      <small>Actualización automática</small></header>
    <div className="material-status-list">
      {requests.map((request) => <article key={request.id}
        className={`material-status ${request.state.toLowerCase()}`}>
        <span className="material-status-light" aria-hidden="true" />
        <div><strong>{request.quantity} ud. · {request.componentCode}</strong>
          <small>{request.description}</small>
          {request.pickingNumber && <small>Picking {request.pickingNumber}</small>}
          {request.error && <small>{request.error}</small>}</div>
        <b>{labels[request.state]}</b>
      </article>)}
    </div>
  </section>;
}
