# Preparación del piloto en IIS

Este documento describe el estado preparado y los pasos que requieren una
autorización explícita antes de activar el piloto.

## Estado verificado

- El sitio `MES` está iniciado y enlazado a `https://MES.EBIR.LOCAL`.
- El sitio apunta a `C:\MES\runtime\bootstrap`.
- El application pool `MES` usa `NetworkService`.
- `AspNetCoreModuleV2` está instalado.
- `C:\MES\runtime\current` todavía no es un enlace a una versión.
- La release combinada de validación es
  `20260731.2-86662f7-combined-candidate`.
- El servicio `MES Worker` no está instalado.

Ejecutar la comprobación de solo lectura:

```powershell
powershell -ExecutionPolicy Bypass -File C:\MES\deploy\iis\Get-PilotPreflight.ps1 `
  -ExpectedCommit 86662f7fd8a01de50a74a9f6f4a6c08105b7c9cc
```

## Estado del routing y bloqueo de activación

El bloqueo técnico de hosting conjunto está resuelto en el árbol local:

- la publicación de la API incorpora el frontend en `api\wwwroot`;
- la API sirve archivos estáticos;
- las rutas `/api/*` conservan prioridad y nunca reciben el fallback SPA;
- las rutas de navegación sin extensión reciben `index.html`;
- los assets inexistentes y las API desconocidas devuelven `404`;
- cinco pruebas de integración cubren estos casos;
- la candidata `.2` fue verificada en loopback sin modificar IIS.

La candidata todavía no debe activarse: procede de un árbol sin commit mediante
`-AllowDirty`, falta crear una release final desde un commit limpio y siguen
pendientes la configuración externa, la autorización de IIS y el rollback
controlado.

Las candidatas
`20260731.0-86662f7-combined-candidate` y
`20260731.1-86662f7-combined-candidate` son inválidas y nunca deben activarse.
La `.0` tiene un CSV de hashes con esquema incorrecto. La `.1` se generó con dos
invocaciones simultáneas del mismo ID y contiene un directorio de trabajo
anidado. El generador mantiene ahora un bloqueo exclusivo por `ReleaseId`.

## Configuración pendiente

- Proporcionar `ConnectionStrings__MesDatabase` mediante un almacén externo al
  repositorio y verificar acceso únicamente a `EBIR_MES_TEST`.
- Confirmar la identidad definitiva del application pool y sus permisos
  mínimos sobre la versión activa y la configuración compartida.
- Mantener deshabilitadas las integraciones NAV/OData, RFID e impresoras
  durante las pruebas del piloto preparatorio.
- No instalar el Worker hasta que registre procesos reales y se hayan definido
  sus credenciales, recuperación y observabilidad.

## Activación propuesta

Después de crear y validar una release final limpia y recibir autorización:

1. Repetir el preflight y exigir repositorio limpio, `HEAD == origin/main` y
   versión completa, estructura válida y hashes comprobados.
2. Crear un enlace temporal a la versión validada.
3. Intercambiar de forma controlada `runtime\current`.
4. Apuntar el sitio a la carpeta combinada de la versión activa.
5. Reciclar el application pool.
6. Comprobar HTTPS, health, carga del frontend y cierre manual contra
   `EBIR_MES_TEST`, sin contactar sistemas externos.

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
