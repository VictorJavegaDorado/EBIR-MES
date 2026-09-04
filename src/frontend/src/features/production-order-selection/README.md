# Selección de órdenes de producción

Consulta órdenes MES operativas y permite seleccionar una para el flujo de
línea. El lote mostrado procede del snapshot NAV; el frontend no lo calcula ni
permite editarlo.

Cuando una orden exacta recien lanzada aun no figura en MES, el flujo de mesa
puede pedir al backend que la prepare desde EbirTest. El frontend solo envia el
numero escaneado y una correlacion idempotente; no conoce ni decide la operacion
NAV.
