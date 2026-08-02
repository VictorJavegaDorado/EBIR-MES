# Preparación de hardware y empleados — 01/08/2026

Inspección realizada sobre `MES.EBIR.LOCAL`, `EBIR_MES_TEST` y el catálogo
SOAP de `EBIRTEST`, sin escribir en NAV ni enviar trabajos a hardware.

## Inventario observado

- `EBIR_MES_TEST`: 0 líneas, 0 impresoras, 0 asignaciones de impresora,
  0 dispositivos, 0 empleados y 0 credenciales RFID.
- Windows: cola de impresión activa, pero únicamente `Microsoft Print to PDF`;
  no hay puerto TCP ni controlador Toshiba instalado.
- Dispositivos: puertos COM1 y COM2 y el enumerador genérico de tarjeta
  inteligente; ningún lector RFID identificado.
- NAV TEST: el catálogo no publica una página de empleados. Publica el codeunit
  `WS_DataClock`, que no se invocó porque no se ha confirmado que sea de solo
  lectura.

## Datos necesarios para Toshiba

1. Modelo exacto, resolución (DPI) y lenguaje admitido por el equipo.
2. Dirección IP o nombre DNS, puerto y protocolo habilitado.
3. Línea MES a la que pertenece y si es impresora principal o alternativa.
4. Tamaño físico de etiqueta, orientación, velocidad y oscuridad aprobadas.
5. Plantilla validada con fabricación y una etiqueta patrón legible.

Hasta disponer de estos valores, el adaptador real permanece ausente y el
worker solo admite explícitamente el modo `Simulated`.

## Datos necesarios para empleados

Se necesita publicar en `EBIRTEST` una página SOAP de solo lectura con, como
mínimo: código estable de empleado, nombre, cargo/rol, proceso o centro,
grupo de turno y estado activo. Debe confirmarse si `WS_DataClock` ofrece una
lectura equivalente; no debe probarse ninguna operación del codeunit sin
clasificar primero cada método como lectura o escritura.

## Datos necesarios para RFID

1. Modelo e interfaz del lector (USB HID, serie o red).
2. Formato exacto emitido: hexadecimal, longitud, prefijo/sufijo y terminador.
3. Tres tarjetas exclusivamente de TEST y su empleado TEST asociado.
4. Equipo/línea donde se conectará y método de reconexión esperado.

El backend ya normaliza UIDs hexadecimales y calcula una huella HMAC-SHA256.
El UID original no se persiste ni se devuelve. La clave HMAC debe suministrarse
como secreto externo `Rfid__LookupKey`; nunca se versiona.

## Paquete 019 preparado — 02/08/2026

El contrato de carga ya está versionado sin valores reales. El archivo de
configuración deberá permanecer fuera de `C:\MES` y aportar los datos de esta
lista después de su revisión. La validación inicial se ejecutará con rollback;
preparar el paquete no autoriza instalarlo ni conectar hardware.

La lista exacta que debe recogerse en fábrica y el orden de continuación están
consolidados en `pilot-readiness-2026-08-02.md`.
