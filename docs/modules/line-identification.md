# Identificación de línea

Nombre funcional: `LineIdentification` en backend y pruebas;
`line-identification` en frontend.

Es la primera vertical de aplicación. Permite introducir o seleccionar una
línea y consultar su estado antes de abrir una sesión.

![Vista inicial de identificación de línea](../assets/line-identification-initial.png)

[Vista compacta a 580 px](../assets/line-identification-mobile.png).

## Flujo

1. La persona introduce el código visible en el puesto.
2. La interfaz normaliza visualmente el valor y llama a
   `GET /api/lines/{code}`.
3. La aplicación valida el código y consulta su configuración y estado.
4. La interfaz presenta la línea, su centro de trabajo y su estado operativo.

Este flujo es de solo lectura. El botón de apertura de sesión permanece
deshabilitado hasta implementar la vertical `LineOperations`.

## Reglas

- La línea debe existir y estar activa.
- La respuesta debe incluir únicamente el estado necesario para decidir el
  siguiente paso.
- El código se normaliza en el servidor.
- Consultar una línea no abre una sesión ni cambia estado productivo.
- La interfaz no simula éxito si la API no está disponible.
- El código admite como máximo 20 caracteres, se recorta y se convierte a
  mayúsculas.
- El código es único dentro de un centro de trabajo, pero el esquema no
  garantiza que sea único globalmente. Si hay más de una coincidencia, la API
  devuelve `LINE_CODE_AMBIGUOUS`; nunca elige una línea arbitrariamente.
- Si no existe todavía un registro en `prod.estados_linea`, el estado de
  lectura es `LIBRE`.

## Contrato HTTP

`GET /api/lines/{code}` devuelve, en éxito:

- `id`, `code` y `name`;
- `workCenterCode` y `workCenterName`;
- `operationalStatus`.

Errores funcionales:

| HTTP | Código | Motivo |
|---:|---|---|
| 400 | `LINE_CODE_REQUIRED` / `LINE_CODE_TOO_LONG` | Código no válido |
| 404 | `LINE_NOT_FOUND` | No hay coincidencias |
| 409 | `LINE_INACTIVE` | La línea está desactivada |
| 409 | `LINE_CODE_AMBIGUOUS` | El código identifica varias líneas |
| 503 | `LINE_IDENTIFICATION_UNAVAILABLE` | Fallo de acceso a configuración |

Los errores no incluyen detalles SQL, cadenas de conexión ni excepciones
internas.

## Persistencia y configuración

El lector `SqlLineIdentificationReader` ejecuta una consulta parametrizada
sobre:

- `cfg.lineas`;
- `cfg.centros_trabajo`;
- `prod.estados_linea`.

La conexión se obtiene de `ConnectionStrings:MesDatabase`. El repositorio solo
contiene una entrada vacía; el secreto deberá suministrarse mediante
configuración protegida del entorno. El tiempo máximo del comando es cinco
segundos.

No se ha ejecutado SQL para implementar ni validar esta vertical y no se ha
contactado con NAV, RFID ni impresoras.

## Pruebas

- Aplicación:
  `tests/backend/Ebir.Mes.Application.Tests/LineIdentification`.
- Contrato HTTP sin base de datos:
  `tests/backend/Ebir.Mes.IntegrationTests/LineIdentification`.
- Componente:
  `tests/frontend/component/features/line-identification`.

Las reglas posteriores de apertura y turnos se encuentran en
`line-operations.md`.
