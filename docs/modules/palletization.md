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

