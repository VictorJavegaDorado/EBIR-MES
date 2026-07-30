# Checklist de piloto: cierre manual de palé

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
