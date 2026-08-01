# Paquete 017 - lote NAV en ordenes de entrada

## Objetivo

El lote del producto terminado deja de ser una decision manual de MES. La
sincronizacion lo lee mediante `ReadMultiple` desde el campo
`Cód_Lote_Salida` de `WS_CPP_OPLanzadas`, lo incorpora al snapshot y lo
persiste en `nav.ordenes_entrada`.

El registro historico anterior al paquete puede conservar `lote = NULL`, pero
una nueva sincronizacion exige exactamente un lote no vacio y coherente con la
orden y el producto. La promocion controlada consume exclusivamente ese lote.

## Cambios

- añade `nav.ordenes_entrada.lote`;
- crea `nav.registrar_lote_snapshot_orden` para asociar lote y hash dentro de
  la misma transaccion que persiste el snapshot;
- crea `nav.promover_orden_entrada_con_lote_nav`, sin parametros manuales de
  lote ni autor;
- retira a `mes_runtime` la ejecucion directa del procedimiento 016 y concede
  solo los nuevos contratos controlados.

## Ejecucion

El paquete se prepara para revision. No debe ejecutarse sin autorizacion
expresa para instalar SQL nuevo en `EBIR_MES_TEST`.
