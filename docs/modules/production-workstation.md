# Mesa de produccion

## Objetivo funcional confirmado

La pantalla de produccion es una mesa unica de trabajo. El operario no debe
navegar entre modulos ni reconstruir el estado del proceso. Desde ella se
identifican, en orden, la linea, la orden y la capacidad humana; despues se
gestionan el equipo activo, los tiempos, los paros y los pales.

El contrato confirmado es:

1. identificar una linea MES activa;
2. seleccionar una orden MES disponible;
3. resolver el formato de palet `POK` asociado al producto;
4. identificar personas mediante RFID;
5. la primera persona productiva abre la mesa y empieza a contar tiempo;
6. cada persona posterior modifica la capacidad desde su propia entrada;
7. las salidas y los paros modifican la capacidad sin perder el acumulado;
8. los pales se gestionan dentro de la misma mesa;
9. cualquier operario activo puede cerrar un palet ordinario;
10. el ultimo palet requiere autorizacion de supervisor.

## Estado de implementacion preparado el 05/08/2026

La release activa identifica linea, orden y empleados, pero todavia conserva
el equipo solo en el estado React del navegador. El corte preparado en el
repositorio añade `POST /api/production-workstations/start-or-join`: despues
de resolver el RFID, el navegador envia solo los identificadores internos de
orden, linea y empleado con una correlacion nueva.

El procedimiento versionado `prod.iniciar_o_incorporar_mesa` crea la sesion y
el primer fichaje dentro de la misma transaccion, o incorpora el operario a la
sesion activa de la misma orden y linea. Reutiliza
`prod.registrar_entrada_productiva`, por lo que el primer recurso inicia el
tramo de capacidad, cambia el estado a `PRODUCIENDO` y reserva el primer pale.
El paquete 023A esta preparado, pero no se considera instalado ni activo hasta
completar la fase SQL y la activacion expresamente autorizadas.
El mismo paquete inicializa de forma idempotente el estado `LIBRE` de cualquier
linea activa que aun no tenga fila en `prod.estados_linea`; no altera estados
ya persistidos.

Para la orden TEST `FL26-00002` se comprobo en lectura:

- orden productiva existente y en estado `IMPORTADA`;
- cero sesiones de linea;
- cero fichajes productivos;
- cero tramos de capacidad;
- cero formatos de palet activos.

Por tanto, la pantalla actual no cuenta tiempo por detras. El backend dispone
de contratos separados para abrir sesion y registrar entradas, pero el
frontend todavia no los consume.

## Inicio productivo y atomicidad

El primer RFID productivo debe realizar una unica intencion funcional:
"iniciar o incorporarse a la mesa". El servidor debe garantizar que la
sesion y el primer fichaje quedan creados conjuntamente o que una repeticion
con la misma correlacion completa de forma segura el estado pendiente. No se
debe mostrar `PRODUCIENDO` hasta recibir confirmacion del servidor.

El contrato administrativo `POST /api/line-sessions` conserva la apertura por
supervisor. La mesa usa un contrato distinto y limitado a operarios
productivos ordinarios. La regla aplicada es:

- dentro del horario permitido, el primer empleado productivo activo puede
  abrir e iniciar la mesa;
- fuera de 06:00-22:00 el inicio desde la mesa queda bloqueado; la excepcion
  operativa sigue perteneciendo al flujo de supervisor existente;
- el iniciador queda auditado con su rol efectivo;
- el mismo RFID no puede crear dos fichajes ni dos sesiones por reintento.

La implementacion debe preferir un caso de uso transaccional de nivel mesa que
orqueste apertura y primera entrada. Encadenar dos llamadas independientes
desde el navegador puede dejar una sesion `CARGADA` sin fichaje si la segunda
llamada falla.

## Modelo de tiempo y capacidad

No hace falta escribir en SQL cada segundo. Cada cambio abre o cierra un tramo
con marcas UTC; los acumulados se calculan a partir de esos intervalos.

La mesa debe distinguir y mostrar:

- tiempo productivo total de la orden/sesion: tiempo con al menos un recurso
  productivo activo;
- tiempo productivo individual: intervalos de cada empleado, descontando sus
  paros;
- tiempo de capacidad: suma de segundos-recurso de los tramos;
- capacidad actual: numero de recursos productivos activos;
- capacidad teorica por hora calculada con el tiempo NAV de la orden;
- estado del servidor: `CARGADA`, `PRODUCIENDO`, `SIN_OPERARIOS`, `STANDBY`,
  `PICO_PENDIENTE` o estado final aplicable.

