# Sincronizacion de ordenes de produccion

## Objetivo

MES consulta ordenes de produccion publicadas por NAV, las traduce a un
contrato estable y prepara su persistencia idempotente en una bandeja de
entrada. NAV permanece exclusivamente en lectura.

## Alcance de lectura

- Cabeceras SOAP `ReadMultiple`: `WS_CPP_ProdOrderList`.
- Lineas SOAP `ReadMultiple`: `WS_CPP_ProdOrderLineList`.
- Ruta y operaciones OData Atom mediante `GET`:
  `WS_CPP_RutaOrdenProduccion`.
- Componentes SOAP `ReadMultiple`: `WS_CPP_Componentes`.
- Formato de palet ODataV4 mediante `GET` a `WS_CPP_UndMedProd`, filtrado por
  producto y codigo exacto `POK`, con `$top=2` para detectar duplicados.
- Grupo contable de producto ODataV4 mediante `GET` a `ItemSalesAndProfit`,
  filtrado por `No` exacto, seleccionando `No` y
  `Gen_Prod_Posting_Group`, con `$top=2` para detectar duplicados.
- Lote de salida del producto terminado: `Cód_Lote_Salida` de
  `WS_CPP_OPLanzadas`, mediante SOAP `ReadMultiple`.
- Estado inicial de trabajo: ordenes lanzadas (`Released`).
- Cada consulta exige un limite entre 1 y 100 registros.
- Las lecturas de detalle exigen un numero de orden exacto. Se rechazan rangos,
  comodines y operadores de filtro de NAV. La ruta usa un `$filter` OData
  exacto por `Prod_Order_No` y un `$top` limitado.
- La autenticacion se delega a la identidad del proceso; no se guardan
  credenciales en codigo ni configuracion versionada.
- Las llamadas solo se producen cuando un caso de uso invoca el adaptador.
- La lectura permanece estrictamente de solo lectura: no se invocan acciones,
  codeunits ni verbos de escritura OData.

La relacion de componentes conserva los numeros de linea de NAV. La pagina de
lineas publicada no expone su numero de linea, por lo que durante el piloto se
exige exactamente una linea por orden.

El contrato del formato POK, sus validaciones y su uso por la mesa de
produccion estan documentados en `production-workstation.md`. La lectura usa
los campos `Item_No`, `Code` y `Qty_per_Unit_of_Measure`. El lector y el modelo
de snapshot estan implementados y la persistencia del paquete 022 esta
instalada en `EBIR_MES_TEST` desde el 05/08/2026.

El grupo contable tampoco se deduce en MES. Debe existir una unica fila para
el producto, la clave devuelta debe coincidir exactamente y el codigo debe ser
no vacio y tener como maximo 50 caracteres. Forma parte del hash del snapshot,
se persiste en la bandeja y se fija en `prod.ordenes` durante la promocion. El
paquete 025A que incorpora esa persistencia esta instalado en
`EBIR_MES_TEST` desde el 05/08/2026.

## Bandeja de entrada idempotente

El caso de uso lee por numero exacto una orden `Released`, su lote de salida,
linea, ruta y componentes. Normaliza entorno, empresa y orden, rechaza relaciones incoherentes
y no acepta exactamente 100 detalles para evitar persistir una pagina
posiblemente truncada. La orden solo entra en la bandeja MES cuando la ruta
contiene exactamente una operacion de tipo `Centro trabajo` cuyo numero de
centro es `1`, identificador funcional de Paterna. Las ordenes sin esa operacion
o con mas de una coincidencia se rechazan antes de cualquier escritura SQL.

El adaptador SQL serializa el snapshot completo de forma determinista, calcula
su SHA-256 y llama a `nav.aplicar_snapshot_orden`. El procedimiento preparado:

- serializa por correlacion y por orden mediante `sp_getapplock`;
- repite de forma segura una correlacion con el mismo snapshot;
- rechaza la misma correlacion con contenido distinto;
- devuelve `CREADA`, `ACTUALIZADA` o `SIN_CAMBIOS`;
- sustituye cabecera y detalles atomicamente cuando NAV ha cambiado.

El lote procede exclusivamente de NAV. Si viene informado, debe corresponder a la
misma orden y producto. Puede llegar vacio: MES lo conserva como pendiente, no lo
calcula ni permite sustituirlo manualmente. Las acciones que requieren trazabilidad,
incluida la etiqueta final, permanecen bloqueadas hasta disponer del lote.

## Promocion controlada a produccion

El paquete 016 instala la promocion base. El paquete 017 añade el contrato que
consume exclusivamente el lote persistido con el snapshot; el endpoint solo
recibe la orden de entrada, una operacion NAV y la correlacion. La cantidad debe
ser un entero exacto y el tiempo de ejecucion de
la operacion debe ser positivo y representable sin redondeo en minutos por
unidad.

La pagina OData publica `Run_Time` como fraccion decimal de dia, aunque no
expone un campo de unidad. El lector lo convierte a minutos por unidad
multiplicando por 1440 y lo normaliza a una cifra decimal, precision del
contrato productivo. `Setup_Time`, `Wait_Time` y `Move_Time` conservan el valor
numerico publicado; no participan en la promocion. La operacion Paterna debe
tener un tiempo de ejecucion convertido positivo.

