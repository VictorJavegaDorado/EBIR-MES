# Worker continuo en TEST

Este runbook prepara el Worker de salidas NAV o de impresion como servicio Windows. No
autoriza instalarlo, iniciarlo, configurar secretos ni contactar NAV. Esas
acciones requieren autorización expresa y una release activable ya validada.

El contrato funcional e idempotente de la salida vive en
[`../../docs/modules/nav-pallet-output.md`](../../docs/modules/nav-pallet-output.md).

## Contrato del servicio

- nombre: `MES Worker`;
- identidad: cuenta integrada `NetworkService`, SID `S-1-5-20`;
- binario: ruta fija de una release validada, nunca `runtime\current`, para que
  una activación web no cambie el Worker de forma implícita;
- inicio: automático retrasado únicamente después del canario autorizado;
- entorno: `Production`;
- endpoint NAV: el adaptador solo admite
  `NAVISION2.EBIR.LOCAL:7147/EbirTest`, empresa `EBIR` y el codeunit de planta;
- línea piloto: un único mapeo explícito `LINEA-TEST-01` a `L01`;
- SQL: cadena con autenticación integrada y base explícita `EBIR_MES_TEST`,
  suministrada fuera de Git y de la release;
- perfiles mutuamente excluyentes: salida NAV o impresion Windows Spooler;
- perfil NAV: `NavisionOutput:Enabled=true` y `Printing:Enabled=false`;
- perfil impresion: `NavisionOutput:Enabled=false`, `Printing:Enabled=true`,
  `Printing:Mode=WindowsSpooler` y un unico mapeo de impresora explicito;
- ejecucion continua: el `RunOnce` del perfil activo debe ser `false`;
- apagado: cancelación cooperativa del host y de la operación en curso;
- observabilidad: Application Event Log, resultado e identificador de
  correlación, sin cuerpos externos, credenciales ni datos personales.

`Microsoft.Extensions.Hosting.WindowsServices` integra el host con el Service
Control Manager. En ejecución interactiva o `RunOnce` conserva el ciclo de vida
de consola utilizado por los canarios.

## Configuración protegida

La configuración específica del servicio debe suministrarse como variables de
entorno del propio servicio en el registro de Windows, bajo
`HKLM\SYSTEM\CurrentControlSet\Services\MES Worker\Environment`. El valor de
`ConnectionStrings__MesDatabase` no se muestra en terminal, comandos, logs ni
evidencias. La escritura de esta clave es una configuración de secretos y
requiere autorización expresa.

Las claves no secretas mínimas son:

```text
DOTNET_ENVIRONMENT=Production
NavisionOutput__Enabled=true
NavisionOutput__RunOnce=false
NavisionOutput__ServiceEndpoint=<endpoint TEST exacto admitido por el adaptador>
NavisionOutput__AssemblyLineMappings__LINEA-TEST-01=L01
Printing__Enabled=false
Printing__Mode=Disabled
```

Para el perfil de impresion validado en EbirTest son:

```text
DOTNET_ENVIRONMENT=Production
NavisionOutput__Enabled=false
Printing__Enabled=true
Printing__Mode=WindowsSpooler
Printing__RunOnce=false
Printing__PollIntervalMilliseconds=1000
Printing__WindowsSpooler__SubmissionTimeoutSeconds=15
Printing__WindowsSpooler__PrinterQueues__PRN-VRETTI-01=MES-VRETTI-420B-PILOT
```

Los dos perfiles no se habilitan simultaneamente. El instalador
`Install-MesPrintingWorker.ps1` solo instala el perfil de impresion y recibe la
cadena SQL como `SecureString`, de modo que no se escriba en comandos, Git ni
evidencias. El servicio apunta siempre al directorio `worker` de una release
exacta cuyo commit coincide con `HEAD == main == origin/main`.

Antes de instalar se resuelve el nombre localizado de `NetworkService` desde
el SID, sin asumir el idioma del servidor:

