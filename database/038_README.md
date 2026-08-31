# Paquete 038 - Reimpresion supervisada de etiqueta de palet

Estado: instalado y validado el 31/08/2026 en `EBIR_MES_TEST`.

`038A_reimpresion_etiqueta_palet.sql` incorpora el contrato transaccional
`imp.solicitar_reimpresion_palet` y adapta la reserva y confirmacion de la cola
para distinguir una copia de la impresion original.

Garantias:

- base exclusiva `EBIR_MES_TEST`;
- supervisor activo, motivo y correlacion obligatorios;
- repeticion idempotente por correlacion;
- una sola copia por solicitud y ningun trabajo simultaneo para la etiqueta;
- la etiqueta original permanece `IMPRESA`;
- la copia no modifica NAV ni repite transiciones productivas;
- solicitud y resultado auditados;
- permisos limitados al rol `mes_runtime`.

Antes de instalar se requiere revision estatica, ensayo con rollback, copia
`COPY_ONLY` verificada y autorizacion expresa. Las pruebas usan adaptador
simulado y no contactan una impresora fisica.
