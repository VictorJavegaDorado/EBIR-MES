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

Una confirmación exige un identificador externo y el bulto NAV cerrado. Solo
entonces el procedimiento existente `nav.confirmar_salida_palet` marca la
operación como confirmada, habilita la etiqueta y crea su trabajo de impresión.
Un timeout posterior al envío nunca repite el codeunit a ciegas.

## Contrato externo de escritura

La escritura correcta de TEST es el codeunit:

`http://Navision.EBIR.LOCAL:7147/EbirTest/WS/EBIR/Codeunit/WS_CPP_ControlPlanta`

El cierre completo usa tres operaciones SOAP 1.1 del mismo codeunit:

- `IsOpenPallet`, de solo lectura, consulta el bulto exacto por orden y línea;
- `OpenClosePallet` cambia una sola vez entre abierto y cerrado, con orden,
  operario, producto, cantidad parcial cero y línea de montaje;
- `RegistrarSalidaFabricacion` registra la salida con los ocho parámetros del
  WSDL: orden, producto, lote, cantidad, `Bin_Code`, unidad de medida base,
  código NAV del operario y línea de montaje NAV.

Todos los valores proceden de MES o de lecturas NAV exactas; el navegador no
los aporta. Si NAV no informa `Bin_Code`, se envía vacío. Nunca se sustituye
por `Location_Code`, porque representan conceptos distintos.

Antes de registrar, MES exige observar el bulto abierto. Si estaba cerrado,
ejecuta un solo `OpenClosePallet` y vuelve a consultar `IsOpenPallet`; no repite
el cambio ante una respuesta incierta. Después del intento de salida comprueba
y cierra el bulto con la misma regla. Una salida observada conserva su
identificador aunque el cierre del bulto quede incierto, para que una ejecución
posterior reconcilie y cierre sin repetir `RegistrarSalidaFabricacion`.

Antes de escribir, el adaptador consulta ODataV4 en lectura:

- `WS_CPP_OPLanzadas`: exige una única orden y que producto y lote coincidan;
- `WS_CPP_Producto`: exige una única unidad de medida base no vacía;
- `WS_CPP_SalidasFabrica`: toma el mayor `Id` ya `Registrado` para la misma
  orden, producto y tipo `Salida`.

`Cód_Lote_Salida` puede llegar vacío desde NAV. En ese caso no bloquea la
salida y MES conserva el lote trazable ya persistido en la orden para enviarlo
al codeunit. Si NAV informa un lote no vacío distinto del lote MES, el
adaptador mantiene el bloqueo por discrepancia.

Una ausencia, ambigüedad o diferencia de datos bloquea el envío. Las lecturas
transitorias pueden reintentarse antes de escribir. El codeunit no se repite
después de una respuesta incierta.

La confirmación local exige que la reconciliación OData publique exactamente
una fila nueva `Registrado`, posterior al mayor `Id` observado, con orden,
producto y cantidad exactos, y que `IsOpenPallet` confirme el bulto cerrado.
La respuesta booleana del codeunit no es prueba suficiente: en TEST se ha
observado que puede devolver `false` después de crear una salida `Pendiente`.
Por ello tanto `true` como `false` continúan hacia la reconciliación y el
codeunit nunca se repite dentro del intento. Una fila nueva `Pendiente` conserva
su identificador como `RESULTADO_DESCONOCIDO`; cero filas, más de una fila,
bulto con estado incierto, truncamiento o fallo de lectura producen igualmente
`RESULTADO_DESCONOCIDO` y mantienen bloqueadas etiqueta e impresión.

La publicación OData posterior al codeunit puede demorarse. MES realiza una
ventana acotada de once observaciones durante aproximadamente treinta segundos,
sin repetir la escritura. En cuanto aparece una única fila exacta `Pendiente`,
conserva inmediatamente su identificador para las conciliaciones posteriores;
no espera a que NAV la registre dentro del mismo intento.

La operación 34 confirmó que una ventana de aproximadamente cinco segundos no
era suficiente: NAV creó una sola salida, 26840, que OData publicó después de
la última observación. El paquete 032A vincula exclusivamente esa operación con
la fila ya existente y mantiene el flujo en modo de solo conciliación; no
repite `RegistrarSalidaFabricacion` ni habilita por sí mismo la impresión.

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

## Reconciliación diferida y continuidad operativa

