# Salida de palet hacia NAV

## Objetivo

Después de cerrar un palet, MES persiste una intención `SALIDA_PALET`. Un
proceso en segundo plano debe transmitirla a NAV y confirmar localmente el
resultado antes de habilitar la etiqueta. El navegador nunca escribe en NAV.

## Estado preparado

El caso de uso `ProcessNextNavisionPalletOutput` separa la cola SQL del
adaptador NAV. El paquete 026A, instalado en `EBIR_MES_TEST`, reserva
operaciones de forma concurrente, registra intentos y aplica reintentos
acotados. `027A`, instalado y validado en `EBIR_MES_TEST`, amplía esa reserva
con lote, código NAV del operario que cerró el palet y código MES de línea.

El Worker integra un adaptador para el codeunit de planta, pero permanece
desactivado por defecto y no está instalado como servicio. La configuración de
líneas es explícita: en el piloto `LINEA-TEST-01` se mapea a `L01`. Los nombres
futuros de producción se configurarán de forma expresa; no se deducen por
formato ni por similitud.

Una confirmación exige un identificador externo. Solo entonces el procedimiento
existente `nav.confirmar_salida_palet` marca la operación como confirmada,
habilita la etiqueta y crea su trabajo de impresión. Un timeout posterior al
envío nunca repite el codeunit a ciegas.

## Contrato externo de escritura

La escritura correcta de TEST es el codeunit:

`http://Navision.EBIR.LOCAL:7147/EbirTest/WS/EBIR/Codeunit/WS_CPP_ControlPlanta`

Se realiza un único `POST` SOAP 1.1 a `RegistrarSalidaFabricacion`, con su
`SOAPAction` exacto y ocho parámetros en el orden del WSDL: orden, producto,
lote, cantidad, `Bin_Code`, unidad de medida base, código NAV del operario y
línea de montaje NAV. Todos proceden de MES o de lecturas NAV exactas; el
navegador no los aporta. Si NAV no informa `Bin_Code`, se envía vacío. Nunca se
sustituye por `Location_Code`, porque representan conceptos distintos.

Antes de escribir, el adaptador consulta ODataV4 en lectura:

- `WS_CPP_OPLanzadas`: exige una única orden y que producto y lote coincidan;
- `WS_CPP_Producto`: exige una única unidad de medida base no vacía;
- `WS_CPP_SalidasFabrica`: toma el mayor `Id` ya `Registrado` para la misma
  orden, producto y tipo `Salida`.

Una ausencia, ambigüedad o diferencia de datos bloquea el envío. Las lecturas
transitorias pueden reintentarse antes de escribir. El codeunit no se repite
después de una respuesta incierta.

La confirmación local exige que la llamada devuelva `true` o que, ante una
incertidumbre de transporte, la reconciliación lo demuestre, y que OData
publique exactamente una fila nueva `Registrado`, posterior al mayor `Id`
observado, con orden, producto y cantidad exactos. Cero filas, más de una fila,
truncamiento o fallo de lectura producen `RESULTADO_DESCONOCIDO` y mantienen
bloqueadas etiqueta e impresión. Un `false` del codeunit es error definitivo.

No se registran cuerpos completos, credenciales, identificadores RFID ni datos
personales. La configuración debe restringir el host a NAV TEST y permanecer
fuera de Git.

## Compatibilidad e idempotencia

El adaptador limita todos los endpoints a `Navision.EBIR.LOCAL:7147`, instancia
`EbirTest` y empresa `EBIR`, usa autenticación integrada y no sigue
redirecciones. Las respuestas tienen límite de tamaño y el XML se analiza sin
DTD ni resolución externa. El JSON técnico conserva solo resultado, motivo,
estado HTTP y mayor identificador previo; nunca incluye cuerpos NAV.

La clave idempotente MES sigue protegiendo el cierre local. Como el codeunit no
acepta esa clave, la barrera externa es la foto previa de identificadores y la
exigencia de una única fila nueva exacta. Un resultado desconocido requiere
reconciliación supervisada; nunca habilita otro envío automático.

## Primer rechazo y reencolación supervisada

El primer intento de la operación 31 usó por error `POST` ODataV4 y recibió
HTTP 405. MES lo registró como `ERROR_DEFINITIVO`, sin reserva ni identificador
externo; no hubo reintento automático.

El paquete 026B realizó una única reencolación supervisada con precondiciones
exactas sobre operación, orden, producto, cantidad, intento 1 y código 405.
Conservó el intento fallido y registró `NAV_SALIDA_REENCOLADA` en auditoría.
El intento 2 usó SOAP, pero recibió HTTP 500 porque el WSDL todavía no exponía
`Create`; MES no obtuvo identificador y OData confirmó cero filas.

## Publicación corregida y tercer intento

La página 50036 de NAV TEST se corrigió y compiló. Su WSDL publica `Create` y
`CreateMultiple`, no publica `Update` ni `Delete`, y conserva los tipos
`decimal` para `Cantidad_salida` y `dateTime` para `fecha`.

El paquete 026C, instalado el 2026-08-06 tras validación transaccional y backup
verificado, permitió exclusivamente el intento 3. El envío SOAP recibió HTTP
200 y una respuesta exacta con identificador positivo, pero estado `Pendiente`.
MES mantuvo por diseño la operación 31 en `RESULTADO_DESCONOCIDO`, liberó su
reserva y no habilitó etiqueta ni creó trabajo de impresión.

La reconciliación OData inmediata encontró exactamente una fila para
`FL26-00003`, producto `27920LG`, cantidad 20 y tipo `Salida`, también en estado
`Pendiente`. La escritura quedó por tanto registrada en NAV y no debe
repetirse. El siguiente contrato deberá consultar esa fila y confirmar
localmente solo ante un estado NAV inequívoco; mientras continúe `Pendiente`,
debe conservarse el bloqueo de etiqueta.
