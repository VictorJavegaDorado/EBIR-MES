# Salida de palet hacia NAV

## Objetivo

Después de cerrar un palet, MES persiste una intención `SALIDA_PALET`. Un
proceso en segundo plano debe transmitirla a NAV y confirmar localmente el
resultado antes de habilitar la etiqueta. El navegador nunca escribe en NAV.

## Estado preparado

El caso de uso `ProcessNextNavisionPalletOutput` separa la cola SQL del
adaptador NAV. El paquete 026A, instalado en `EBIR_MES_TEST`, reserva
operaciones de forma concurrente, registra intentos y aplica reintentos
acotados. El Worker integra un adaptador SOAP para
`WS_CPP_SalidasFabrica`, pero permanece desactivado por defecto y no está
instalado como servicio.

Una confirmación exige un identificador externo. Solo entonces el procedimiento
existente `nav.confirmar_salida_palet` marca la operación como confirmada,
habilita la etiqueta y crea su trabajo de impresión. Los errores 408, 429 y 5xx
se clasifican como `RESULTADO_DESCONOCIDO`, porque la página no expone un campo
para la clave idempotente MES. Un timeout posterior al envío tampoco se repite
a ciegas.

## Contrato externo de escritura

La página TEST de escritura es:

`http://Navision.EBIR.LOCAL:7147/EbirTest/WS/EBIR/Page/WS_CPP_SalidasFabrica`

Se realiza un único `POST` SOAP 1.1 con la operación `Create`, `SOAPAction`
exacto y los campos `Orden`, `Producto`, `Cantidad_salida`, `fecha` y
`Tipo = Salida`. NAV conserva la autoridad sobre sus campos de estado. Orden,
producto, cantidad y fecha proceden del palet y la orden persistidos en MES, no
del navegador. La respuesta solo se confirma si `Create_Result` devuelve un
`Id` positivo, repite exactamente orden, producto, cantidad y tipo, y su estado
es `Registrado`.

La publicación ODataV4 con el mismo nombre se usa solo para lectura y
reconciliación. El ensayo del 2026-08-06 confirmó que rechaza escritura con HTTP
405. DATACPP y el WSDL de la página exponen la escritura mediante SOAP
`Create`.

Una fila SOAP devuelta como `Pendiente` conserva su `Id` y queda en
`RESULTADO_DESCONOCIDO` para reconciliación; no se repite el alta. Una fila en
`Error` se registra como error definitivo sin exponer el texto de NAV.

Queda pendiente definir una reconciliación manual o de solo lectura para los
resultados desconocidos. La combinación funcional no es una clave única y no
autoriza una repetición automática.

No se registran cuerpos completos, credenciales, identificadores RFID ni datos
personales. La configuración debe restringir el host a NAV TEST y permanecer
fuera de Git.

## Primer rechazo y reencolación supervisada

El primer intento de la operación 31 usó por error `POST` ODataV4 y recibió
HTTP 405. MES lo registró como `ERROR_DEFINITIVO`, sin reserva ni identificador
externo; no hubo reintento automático.

El paquete 026B permite una única reencolación supervisada con precondiciones
exactas sobre operación, orden, producto, cantidad, intento 1 y código 405.
Conserva el intento fallido, registra `NAV_SALIDA_REENCOLADA` en auditoría y
deja que SOAP `Create` sea el intento 2. Preparar el paquete no autoriza su
instalación ni un nuevo envío.
