# Runbook NAV-001A en EbirTest

Este documento no autoriza ejecutar sus fases. Cada bloque que cambie NAV,
Job Queue, Worker o impresion requiere una autorizacion expresa y nueva.

## Fase 0 - Prevuelo de solo lectura

1. Verificar TEST, repositorio limpio y paquete `NAV-001A` en `origin/main`.
2. Confirmar que la instancia es `EbirTest` y que produccion queda fuera.
3. Reexportar los cinco objetos a una ubicacion protegida fuera de
   `C:\MES`, Git y `Z:\MES`.
4. Comparar los hashes con `README.md`; abortar ante cualquier diferencia.
5. Confirmar que el campo 700 de la tabla 50013 sigue libre.
6. Inventariar salidas `Pendiente`, `Procesando` y `Error` sin cambiar datos.
7. Confirmar que la Job Queue historica del Report 50056 sigue `En espera`.
8. Confirmar Worker ausente o detenido y Printing desactivado.

## Fase 1 - Materializacion protegida

Requiere autorizacion para editar objetos NAV TEST.

1. Guardar backup de objetos y hashes fuera de las rutas prohibidas.
2. Generar objetos de avance y rollback compatibles con el nuevo campo.
3. Aplicar exclusivamente `CHANGE-SPECIFICATION.md`.
4. Comparar el texto resultante y rechazar cambios ajenos.
5. No importar todavia.

## Fase 2 - Importacion y compilacion

Requiere otra autorizacion para importar y compilar en `EbirTest`.

1. Importar solo 50013, 50036, 50056, 60103 y 82000.
2. Sincronizar el cambio de tabla mediante la herramienta NAV autorizada; no
   escribir tablas NAV con SQL.
3. Compilar los cinco objetos en GUI y conservar el resultado.
4. Verificar metadatos WSDL/OData sin ejecutar operaciones.
5. Confirmar que `OpenClosePallet` no cambio de firma y que aparece
   `OpenClosePalletMES`.
6. Dejar todas las entradas de Job Queue detenidas.

## Fase 3 - Pruebas sin contabilizacion

1. Ejecutar pruebas de seleccion y reclamacion solo sobre fixtures acordados.
2. Verificar que el modo MES ignora salidas heredadas.
3. Verificar que no existe ninguna ruta MES hacia `ImprimirAlRegistrar`.
4. No abrir o cerrar bultos reales y no registrar diarios.

## Fase 4 - Canario de una salida

Requiere autorizacion que identifique la operacion MES y la salida NAV exactas.

1. Conciliar primero cualquier movimiento por `External Document No.`.
2. Exigir exactamente una salida MES futura y ninguna elegible adicional.
3. Crear una entrada Job Queue independiente para Report 50056 con
   `SoloSalidasMES=TRUE`, dejandola inicialmente `En espera`.
4. Ejecutarla una sola vez de forma controlada.
5. Exigir una sola reclamacion y como maximo una contabilizacion.
6. Confirmar `Registrado`, identificador estable y bulto cerrado.
7. Confirmar cero impresiones NAV y cero impresiones MES fisicas.
8. Devolver la entrada a `En espera` y verificar ausencia de trabajo residual.

## Fase 5 - Programacion continua

Solo despues del canario y con nueva autorizacion:

1. acordar intervalo y ventana operativa;
2. programar exclusivamente la entrada `SoloSalidasMES=TRUE`;
3. mantener la cola historica sin cambios;
4. observar al menos una salida completa y una ejecucion sin trabajo;
5. no activar el Worker continuo hasta validar el contrato conjunto.

## Recuperacion y rollback

- ante un resultado incierto, detener la cola y conciliar por identificador;
- no cambiar automaticamente `Procesando` a `Pendiente`;
- antes del primer uso del campo puede restaurarse el backup completo;
- despues de crear datos con `Origen MES`, el rollback debe conservar el campo
  700 y restaurar solo logica compatible; nunca eliminar datos por rollback;
- conservar objetos, logs y evidencias de compilacion;
- no restaurar un objeto de tabla antiguo si ello puede retirar el campo usado;
- cualquier importacion de rollback requiere autorizacion expresa.

## Evidencia minima

- commit y hashes del paquete;
- hashes de objetos antes y despues, sin guardar su contenido en Git;
- resultado de compilacion por objeto;
- metadatos que prueban compatibilidad de WSDL/OData;
- inventario previo y posterior de estados, sin datos personales;
- identificador exacto del unico canario;
- prueba de una contabilizacion, cero duplicados y cero impresiones.
