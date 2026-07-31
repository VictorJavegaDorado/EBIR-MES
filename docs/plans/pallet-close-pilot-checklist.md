# Checklist de piloto: cierre manual de palé

## Estado de preparación

Validado el 30/07/2026:

- flujo frontend integrado desde `App`;
- carga de reservas, empleados y supervisores desde la API;
- validaciones, estados de carga y tratamiento seguro de errores;
- conservación de correlación al reintentar sin cambios e invalidación al editar;
- confirmación visible del palé cerrado;
- cierre completo validado manualmente contra `EBIR_MES_TEST`;
- pruebas backend y frontend, TypeScript y build superados;
- release `20260730.1-86662f7` generada con manifiesto y hashes.

Validado el 31/07/2026:

- hosting conjunto API+SPA en `api\wwwroot`;
- rutas API, assets, fallback SPA y respuestas `404` cubiertas por cinco
  pruebas de integración;
- candidata `20260731.2-86662f7-combined-candidate` con 97 hashes verificados;
- prueba en loopback correcta con integraciones externas deshabilitadas.

La release no está activada. La candidata combinada procede de un árbol sin
commit y sirve únicamente como evidencia técnica. Consultar
`../../deploy/iis/PILOT-RUNBOOK.md` antes de cualquier cambio de IIS.

## Precondiciones

- `HEAD` validado y artefactos backend/frontend compilados.
- Paquete 014 aplicado en `EBIR_MES_TEST`.
- Conexión `MesDatabase` configurada fuera del repositorio.
- Integraciones reales de NAV, RFID e impresión desactivadas.
- Línea de prueba con sesión actual, empleados sintéticos y reserva activa.

## Prueba funcional

1. Identificar la línea y comprobar que solo aparecen sus reservas activas.
2. Confirmar que empleados y supervisores muestran únicamente roles vigentes.
3. Cerrar un palé completo y conservar palé y correlación confirmados.
4. Repetir la misma petición con la misma correlación y obtener el mismo palé.
5. Simular una respuesta perdida y reintentar sin cambiar los datos.
6. Editar cualquier dato y comprobar que se genera una correlación nueva.
7. Probar cierre parcial sin supervisor y verificar el bloqueo frontend.
8. Probar los rechazos `51400`–`51409`.
9. Probar los conflictos `55400`–`55404`.
10. Ejecutar dos cierres concurrentes sobre la misma reserva y verificar un
    único ganador.

## Evidencias

- Pruebas automatizadas backend y frontend.
- Capturas de carga, vacío, error, conflicto y éxito.
- Correlación, palé y códigos funcionales de cada caso.
- Un único palé y una única intención de impresión/NAV.
- Logs buscables por correlación sin datos personales ni detalles SQL.
- Manifiesto y hashes de la release candidata.

## Criterios de parada

- Cualquier duplicado de palé, trabajo o intención externa.
- Error que exponga SQL, credenciales o datos internos.
- Correlación distinta al reintentar una solicitud sin cambios.
- Replay directo de una correlación rechazada por conflicto.
- Opciones pertenecientes a otra línea o a una sesión no actual.

## Fuera del piloto

- No habilitar llamadas reales a NAV.
- No contactar RFID físico.
- No enviar trabajos a impresoras reales.
- No publicar hasta revisar las evidencias y aprobar el despliegue.
