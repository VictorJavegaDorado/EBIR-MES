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

## Estado actual comprobado el 04/08/2026

La interfaz identifica linea, orden y empleados, pero conserva linea, orden y
equipo solo en el estado React del navegador. La identificacion RFID llama a
`POST /api/operator-identification/rfid`; no abre una sesion ni registra una
entrada productiva.

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

El contrato actual `POST /api/line-sessions` exige siempre `supervisorId`, y
`prod.abrir_sesion_linea` exige rol `SUPERVISOR`. Esto no coincide con la regla
confirmada de inicio por el primer operario. El siguiente corte debe revisar
ese contrato. La regla objetivo es:

- dentro del horario permitido, el primer empleado productivo activo puede
  abrir e iniciar la mesa;
- fuera de horario se mantiene una confirmacion explicita de supervisor;
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

Se necesita un contrato de lectura de estado de mesa, porque las respuestas
actuales de apertura y entrada solo devuelven identificadores. Esa lectura
debe incluir tiempos derivados del servidor y no credenciales RFID.

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

Esto requiere un paquete SQL versionado nuevo y autorizacion independiente
antes de instalarlo o escribir una nueva fase TEST.

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

1. lector ODataV4 POK, pruebas de contrato y resiliencia;
2. paquete SQL y snapshot/promocion del formato;
3. lectura backend del estado completo de mesa;
4. inicio atomico de mesa con el primer RFID productivo;
5. entradas, salidas y paros desde la misma pantalla;
6. cronometros e indicadores derivados del estado servidor;
7. paletizado ordinario y regla de ultimo palet con supervisor;
8. pruebas de recarga, reintento, concurrencia y cambio de capacidad;
9. candidate controlada, ensayo TEST y activacion con autorizaciones nuevas.
