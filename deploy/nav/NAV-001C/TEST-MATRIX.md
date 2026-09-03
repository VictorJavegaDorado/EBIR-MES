# Matriz de pruebas NAV-001C

| Caso | Resultado exigido |
|---|---|
| Objeto actual | Codeunit 50009 y Table 472 coinciden con los exports protegidos |
| Entrada unica | Una coincidencia exacta por objeto y parametro |
| Duplicado o divergencia | Detenerse sin editar |
| Preparacion | Entrada recurrente pero en `En espera`; tarea de sistema vacia |
| Dias | Lunes a domingo activados |
| Ventana | `00:00:00` a `23:59:59` |
| Intervalo | Un minuto |
| Caducidad | Vacia |
| Intentos | Maximo 1 |
| Impresion NAV | Ninguna |
| Ejecucion interactiva | Rechazada por Codeunit 50009 |
| Primera activacion | Solo con autorizacion; transicion a `Listo` con `EBIR\NAVEBIR` |
| Persistencia | Tras un ciclo correcto la entrada sigue existiendo y vuelve a `Listo` |
| Aislamiento | Ninguna otra entrada cambia de estado, tarea o proxima ejecucion |
| Sin trabajo | Report 50056 termina sin crear movimientos ni imprimir |
| Con una salida MES | Una sola salida pasa de `Pendiente` a `Registrado` |
| Repeticion | Cero segundo movimiento para el mismo identificador |
| Error | Estado y mensaje observables; no ejecutar manualmente para compensar |
| Rollback | `En espera`, tarea detenida y campos periodicos restaurados a no periodicos |

La prueba con una salida real se coordina con el Worker MES y requiere backup
verificado de `EBIR_MES_TEST`, cola vacia y autorizacion especifica.