El paquete 028A y el Worker distinguen entre enviar y reconciliar. Una
operación `RESULTADO_DESCONOCIDO` que ya contiene identificador externo se
reserva de nuevo exclusivamente para una lectura OData exacta por `Id`; nunca
se repite `RegistrarSalidaFabricacion`. Si NAV todavía publica `Pendiente`, la
operación conserva el identificador y programa otra lectura. Cuando publica
una única fila exacta `Registrado`, MES confirma la salida, habilita la
etiqueta y conserva toda la auditoría de intentos.

La salida NAV y el estado operativo de la línea quedan desacoplados. Cerrar un
palet no final no cambia una línea `PRODUCIENDO` o `SIN_OPERARIOS` a
`PENDIENTE_NAV`, por lo que los fichajes y el tiempo productivo continúan. Para
mantener la secuencia y evitar duplicados, no se permite cerrar el siguiente
palet de la misma sesión mientras exista una salida anterior distinta de
`CONFIRMADA`. El último palet mantiene el bloqueo de cierre de orden hasta la
confirmación externa.

Para una orden de 100 unidades con POK 20, el resultado esperado son cinco
palets MES y cinco filas NAV independientes en estado final `Registrado`.

## Segundo palet y recuperación supervisada

El primer intento de la operación 32, palet 22 de `FL26-00003`, envió
`RegistrarSalidaFabricacion` sin gestionar antes el bulto NAV. `EbirTest`
respondió HTTP 500 con el error funcional de que no existía ningún bulto
abierto. Tres lecturas OData posteriores demostraron que no se creó una nueva
salida: la orden conservó solo la fila registrada del primer palet. MES dejó
la operación en `RESULTADO_DESCONOCIDO`, intento 1, sin identificador externo;
la mesa continuó `PRODUCIENDO` y la etiqueta siguió `PENDIENTE_NAV`.

El paquete 029A prepara una única reencolación supervisada de esa operación.
Comprueba operación 32, palet 22, cantidad 20, ausencia de identificador y
reserva, HTTP 500, adaptador, resultado, motivo y mayor identificador previo.
Conserva el intento original y registra auditoría. El paquete no contacta NAV
ni autoriza el siguiente envío; instalación y ensayo real son fases separadas.

El intento 2 gestionó correctamente el ciclo del bulto: lo abrió, ejecutó una
sola vez `RegistrarSalidaFabricacion` y comprobó su cierre. El codeunit respondió
HTTP 200 con valor `false`, pero OData publicó exactamente la nueva fila 26838,
cantidad 20 y estado `Pendiente`. La versión anterior clasificó el booleano como
rechazo definitivo antes de reconciliar y no conservó ese identificador. La
salida existe y no debe reenviarse.

El paquete 030A recupera exclusivamente esa operación como
`RESULTADO_DESCONOCIDO` con el identificador externo ya observado. Una
ejecución posterior entra solo por reconciliación OData por `Id`: mientras NAV
mantenga `Pendiente` conserva el bloqueo; cuando NAV publique `Registrado`, MES
confirma, habilita la etiqueta y no repite el codeunit.

## Tercer palet y latencia de publicación OData

El intento 1 de la operación 33 ejecutó una sola vez el ciclo completo del
bulto y recibió HTTP 200 en todas las llamadas. Las tres observaciones OData de
la versión anterior terminaron antes de que NAV publicara la nueva salida. Poco
después se observó exactamente la fila 26839, cantidad 20 y estado `Pendiente`;
el bulto permanecía cerrado. La operación quedó `RESULTADO_DESCONOCIDO` sin
identificador, por lo que no es elegible para reenvío ni conciliación automática.

El paquete 031A vincula exclusivamente la operación 33 con la fila 26839 y la
mantiene en modo de solo reconciliación. No contacta NAV ni habilita impresión.
Cuando la fila pase a `Registrado`, una conciliación por identificador podrá
confirmar la operación y liberar la etiqueta sin repetir
`RegistrarSalidaFabricacion`.

## Quinto palet final y lote NAV vacío

El cierre del palet 25, número 5, registró correctamente su carácter final y
la autorización de supervisor. El intento 1 de la operación 35 realizó una
única lectura de `WS_CPP_OPLanzadas` y terminó antes de abrir el bulto o llamar
al codeunit: NAV devolvió la orden exacta con `Cód_Lote_Salida` vacío y el
adaptador anterior lo trató como una respuesta OData inválida. No se creó una
quinta salida NAV.

El paquete 033A reencola exclusivamente esa operación conservando el intento
original y auditando la recuperación. La versión corregida permite el lote NAV
vacío, pero sigue exigiendo el lote trazable MES y bloquea cualquier lote NAV
no vacío que discrepe. Instalación, activación y nuevo ensayo permanecen como
fases separadas.