```powershell
$networkServiceSid = [System.Security.Principal.SecurityIdentifier]'S-1-5-20'
$networkServiceAccount = $networkServiceSid.Translate(
    [System.Security.Principal.NTAccount]).Value
```

## Prevuelo obligatorio

1. Exigir entorno TEST, repositorio limpio y `HEAD == origin/main`.
2. Leer todos los `AGENTS.md` aplicables y repetir el inventario de solo
   lectura de IIS, Worker, tareas y listeners temporales.
3. Verificar manifiesto, commit y todos los hashes de la release candidata.
4. Exigir que no exista el servicio `MES Worker` ni otro proceso Worker.
5. Confirmar que la cola seleccionada para el canario es inequívoca y que no
   puede reenviarse una salida ya existente; conciliar antes por identificador.
6. Confirmar configuracion exacta de TEST y que solo el perfil autorizado esta activo.
7. Preparar un procedimiento de parada y conservar la release anterior.

## Canario NAV `RunOnce`

El canario se ejecuta como tarea efímera bajo el SID `S-1-5-20`, con
`NavisionOutput:RunOnce=true`, Printing desactivado y una guarda exacta sobre
una única operación conocida. La tarea y el proceso deben desaparecer al
terminar.

La evidencia debe demostrar:

- una sola reserva de cola;
- reconciliación previa por identificador cuando exista;
- ningún segundo `RegistrarSalidaFabricacion` ante resultado incierto;
- endpoint y empresa de TEST;
- parada limpia, reserva liberada y estado final auditable;
- cero trabajos de impresión consumidos.

El canario y cualquier contacto con NAV o SQL requieren autorización expresa.

## Canario de impresion `RunOnce`

El canario de impresion se ejecuta como tarea efimera bajo `S-1-5-20`, con
`NavisionOutput:Enabled=false`, `Printing:RunOnce=true` y un unico trabajo
conocido elegible. Antes de cada salida se exige cola fisica vacia y se conserva
una copia verificada de `EBIR_MES_TEST`.

La evidencia debe demostrar una sola reserva, un solo intento, una sola pagina
en spool, cola vacia, confirmacion fisica y ausencia de Worker al terminar. Un
resultado SQL completado no autoriza a reenviar si el spool queda retenido: se
concilia primero con el operador y los eventos 307/842.

## Instalación e inicio

Solo después de un canario correcto y una nueva autorización se puede:

1. crear `MES Worker` apuntando al binario de la release exacta;
2. asignar la cuenta resuelta desde `S-1-5-20`, sin contraseña;
3. aplicar la configuración protegida específica del servicio;
4. configurar inicio automático retrasado y recuperación acotada;
5. iniciar el servicio;
6. observar una operación conocida hasta estado terminal;
7. comprobar que no quedan reservas y que solo el perfil autorizado esta activo.

Para el perfil de impresion, antes del primer inicio continuo se exige ademas
que no haya trabajos pendientes no autorizados, la cola VRETTI este vacia y el
lote historico haya sido conciliado. Tras iniciar, el servicio debe permanecer
`Running` con cero reservas y cero trabajos de spool cuando no haya trabajo.

No se cambia el `ImagePath` a otra release ni se inicia el servicio como parte
de una activación web.

## Parada y rollback

1. Solicitar `Stop-Service` y esperar como máximo el tiempo operativo acordado.
2. Confirmar proceso ausente y reserva liberada antes de cambiar el binario.
3. Si el servicio no termina, no matar el proceso a ciegas: inspeccionar el
   intento y el identificador externo para evitar un reenvío.
4. Restaurar `ImagePath` y configuración a la release anterior conservada.
5. Reiniciar solo con autorización y reconciliar primero cualquier resultado
   incierto.

La desinstalación, el cambio de identidad, el cambio de recuperación y el
rollback son cambios del servicio y requieren autorización expresa.
