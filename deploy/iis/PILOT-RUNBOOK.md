# Preparación del piloto en IIS

Este documento describe el estado preparado y los pasos que requieren una
autorización explícita antes de activar el piloto.

## Estado verificado

- El sitio `MES` está iniciado y enlazado a `https://MES.EBIR.LOCAL`.
- El sitio apunta a `C:\MES\runtime\bootstrap`.
- El application pool `MES` usa `NetworkService`.
- `AspNetCoreModuleV2` está instalado.
- `C:\MES\runtime\current` todavía no es un enlace a una versión.
- La release final combinada debe tener en su manifiesto el mismo commit que
  `HEAD`; el preflight muestra las versiones disponibles para comprobarlo.
- `NetworkService` accede a SQL como `EBIR\MES$` y conecta exclusivamente a
  `EBIR_MES_TEST`.
- La cuenta tiene los ocho permisos específicos requeridos: lectura de las
  tablas de opciones y ejecución de `prod.cerrar_palet_idempotente`, sin
  permisos globales de lectura, escritura o ejecución.
- El servicio `MES Worker` no está instalado.

Ejecutar la comprobación de solo lectura:

```powershell
$expectedCommit = (& git -C C:\MES rev-parse HEAD).Trim()
powershell -ExecutionPolicy Bypass -File C:\MES\deploy\iis\Get-PilotPreflight.ps1 `
  -ExpectedCommit $expectedCommit
```

## Estado del routing y bloqueo de activación

El bloqueo técnico de hosting conjunto está resuelto en `main`:

- la publicación de la API incorpora el frontend en `api\wwwroot`;
- la API sirve archivos estáticos;
- las rutas `/api/*` conservan prioridad y nunca reciben el fallback SPA;
- las rutas de navegación sin extensión reciben `index.html`;
- los assets inexistentes y las API desconocidas devuelven `404`;
- cinco pruebas de integración cubren estos casos;
- la candidata `.2` fue verificada en loopback sin modificar IIS.

La release final procede de un commit limpio, está publicada y sus 97 hashes
han sido verificados sin discrepancias. Todavía no debe activarse: sigue
pendiente aplicar la configuración externa junto con la autorización de IIS y
el rollback controlado.

Las candidatas
`20260731.0-86662f7-combined-candidate` y
`20260731.1-86662f7-combined-candidate` son inválidas y nunca deben activarse.
La `.0` tiene un CSV de hashes con esquema incorrecto. La `.1` se generó con dos
invocaciones simultáneas del mismo ID y contiene un directorio de trabajo
anidado. El generador mantiene ahora un bloqueo exclusivo por `ReleaseId`.

## Configuración externa preparada

- Proporcionar `ConnectionStrings__MesDatabase` como variable del application
  pool, fuera del repositorio y de la release.
- Usar autenticación integrada, base explícita `EBIR_MES_TEST`,
  `Encrypt=True` y, solo durante el piloto autorizado,
  `TrustServerCertificate=True`.
- La instancia SQL no tiene un certificado configurado y la validación TLS
  estricta falla. La excepción anterior es temporal y debe retirarse antes de
  producción instalando un certificado confiable en SQL Server.
- Mantener deshabilitadas las integraciones NAV/OData, RFID e impresoras
  durante las pruebas del piloto preparatorio.
- No instalar el Worker hasta que registre procesos reales y se hayan definido
  sus credenciales, recuperación y observabilidad.

## Activación propuesta

Después de crear y validar una release final limpia y recibir autorización:

1. Repetir el preflight y exigir repositorio limpio, `HEAD == origin/main` y
   versión completa, estructura válida y hashes comprobados.
2. Configurar la variable externa del application pool sin mostrar su valor.
3. Crear un enlace temporal a la versión validada.
4. Intercambiar de forma controlada `runtime\current`.
5. Apuntar el sitio a la carpeta combinada de la versión activa.
6. Reciclar el application pool.
7. Comprobar HTTPS, health, carga del frontend y lectura de opciones contra
   `EBIR_MES_TEST`, sin contactar sistemas externos ni cambiar datos.
8. Ejecutar un cierre manual solo con autorización funcional específica.

## Rollback propuesto

Conservar siempre la versión anterior. Ante un fallo:

1. Restaurar `runtime\current` a la versión anterior.
2. Restaurar la ruta física anterior si hubiese cambiado.
3. Reciclar el application pool.
4. Verificar HTTPS y health.
5. Registrar la versión fallida y no eliminar sus artefactos hasta completar el
   diagnóstico.

Los cambios de IIS, la activación, el rollback y cualquier contacto con NAV o
periféricos requieren autorización independiente.