La primera promocion crea atomicamente `prod.ordenes`, sus componentes y, con
el paquete 022, el formato POK en `prod.formatos_palet_orden`. Cuando se instale
025A tambien exigira y fijara el grupo contable de producto. Una
nueva correlacion con el mismo snapshot y decisiones devuelve `SIN_CAMBIOS`.
Un cambio de snapshot, lote NAV u operacion no sobrescribe los datos productivos:
devuelve `REVISION` y bloquea la orden en ese estado. Repetir una correlacion
solo es valido con exactamente el mismo contenido.

El endpoint administrativo `POST /api/admin/production-orders/promote` esta
deshabilitado por defecto y no consulta ni escribe en NAV.

## Resiliencia

Las lecturas SOAP y OData pueden repetirse porque no cambian estado. Se
reintentan como maximo tres veces ante timeouts, errores de transporte, `408`,
`429` o respuestas `5xx`. Los errores funcionales y las respuestas XML o JSON
no validas no se reintentan.

## Seleccion operativa

`GET /api/production-orders` expone hasta 100 ordenes MES operativas en estado
`IMPORTADA`, `ABIERTA` o `PICO_PENDIENTE`, ordenadas por importacion reciente.
La pantalla permite buscar por orden, producto, descripcion o lote y conserva
el lote NAV como dato de solo lectura. Seleccionar una orden no abre una sesion
ni cambia su estado.

## Disparador administrativo controlado

La API compone `IProductionOrderSource`, `IProductionOrderSnapshotStore` y
`SynchronizeProductionOrder`, pero el disparador permanece desactivado por
defecto. Cuando la configuracion operativa lo habilita, el endpoint
`POST /api/admin/production-orders/synchronize` acepta exclusivamente un numero
de orden exacto y una correlacion. El entorno, la empresa, la raiz SOAP y los
limites de resiliencia proceden de configuracion del servidor, nunca del
navegador.

La unica raiz admitida en TEST es
`http://NAVISION2.EBIR.LOCAL:7147/EbirTest/WS/`. El adaptador SOAP agrega despues la
empresa y la pagina NAV. Los lectores OData derivan exclusivamente de esa misma
URI las raices `/OData/` y `/ODataV4/`, conservando esquema, host y puerto, y
agregan empresa y entidad. El alias antiguo, las direcciones IP, HTTPS, otra
instancia, otro puerto y cualquier raiz que no termine en `/WS/` se rechazan.
El codigo interno del entorno sigue siendo `EBIRTEST` y la empresa exacta es
`EBIR`; la raiz no incluye de nuevo la empresa.

La respuesta publica `CREADA`, `ACTUALIZADA` o `SIN_CAMBIOS`. Las validaciones
funcionales se traducen a `400`, `404` o `409`; los fallos de NAV, SQL o de
configuracion se ocultan tras un `503` seguro. El cliente NAV utiliza la
identidad del proceso y no realiza ninguna llamada durante el arranque.

Habilitar el disparador no activa IIS ni programa periodicidad. En la fase
manual debe habilitarse solo para la ventana de prueba y volver a deshabilitarse
al terminar.

## Estado y limites pendientes de autorizacion

- `025A_grupo_contable_y_cierre_palet.sql` esta instalado y validado en
  `EBIR_MES_TEST`. La release activa `20260805.3-3e02370-combined` contiene el
  codigo que genera y consume el nuevo snapshot.

- `025B_adopcion_grupo_contable_snapshot.sql` esta instalado y validado en
  `EBIR_MES_TEST`. Permitio adoptar el nuevo campo en `FL26-00003` porque el
  JSON anterior coincidia exactamente al retirar `productPostingGroup`; no
  relaja la revision ante otros cambios NAV.

- El paquete `022A_formato_palet_pok.sql` esta instalado y validado en
  `EBIR_MES_TEST`. La release activa aun no contiene el lector POK; su despliegue
  requiere una candidate y autorizacion de activacion independientes.

- El paquete `015A_bandeja_entrada_ordenes_nav.sql` esta instalado y validado en
  `EBIR_MES_TEST`.
- El paquete `016A_promover_ordenes_nav.sql` esta instalado y validado en
  `EBIR_MES_TEST`; todavia no se ha promovido ninguna orden real.
- El paquete `017A_lote_nav_ordenes_entrada.sql` esta instalado y validado en
  `EBIR_MES_TEST`.
- La primera invocacion manual se hizo usando `29516CI/1508` como numero de
  orden. Ese valor es el producto; el snapshot historico conservado no debe
  promocionarse.
- Programar periodicidad solo despues de validar el disparador manual.
- Ejecutar una promocion manual real desde `nav.*_entrada` a `prod.ordenes`.
- Invocar codeunits que registren tiempos, consumos, salidas o cierres.
- Activar el adaptador en API, Worker o IIS.
- Contactar RFID o impresoras.
