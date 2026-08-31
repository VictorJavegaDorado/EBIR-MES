# Paletización

La paletización agrupa unidades producidas en un palé trazable. El cierre manual
de un palé deberá:

- comprobar que el palé esté abierto;
- comprobar que contenga al menos una unidad válida;
- persistir el cierre de manera transaccional;
- crear el trabajo de impresión dentro de la misma operación de negocio;
- permitir que el worker imprima después, fuera de la transacción;
- ser idempotente frente a repeticiones del terminal.

## Cierre manual idempotente

El primer corte backend expone `POST /api/pallet-reservations/{reservationId}/close`.
Recibe cantidad buena, empleado que cierra, supervisor autorizador opcional,
marca de parcialidad, motivo parcial y correlación. Devuelve `200 OK` con el
identificador del palé y la correlación tanto en el primer cierre como en un
reintento: el contrato de persistencia no distingue ambos resultados.

La correlación es obligatoria. Los motivos parciales permitidos son
`FIN_TURNO`, `FALTA_MATERIAL` y `ULTIMO_PALET`; un cierre parcial requiere
motivo. Un cierre completo no admite motivo. El contrato SQL calcula si el
cierre completa la cantidad objetivo y exige supervisor solo en ese ultimo
palet, sea parcial o completo.

El backend usa exclusivamente `prod.cerrar_palet_idempotente` cuando el
paquete 014 esté instalado. Hasta entonces, y ante errores de disponibilidad,
responde de forma segura sin exponer detalles SQL. Las intenciones locales de
NAV e impresión se persisten por el procedimiento; el endpoint no los llama.

## Preparación operativa del cierre

El terminal identifica primero una línea mediante `GET /api/lines/{code}` y
consulta `GET /api/lines/{lineId}/pallet-close-options` desde la pantalla de
Trabajo. Esta consulta de solo lectura devuelve las reservas activas de la
sesión actual de la línea, los empleados MES activos con rol vigente
`OPERARIO` o `SUPERVISOR` y los supervisores MES activos.

La reserva es interna. La interfaz exige una unica reserva activa, la resuelve
automaticamente y la presenta como `Palet en curso`, con formato POK y cantidad
propuesta editable. No muestra identificadores de reserva ni obliga a navegar a
un modulo separado. Tras un cierre confirmado vuelve a consultar las opciones
para preparar el siguiente palet dentro de la misma mesa.

Si no hay reservas activas devuelve una lista vacía. El frontend bloquea el
cierre mientras carga las opciones y permite recuperar un fallo de consulta.
Los errores temporales conservan la correlación para un reintento sin cambios.
Los conflictos productivos o de correlación bloquean el replay directo y
cualquier edición invalida la correlación anterior.

Los logs registran reserva, correlación, resultado y código funcional. No
registran nombres de empleados, secretos ni detalles SQL.

La lista de personas que pueden figurar como autor material de un cierre se
limita a fichajes abiertos de la sesion activa de la linea y excluye a quien
tenga un paro de operario abierto. No basta con disponer globalmente del rol
`OPERARIO` o `SUPERVISOR` en MES.

La misma regla se revalida bajo bloqueo dentro de `prod.cerrar_palet`: el autor
debe conservar un fichaje abierto en la sesion de la reserva y no puede tener
un paro individual abierto. Una lista de opciones desactualizada no permite
cerrar un palet.

En la mesa, el cierre se inicia desde la tarjeta de una persona productiva. El
formulario se abre como dialogo, fija esa persona como autor y mantiene la
cantidad `POK` propuesta editable. No muestra un selector de empleado: antes de
habilitar el envio comprueba que el autor siga presente en las opciones activas
devueltas por el servidor. La confirmacion permanece visible en el dialogo y
ofrece una vuelta explicita a la mesa. Los avatares usan iniciales; este corte
no integra fotografias ni amplia los datos personales del contrato.

## Plantilla de etiqueta de palet

La plantilla confirmada mide 150 x 100 mm, se prepara para Vretti a 201 dpi y
presenta los datos en horizontal aunque la alimentacion fisica sea vertical.
El contenido funcional es: logo EBIR, grupo contable de producto, codigo y
descripcion del articulo, numero de orden, cantidad real cerrada y nombre de la
linea MES.

El grupo contable se obtiene en TEST del campo ODataV4
`Gen_Prod_Posting_Group`; no se deduce del codigo ni de la descripcion. La
consulta exacta autorizada del producto `27920LG` devolvio una sola coincidencia
y el valor `P_MATPRIMA`. Antes de generar una etiqueta, MES debe persistir ese
dato en el snapshot de la orden y trasladarlo al payload de `imp.etiquetas`.
Cero o varias coincidencias, o un grupo vacio, bloquean la generacion: la
plantilla no muestra valores inventados.