La entrada de una segunda persona cierra el tramo de capacidad 1 y abre otro
de capacidad 2. La salida o el inicio de paro hace la transicion inversa. Si no
queda ningun recurso productivo, el tiempo productivo total deja de avanzar
hasta una nueva entrada o fin de paro.

## Estado visible y prevencion de errores

La pantalla debe obtener del servidor una vista de mesa recuperable tras
recargar el navegador. El estado local no puede ser la autoridad.

Como minimo debe mostrar:

- indicador destacado `PRODUCIENDO` o el estado efectivo;
- cronometro total y ultima actualizacion del servidor;
- capacidad actual;
- personas activas con tiempo individual y estado `PRODUCIENDO` o `EN PARO`;
- paros activos y su motivo;
- formato POK y unidades por palet;
- palet/reserva activa, cantidad y progreso;
- acciones habilitadas solo cuando el estado del servidor las admite.

Cada mutacion usa una correlacion estable durante los reintentos. Mientras una
operacion esta pendiente se bloquea el boton o lector correspondiente. Un
error debe conservar linea, orden y mesa, mostrar un codigo funcional seguro y
permitir reintentar sin duplicar datos.

## Recorrido simplificado del terminal

El piloto presenta unicamente tres pasos: `Linea`, `Orden` y `Trabajo`.
Identificacion RFID, tiempos, paros y paletizacion conviven dentro de Trabajo;
el operario no navega a una pantalla de pales ni a un paso NAV. La mesa sigue
siendo recuperable desde el servidor al recargar.

Las reservas de pale permanecen como garantia tecnica de concurrencia e
idempotencia, pero no son un concepto visible ni seleccionable. La interfaz
resuelve la unica reserva activa de la sesion, presenta `POK` y propone su
cantidad. El operario puede editarla; una cantidad distinta exige el motivo
funcional que valida el servidor.

NAV se representa mediante mensajes de estado en segundo plano. Registrar un
pale no implica que el navegador contacte NAV ni impresion. Al terminar la
orden, la accion principal sera `Nueva orden`, que conserva la linea; cambiar
de linea queda como accion secundaria. Mientras haya operarios activos no se
permite abandonar la orden desde esa accion.

`GET /api/production-workstations/state?orderId=...&lineId=...` devuelve la
sesion activa, reloj del servidor, segundos productivos, recursos efectivos,
capacidad teorica, POK y operarios activos. Los cronometros avanzan localmente
desde esa instantanea UTC; no generan escrituras periodicas. La respuesta no
incluye credenciales RFID.

La pantalla refresca esa instantanea cada 10 segundos para recoger cambios
realizados desde otro terminal. Un fallo puntual conserva el ultimo estado
confirmado y se reintenta en el siguiente ciclo. Entre instantaneas, la
proyeccion visual avanza cada segundo desde un ancla monotona tomada por el
navegador al recibir la respuesta. No resta la hora del terminal a la hora UTC
del servidor, por lo que un desfase entre ambos relojes no produce saltos de 10
segundos. La siguiente lectura reconcilia siempre el valor con el acumulado
autoritativo del servidor.

Solo avanza localmente el tiempo total cuando el servidor confirma
`PRODUCIENDO` con recursos activos y el tiempo individual de las personas cuyo
estado es `PRODUCIENDO`; una persona `EN_PAUSA` mantiene su acumulado congelado.
El estado visible nunca se sustituye por un `PRODUCIENDO` calculado o fijo en
el navegador. `serverTimeUtc` se conserva para mostrar la ultima confirmacion,
pero no es la base del cronometro animado.

Cada persona visible dispone de acciones tactiles de salida, pausa `WC`, pausa
`PAUSA_CALOR` y reanudacion segun su estado. La pantalla usa los contratos de
sesion existentes, conserva la correlacion durante un reintento y vuelve a leer
la mesa despues de cada mutacion. El resultado visual siempre procede de esa
lectura posterior del servidor.

La tarjeta representa a la persona mediante un avatar circular con sus
iniciales; este corte no consulta ni persiste fotografias. Cuando la persona
esta productiva, la misma tarjeta ofrece `Cerrar palet`. La accion abre un
dialogo dentro de Trabajo, conserva visible el estado de NAV en segundo plano,
preselecciona al autor material y dirige el foco a la cantidad propuesta. El
autor no se elige de nuevo en el formulario y se vuelve a validar contra las
opciones activas devueltas por el servidor. Una persona en pausa conserva su
tarjeta y su accion de reanudacion, pero no puede iniciar un cierre mientras el
paro permanezca abierto.

