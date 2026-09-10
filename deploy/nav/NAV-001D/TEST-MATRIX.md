# Matriz de pruebas NAV-001D

## Estaticas

- baseline actual de Codeunit 82000 y Codeunit 453 identificado por SHA-256;
- forward cambia solo Codeunit 82000 y agrega una unica funcion publica;
- la validacion acepta la hora inicial configurada `00:00:00` y rechaza una
  hora inicial posterior;
- una entrada exacta en `Ready` puede reprogramarse con `Scheduled=FALSE`; una
  entrada en espera o con contrato distinto sigue bloqueada;
- MES cierra y verifica el bulto antes de observar la salida posterior al unico
  envio, y conserva el identificador aunque el cierre quede incierto;
- no aparecen llamadas a Report 50056, registro directo, impresion o SQL en la
  nueva funcion;
- endpoint MES permanece fijado a `EbirTest / EBIR` y el interruptor por defecto
  es `false`;
- pruebas .NET simulan NAV y no contactan servicios reales.

## Compilacion y WSDL

- importar y compilar solo Codeunit 82000 en EbirTest;
- confirmar que el WSDL de `WS_CPP_ControlPlanta` conserva sus operaciones y
  agrega exactamente `TriggerMesEntryNow` con
  `salidaId` entero;
- confirmar que Codeunit 50009, Codeunit 453, Report 50056 y las otras entradas no cambian.

## Canario funcional

1. partir de cero salidas MES no terminales y cola de impresion vacia;
2. cerrar un unico palet conocido;
3. demostrar una llamada a `TriggerMesEntryNow` para su ID;
4. demostrar que la tarea se ejecuta como `EBIR\NAVEBIR`;
5. observar una sola transicion a `Registrado`, un solo movimiento y una sola
   etiqueta;
6. medir cierre a registro y cierre a impresion;
7. repetir con el interruptor apagado para demostrar el respaldo de un minuto;
8. probar respuesta SOAP incierta sin repetir `RegistrarSalidaFabricacion`.
