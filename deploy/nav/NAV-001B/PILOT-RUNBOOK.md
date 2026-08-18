# Runbook NAV-001B en EbirTest

Este documento no autoriza ejecutar sus fases. Cada bloque que cambie objetos,
Web Services o Job Queue requiere una autorizacion expresa y nueva.

## Fase 0 - Prevuelo de solo lectura

1. Verificar `HEAD=origin/main`, worktree limpio y paquete NAV-001B exacto.
2. Confirmar instancia `EbirTest`, empresa `EBIR` y produccion fuera de alcance.
3. Confirmar Worker, servicio y tareas MES ausentes o detenidos.
4. Confirmar Printing desactivado.
5. Exportar a ubicacion protegida Report 50056 y Table 472.
6. Inventariar IDs de codeunit libres y licencia; resolver
   `OBJECT_ID_PENDING_INVENTORY` o abortar.
7. Inventariar entradas para Report 50056, descripcion MES y nuevo codeunit.
8. Confirmar que la cola historica sigue `En espera` y no tocarla.

## Fase 1 - Materializacion protegida

Requiere autorizacion independiente.

1. Guardar backups y hashes fuera de `C:\MES`, Git y `Z:\MES`.
2. Agregar solo `SetSoloSalidasMES` al Report 50056.
3. Crear el codeunit con el ID inventariado y el contrato de la especificacion.
4. Comparar objetos completos y rechazar cambios ajenos.
5. Preparar rollback compatible.
6. No importar, compilar, publicar ni ejecutar.

## Fase 2 - Importacion y compilacion

Requiere otra autorizacion independiente.

1. Repetir hashes e inventario de entradas.
2. Importar exclusivamente Report 50056 y el nuevo codeunit.
3. Compilar ambos objetos en GUI NAV de `EbirTest`.
4. No crear todavia el registro Web Service.
5. No ejecutar el report ni el codeunit.
6. Conservar evidencia de compilacion y objetos protegidos.

## Fase 3 - Publicacion administrativa detenida

Requiere otra autorizacion independiente.

1. Crear el registro `WS_MES_JobQueueAdmin` inicialmente no publicado.
2. Verificar empresa, tipo e ID exactos.
3. Publicarlo solo en `EbirTest`.
4. Inspeccionar WSDL sin invocar operaciones.
5. Exigir `EnsureStoppedMesEntry` y ausencia de operaciones para iniciar colas.
6. No publicar Page 672.

## Fase 4 - Creacion de la entrada detenida

Requiere autorizacion de una unica llamada SOAP administrativa.

1. Inventariar de nuevo entradas coincidentes.
2. Abortar ante cualquier coincidencia parcial, duplicada o ambigua.
3. Invocar `EnsureStoppedMesEntry` una sola vez.
4. Ante respuesta incierta, consultar antes de repetir.
5. Verificar todos los invariantes y estado `En espera`.
6. Confirmar cero tareas programadas y cero ejecuciones.
7. Mantener el Web Service bajo la politica acordada; no asumir que debe quedar
   publicado permanentemente.

## Fase 5 - Canario productivo futuro

No forma parte de NAV-001B preparado. Exige una operacion MES futura exacta,
inventario sin ambiguedades y autorizacion para iniciar una unica ejecucion.
La salida debe quedar `Registrado`, sin duplicados y sin impresion NAV o fisica.

## Recuperacion y rollback

- ante incertidumbre, no repetir la funcion sin inventariar la entrada;
- nunca cambiar una entrada divergente automaticamente;
- despublicar primero el Web Service ante cualquier anomalia;
- una entrada nunca ejecutada solo puede borrarse tras verificar ID, token,
  estado `En espera`, cero intentos y tarea de sistema vacia;
- despues de una ejecucion conservar la entrada y evidencias hasta aprobar un
  rollback compatible;
- restaurar Report 50056 solo mediante backup versionado y autorizacion;
- no escribir ni reparar tablas NAV con SQL.

## Evidencia minima

- commit NAV-001B y resultado de prueba estatica;
- ID elegido y prueba de licencia/libertad;
- hashes antes y despues de los dos objetos;
- compilacion por objeto;
- WSDL limitado;
- inventario previo y posterior de Job Queue;
- resultado SOAP sin cuerpos ni credenciales;
- prueba de estado detenido, cero tareas y cero ejecuciones.
