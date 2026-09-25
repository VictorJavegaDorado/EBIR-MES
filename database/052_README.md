# Paquete 052 - Seguimiento de solicitudes de material MES

`052A_seguimiento_solicitudes_material_mes.sql` crea un procedimiento de
lectura mínimo para recuperar por sesión la correlación auditada y el contexto
de las solicitudes de material. No modifica solicitudes, estados ni datos NAV.

El runtime conserva sin cambios la prohibición de leer directamente
`aud.eventos`; recibe únicamente permiso `EXECUTE` sobre el procedimiento. La
instalación está permitida exclusivamente en `EBIR_MES_TEST` y requiere
autorización SQL explícita.
