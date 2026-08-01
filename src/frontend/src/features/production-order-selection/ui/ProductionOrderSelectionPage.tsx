import { useEffect, useMemo, useState } from "react";
import {
  getProductionOrders,
  ProductionOrderSelectionApiError,
} from "../api/getProductionOrders";
import type { ProductionOrder } from "../model/productionOrder";

type Props = {
  selectedOrder: ProductionOrder | null;
  onOrderChange: (order: ProductionOrder) => void;
};

type ViewState =
  | { status: "loading" }
  | { status: "ready"; orders: ProductionOrder[] }
  | { status: "error"; code: string };

export function ProductionOrderSelectionPage({
  selectedOrder,
  onOrderChange,
}: Props) {
  const [viewState, setViewState] = useState<ViewState>({ status: "loading" });
  const [search, setSearch] = useState("");
  const [reloadKey, setReloadKey] = useState(0);

  useEffect(() => {
    const request = new AbortController();
    setViewState({ status: "loading" });
    getProductionOrders(request.signal)
      .then((orders) => setViewState({ status: "ready", orders }))
      .catch((error: unknown) => {
        if (request.signal.aborted) return;
        setViewState({
          status: "error",
          code:
            error instanceof ProductionOrderSelectionApiError
              ? error.code
              : "PRODUCTION_ORDER_SELECTION_UNAVAILABLE",
        });
      });
    return () => request.abort();
  }, [reloadKey]);

  const visibleOrders = useMemo(() => {
    if (viewState.status !== "ready") return [];
    const filter = search.trim().toUpperCase();
    if (!filter) return viewState.orders;
    return viewState.orders.filter((order) =>
      [order.orderNumber, order.productNumber, order.productDescription, order.lotNumber]
        .some((value) => value.toUpperCase().includes(filter)),
    );
  }, [search, viewState]);

  return (
    <div className="order-selection-page">
      <header className="order-selection-header">
        <div>
          <p className="eyebrow">Producción disponible</p>
          <h1>Selecciona una orden</h1>
          <p className="welcome-description">
            El lote procede de NAV y acompañará a todos los palés de la orden.
          </p>
        </div>
        {selectedOrder && (
          <div className="selected-order-summary" aria-live="polite">
            <span>Orden seleccionada</span>
            <strong>{selectedOrder.orderNumber}</strong>
            <small>Lote {selectedOrder.lotNumber}</small>
          </div>
        )}
      </header>

      <section className="order-selection-card">
        <label className="line-input-label" htmlFor="order-search">
          Buscar por orden, producto, descripción o lote
        </label>
        <div className="line-input-wrap order-search-wrap">
          <span aria-hidden="true">⌕</span>
          <input
            id="order-search"
            value={search}
            onChange={(event) => setSearch(event.target.value)}
            placeholder="Ej. FL20-02277"
            autoComplete="off"
          />
        </div>

        {viewState.status === "loading" && (
          <div className="order-list-message" role="status">
            <span className="loading-mark" aria-hidden="true" />
            <strong>Cargando órdenes disponibles…</strong>
          </div>
        )}
        {viewState.status === "error" && (
          <div className="order-list-message error" role="alert">
            <strong>No se pueden consultar las órdenes</strong>
            <small>{viewState.code}</small>
            <button type="button" onClick={() => setReloadKey((value) => value + 1)}>
              Reintentar
            </button>
          </div>
        )}
        {viewState.status === "ready" && visibleOrders.length === 0 && (
          <div className="order-list-message">
            <strong>No hay órdenes que coincidan</strong>
            <p>Prueba con otro número, producto o lote.</p>
          </div>
        )}
        {viewState.status === "ready" && visibleOrders.length > 0 && (
          <div className="production-order-list">
            {visibleOrders.map((order) => {
              const selected = selectedOrder?.productionOrderId === order.productionOrderId;
              return (
                <article className={`production-order-card${selected ? " selected" : ""}`} key={order.productionOrderId}>
                  <div className="production-order-main">
                    <span className="order-state">{order.state.replaceAll("_", " ")}</span>
                    <h2>{order.orderNumber}</h2>
                    <p>{order.productDescription}</p>
                    <small>{order.productNumber}</small>
                  </div>
                  <dl className="production-order-facts">
                    <div><dt>Lote</dt><dd>{order.lotNumber}</dd></div>
                    <div><dt>Objetivo</dt><dd>{order.targetQuantity} uds.</dd></div>
                    <div><dt>Tiempo NAV</dt><dd>{order.runTimeMinutes} min/ud.</dd></div>
                    <div><dt>Fabricadas</dt><dd>{order.goodQuantity}</dd></div>
                  </dl>
                  <button
                    type="button"
                    className="primary-action order-select-action"
                    onClick={() => onOrderChange(order)}
                    aria-pressed={selected}
                  >
                    {selected ? "Orden seleccionada" : "Seleccionar orden"}
                    <span aria-hidden="true">{selected ? "✓" : "→"}</span>
                  </button>
                </article>
              );
            })}
          </div>
        )}
      </section>
    </div>
  );
}
