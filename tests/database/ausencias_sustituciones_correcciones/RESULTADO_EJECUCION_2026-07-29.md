# Resultado de ejecución del paquete 012 — 29/07/2026

Ámbito exclusivo:

```text
SQL.EBIR.LOCAL\NAVISION2017
EBIR_MES_TEST
```

## Fases completadas

1. instalación atómica de `012A–012I`;
2. prevuelo y fixtures `ZZTEST_012`/`ZZ12-`;
3. pruebas funcionales `01–04`;
4. concurrencia `05–06` en dos conexiones;
5. auditoría y permisos `07`;
6. limpieza y `DBCC CHECKDB` mediante `99`.

No se llamó a NAV, RFID, dispositivos ni impresoras físicas.

## Cobertura

- WC y pausa de calor;
- ausencia total y retorno desde `SIN_OPERARIOS`;
- sustitución supervisada sin aumentar dotación;
- finalización automática y anticipada de sustituciones;
- corrección supervisada de fichaje;
- reconstrucción de tramos sin solapamientos;
- desbloqueo posterior a impresión con fichajes en paro;
- concurrencia de dos supervisores sobre el mismo operario;
- seis tipos de auditoría nuevos;
- mínimo privilegio efectivo de `EBIR\MES$`.

## Correcciones realizadas durante las pruebas

Se corrigieron exclusivamente defectos de los tests:

- expectativas de parámetros `OUTPUT` después de `THROW`;
- dos expresiones `DATEADD` usadas directamente como argumentos de `EXEC`;
- cálculo prematuro de una variable en C03;
- centinela reutilizado por el cliente perdedor de concurrencia.

Los procedimientos devolvieron los errores funcionales y estados
transaccionales esperados.

## Concurrencia

La repetición validada terminó con:

```text
1 sustitución activa
1 fichaje de supervisor sustituto abierto
2 recursos efectivos
ganador: ZZ12-SUP
```

## Estado final

```text
37 tablas
16 procedimientos
1 función interna
37 registros iniciales
0 filas operativas
0 fixtures
EBIR\MES$ miembro de mes_runtime
DBCC CHECKDB sin errores
```

Los fixtures eliminados eran exclusivamente sintéticos y su eliminación no es
recuperable desde el propio paquete de pruebas.
