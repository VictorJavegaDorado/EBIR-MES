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
motivo y supervisor. Un cierre completo no admite motivo y deja al contrato
SQL determinar si requiere supervisor por ser el último palé.

El backend usa exclusivamente `prod.cerrar_palet_idempotente` cuando el
paquete 014 esté instalado. Hasta entonces, y ante errores de disponibilidad,
responde de forma segura sin exponer detalles SQL. Las intenciones locales de
NAV e impresión se persisten por el procedimiento; el endpoint no los llama.

## Preparación operativa del cierre

El terminal identifica primero una línea mediante `GET /api/lines/{code}` y
consulta `GET /api/lines/{lineId}/pallet-close-options`. Esta consulta de solo
lectura devuelve las reservas activas de la sesión actual de la línea, los
empleados MES activos con rol vigente `OPERARIO` o `SUPERVISOR` y los
supervisores MES activos.

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

La previsualizacion se renderiza con los mismos datos persistidos que consumira
el trabajo de impresion. Preparar o mostrar esa previsualizacion no habilita el
Worker ni contacta la impresora fisica.

## Regla funcional de la mesa de produccion

La regla confirmada para el siguiente corte es que cualquier operario
productivo activo pueda cerrar un palet ordinario desde la mesa. El servidor,
no el navegador, determina si se trata del ultimo palet. El ultimo cierre exige
un supervisor activo y queda auditado.

Esta regla obliga a revisar el contrato que actualmente exige supervisor para
cualquier cierre parcial. Hasta completar esa revision siguen vigentes las
validaciones instaladas; la interfaz no debe eludirlas ni simular un cierre.

El formato y las unidades por palet procederan del registro `POK` publicado por
NAV en `WS_CPP_UndMedProd`, segun el contrato descrito en
`production-workstation.md`.