El dialogo bloquea el cierre accidental durante el envio, contiene la
navegacion de foco, admite cancelacion y devuelve el foco a la tarjeta que lo
abrio. Tras una confirmacion muestra el resultado antes de volver a la mesa.
Cambiar de linea u orden, o dejar de recibir al autor en el estado del servidor,
descarta el dialogo para evitar operar con un contexto obsoleto.

El tiempo individual es el acumulado de todos los fichajes del empleado dentro
de la misma sesion de linea. Una salida cierra el intervalo actual y una nueva
identificacion abre otro, pero no reinicia el contador visible. De cada fichaje
se descuenta la duracion de sus paros. Solo se muestran personas con un fichaje
abierto, aunque su acumulado incluya intervalos anteriores ya cerrados.

## Formato de palet desde NAV

El formato se obtiene exclusivamente en lectura mediante ODataV4:

`WS_CPP_UndMedProd`

Raiz TEST:

`http://Navision.EBIR.LOCAL:7147/EbirTest/ODataV4/Company('EBIR')/`

La consulta debe filtrar de forma exacta por el producto de la orden y por
`Code eq 'POK'`. Los campos funcionales iniciales son:

- `Item_No`: producto NAV;
- `Code`: debe ser `POK`;
- `Qty_per_Unit_of_Measure`: unidades por palet.

La lectura real autorizada del 04/08/2026 devolvio una coincidencia para el
producto de prueba `27924LG`, codigo `POK` y cantidad `25`. Ese producto es una
prueba especifica del contrato de unidades y no es el producto de
`FL26-00002`.

La respuesta debe contener exactamente una coincidencia, el producto debe
coincidir de forma ordinal con la orden y la cantidad debe ser positiva,
entera y representable por el contrato MES. Cero o varias coincidencias
bloquean la apertura de mesa con un codigo funcional; MES no inventa un
formato.

La autenticacion usa la identidad del proceso. Se aplican filtro exacto,
limite, JSON seguro y reintentos solo para timeout, transporte, 408, 429 y 5xx.
NAV permanece estrictamente en lectura y no se registra el cuerpo completo.

## Persistencia propuesta del formato

El formato POK debe formar parte del snapshot idempotente de la orden, no de
una consulta tardia al abrir la linea. El corte propuesto es:

1. leer POK junto con cabecera, linea, ruta y componentes;
2. persistirlo en una bandeja de entrada versionada;
3. incluirlo en el hash del snapshot;
4. crear o revisar `prod.formatos_palet_orden` durante la promocion;
5. exponer el formato activo en la lectura de orden/mesa.

Los puntos 1 a 4 estan implementados. El paquete versionado 022 esta instalado
y validado en `EBIR_MES_TEST`, y la release activa
`20260805.0-cbfc35d-combined` contiene el lector y la promocion POK. El punto 5
queda implementado por el corte de mesa y pendiente de instalar/activar junto
con el paquete 023A.

## Paletizado y autorizacion

El servidor determina si el cierre corresponde al ultimo palet a partir del
objetivo, cantidades buenas, reservas y cierres ya persistidos; el navegador
no puede declarar por si solo que un palet no es el ultimo.

- palet ordinario: lo cierra cualquier operario productivo activo de la mesa;
- ultimo palet: exige supervisor activo y queda auditado;
- repeticion: misma correlacion y mismos parametros devuelve el mismo cierre;
- cambio de cantidad, autor o motivo invalida la correlacion anterior.

La politica anterior que exigia supervisor para cualquier cierre parcial debe
revisarse frente a esta regla funcional. No se habilitan NAV, etiquetas,
impresion ni Worker como consecuencia de este diseño.

## Cortes de implementacion recomendados

1. validar e instalar 023A en `EBIR_MES_TEST` con autorizacion SQL nueva;
2. probar inicio, repeticion idempotente e incorporacion con rollback;
3. crear candidate y ensayar la API bajo `NetworkService` sin activar IIS;
4. activar solo con autorizacion nueva y probar el primer RFID en TEST;
5. incorporar salidas y paros a la misma pantalla;
6. integrar palets y autorizacion de ultimo palet;
7. completar recuperacion de contexto tras recargar el navegador;
8. probar concurrencia y todos los cambios de capacidad.