La previsualizacion se renderiza en proporcion 150 x 100 con los datos
persistidos de la reserva y la orden que consumira el trabajo de impresion.
La cantidad mostrada es la cantidad que el operario va a cerrar. Preparar o
mostrar esa previsualizacion no crea `imp.etiquetas`, no habilita el Worker ni
contacta la impresora fisica.

La proporcion se conserva tambien dentro de la mesa de produccion. Tipografias
y filas escalan respecto al ancho disponible para que codigo, articulo, orden,
cantidad y linea permanezcan visibles sin recorte en el terminal del piloto.

## Regla funcional de la mesa de produccion

La regla confirmada para el siguiente corte es que cualquier operario
productivo activo pueda cerrar un palet ordinario desde la mesa. El servidor,
no el navegador, determina si se trata del ultimo palet. El ultimo cierre exige
un supervisor activo y queda auditado.

El paquete 025A implementa esta regla en el contrato SQL y agrega el grupo
contable al JSON persistido de `imp.etiquetas`. Esta instalado y validado en
`EBIR_MES_TEST` desde el 05/08/2026. La release activa
`20260805.3-3e02370-combined` expone la previsualizacion y consume el grupo ya
adoptado por la orden. Worker e impresion fisica permanecen desactivados.

El resultado visible confirma el pale y muestra NAV como pendiente de segundo
plano. No existe un paso NAV manual y la interfaz no declara una confirmacion
externa que el backend no haya recibido.

La entrega asíncrona de esa intención se define en `nav-pallet-output.md`. El
paquete 026A, el Worker y el adaptador ODataV4 están preparados, pero el paquete
no está instalado y el Worker permanece desactivado. El cierre local no
equivale todavía a una salida confirmada.

Para la orden de ensayo `FL26-00003`, objetivo 100 y formato POK de 20
unidades, los palets 1 a 4 son cierres ordinarios realizables por cualquier
operario activo en la mesa. El quinto completa el objetivo y exige un
supervisor autorizador vigente. El servidor calcula esa posicion usando las
cantidades bloqueadas de la orden; el navegador no decide que palet es el
ultimo.

Un palet no final cerrado no detiene los fichajes ni el contador productivo.
La salida NAV y la etiqueta conservan su estado propio mientras la mesa sigue
operativa. El siguiente cierre queda bloqueado hasta que la salida anterior
esté confirmada en NAV; esta barrera evita solapar o duplicar movimientos. El
último palet continúa requiriendo supervisor y confirmación externa antes del
cierre definitivo de la orden.

El formato y las unidades por palet procederan del registro `POK` publicado por
NAV en `WS_CPP_UndMedProd`, segun el contrato descrito en
`production-workstation.md`.

## Impresion fisica mediante cola Windows

La integracion fisica usa el controlador oficial del fabricante y una cola de
Windows instalada en el host del Worker. MES no presupone TSPL, ZPL ni otro
lenguaje propietario a partir del transporte `RAW_TCP`. El modo
`WindowsSpooler` permanece desactivado por defecto y exige un mapeo explicito
entre cada codigo de impresora MES y el nombre exacto de su cola Windows.

La plantilla `PALET` version 1 se renderiza a 150 x 100 mm con marca EBIR,
grupo contable, codigo y descripcion del articulo, orden, lote, cantidad,
linea y codigo visible del palet. Los datos proceden exclusivamente del JSON
persistido en `imp.etiquetas`; un campo funcional vacio bloquea la entrega.
Cada documento usa el UID inmutable del trabajo en su nombre tecnico. La
entrega al spooler tiene un timeout acotado; un timeout o cancelacion conserva
la reserva para conciliacion supervisada y no habilita un reintento automatico
que pueda duplicar una etiqueta ya aceptada por Windows.

Instalar el controlador, crear la cola, habilitar `WindowsSpooler` o ejecutar
una impresion fisica son operaciones separadas y requieren autorizacion
expresa. Las pruebas automatizadas sustituyen la cola de Windows y nunca
contactan una impresora real.

## Reimpresion supervisada

Una copia adicional de la etiqueta de palet se solicita mediante
`POST /api/pallets/{palletId}/label-reprints`. Requiere un supervisor MES
activo, un motivo no vacio y una correlacion. La repeticion exacta de la misma
correlacion devuelve el mismo trabajo; reutilizarla con otros parametros se
rechaza.

Solo se admite cuando existe una impresion original completada, la etiqueta
permanece `IMPRESA`, no hay otro trabajo abierto para ella y la linea conserva
una impresora principal activa. La solicitud crea exactamente un trabajo con
`es_reimpresion = 1`, una copia y auditoria del supervisor y el motivo. No crea
ni modifica operaciones NAV.

El Worker reserva una reimpresion directamente sobre una etiqueta `IMPRESA`.
Al completarla registra `ETIQUETA_REIMPRESA`, pero no cambia la fecha ni el
estado funcional de la etiqueta original y no repite desbloqueos de linea,
finalizaciones de orden ni otras transiciones productivas. Un resultado
desconocido no se reencola automaticamente.

