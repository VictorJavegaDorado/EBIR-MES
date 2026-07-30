/*
Pruebas 011 - auditoria y permisos efectivos.
Estado: preparado para revision; no ejecutado.
Requiere haber completado los bloques funcionales 01-04 y la concurrencia 05-06.
No modifica datos ni llama a sistemas externos.
*/
SET NOCOUNT ON;
SET XACT_ABORT ON;

IF DB_NAME() <> N'EBIR_MES_TEST'
    THROW 53700, 'Pruebas permitidas unicamente en EBIR_MES_TEST.', 1;

IF USER_ID(N'EBIR\MES$') IS NULL
    THROW 53701, 'No existe el usuario runtime EBIR\MES$ en EBIR_MES_TEST.', 1;

IF DATABASE_PRINCIPAL_ID(N'mes_runtime') IS NULL
    THROW 53702, 'No existe el rol mes_runtime.', 1;

IF NOT EXISTS
(
    SELECT 1
    FROM sys.database_role_members drm
    WHERE drm.role_principal_id = DATABASE_PRINCIPAL_ID(N'mes_runtime')
      AND drm.member_principal_id = USER_ID(N'EBIR\MES$')
)
    THROW 53703, 'EBIR\MES$ no pertenece a mes_runtime.', 1;

IF (SELECT COUNT(*) FROM prod.ordenes WHERE numero_orden LIKE N'ZZ11-%') <> 4
 OR NOT EXISTS
 (
     SELECT 1
     FROM prod.sesiones_linea s
     JOIN prod.ordenes o ON o.orden_id = s.orden_id
     WHERE o.numero_orden = N'ZZ11-FL-TURNO'
       AND s.estado = N'FINALIZADA_TURNO'
 )
 OR NOT EXISTS
 (
     SELECT 1
     FROM imp.etiquetas e
     JOIN prod.ordenes o ON o.orden_id = e.orden_id
     WHERE o.numero_orden = N'ZZ11-FL-PRINT'
       AND e.tipo = N'PALET'
       AND e.estado = N'IMPRESA'
 )
    THROW 53704, 'No se completaron los bloques funcionales previos.', 1;

DECLARE @tipos_esperados TABLE
(
    tipo_evento nvarchar(80) NOT NULL PRIMARY KEY
);

INSERT @tipos_esperados
VALUES
(N'SESION_LINEA_ABIERTA'),
(N'FICHAJE_ENTRADA_PRODUCTIVA'),
(N'RESERVA_PALET_CREADA'),
(N'FICHAJE_SALIDA_PRODUCTIVA'),
(N'CAMBIO_TURNO_PENDIENTE'),
(N'RESERVA_PALET_CANCELADA'),
(N'SESION_FINALIZADA_TURNO'),
(N'PALET_CERRADO'),
(N'SALIDA_PALET_NAV_CONFIRMADA'),
(N'ETIQUETA_IMPRESA');

IF EXISTS
(
    SELECT 1
    FROM @tipos_esperados t
    WHERE NOT EXISTS
    (
        SELECT 1
        FROM aud.eventos a
        JOIN prod.ordenes o ON o.orden_id = a.orden_id
        WHERE o.numero_orden LIKE N'ZZ11-%'
          AND a.tipo_evento = t.tipo_evento
    )
)
    THROW 53705, 'Falta al menos un tipo de auditoria 011 esperado.', 1;

IF EXISTS
(
    SELECT 1
    FROM aud.eventos a
    JOIN prod.ordenes o ON o.orden_id = a.orden_id
    WHERE o.numero_orden LIKE N'ZZ11-%'
      AND
      (
          a.correlacion_id IS NULL
          OR a.fecha_utc IS NULL
          OR NULLIF(LTRIM(RTRIM(a.entidad)), N'') IS NULL
          OR (a.empleado_id IS NULL AND NULLIF(LTRIM(RTRIM(a.cuenta_dominio)), N'') IS NULL)
          OR a.linea_id IS NULL
          OR a.sesion_linea_id IS NULL
      )
)
    THROW 53706, 'Existe auditoria 011 sin correlacion, autor o contexto obligatorio.', 1;

IF EXISTS
(
    SELECT 1
    FROM aud.eventos a
    JOIN prod.ordenes o ON o.orden_id = a.orden_id
    WHERE o.numero_orden LIKE N'ZZ11-%'
      AND
      (
          LOWER(COALESCE(a.valor_anterior, N'')) LIKE N'%rfid%'
          OR LOWER(COALESCE(a.valor_nuevo, N'')) LIKE N'%rfid%'
          OR LOWER(COALESCE(a.motivo, N'')) LIKE N'%rfid%'
          OR LOWER(COALESCE(a.entidad, N'')) LIKE N'%credenciales_rfid%'
      )
)
    THROW 53707, 'La auditoria 011 contiene una posible referencia RFID.', 1;

IF EXISTS
(
    SELECT 1
    FROM aud.eventos a
    JOIN prod.ordenes o ON o.orden_id = a.orden_id
    WHERE o.numero_orden LIKE N'ZZ11-%'
      AND a.tipo_evento IN
          (N'RESERVA_PALET_CANCELADA', N'SESION_FINALIZADA_TURNO')
      AND
      (
          a.empleado_id IS NULL
          OR COALESCE(a.rol_usado, N'') <> N'SUPERVISOR'
          OR NULLIF(LTRIM(RTRIM(a.motivo)), N'') IS NULL
      )
)
    THROW 53708, 'Una accion supervisada carece de autor, rol o motivo.', 1;

IF EXISTS
(
    SELECT 1
    FROM aud.eventos a
    JOIN prod.ordenes o ON o.orden_id = a.orden_id
    WHERE o.numero_orden LIKE N'ZZ11-%'
      AND a.tipo_evento IN
          (N'CAMBIO_TURNO_PENDIENTE',
           N'SALIDA_PALET_NAV_CONFIRMADA',
           N'ETIQUETA_IMPRESA')
      AND COALESCE(a.cuenta_dominio, N'') <> N'EBIR\MES$'
)
    THROW 53709, 'Un evento tecnico no esta atribuido a EBIR\MES$.', 1;

IF
(
    SELECT COUNT(*)
    FROM aud.eventos a
    JOIN prod.ordenes o ON o.orden_id = a.orden_id
    WHERE o.numero_orden = N'ZZ11-FL-TURNO'
      AND a.tipo_evento = N'CAMBIO_TURNO_PENDIENTE'
) <> 1
    THROW 53710, 'El marcado idempotente duplico su auditoria.', 1;

/*
Comprueba permisos efectivos bajo la identidad de base del runtime.
El TRY/CATCH garantiza REVERT incluso si falla una asercion.
*/
EXECUTE AS USER = N'EBIR\MES$';
BEGIN TRY
    IF EXISTS
    (
        SELECT 1
        FROM
        (
            VALUES
            (N'prod.reservar_palet'),
            (N'prod.cancelar_reserva_palet'),
            (N'prod.cerrar_palet'),
            (N'nav.confirmar_salida_palet'),
            (N'imp.confirmar_trabajo_impresion'),
            (N'prod.abrir_sesion_linea'),
            (N'prod.registrar_entrada_productiva'),
            (N'prod.registrar_salida_productiva'),
            (N'prod.marcar_cambio_turno_pendiente'),
            (N'prod.finalizar_sesion_turno')
        ) p(objeto)
        WHERE COALESCE(HAS_PERMS_BY_NAME(p.objeto, N'OBJECT', N'EXECUTE'), 0) <> 1
    )
        THROW 53711, 'Runtime sin EXECUTE en algun procedimiento operativo.', 1;

    IF EXISTS
    (
        SELECT 1
        FROM
        (
            VALUES
            (N'cfg.lineas'),
            (N'seg.empleados'),
            (N'prod.ordenes'),
            (N'prod.sesiones_linea'),
            (N'nav.operaciones'),
            (N'imp.trabajos_impresion')
        ) p(objeto)
        WHERE COALESCE(HAS_PERMS_BY_NAME(p.objeto, N'OBJECT', N'SELECT'), 0) <> 1
    )
        THROW 53712, 'Runtime sin lectura en algun objeto funcional.', 1;

    IF HAS_PERMS_BY_NAME(N'aud.registrar_evento', N'OBJECT', N'EXECUTE') <> 0
        THROW 53713, 'Runtime puede ejecutar directamente el registrador de auditoria.', 1;

    IF HAS_PERMS_BY_NAME(N'aud.eventos', N'OBJECT', N'SELECT') <> 0
        THROW 53714, 'Runtime puede leer auditoria.', 1;

    IF HAS_PERMS_BY_NAME(DB_NAME(), N'DATABASE', N'CONTROL') <> 0
        THROW 53715, 'Runtime controla la base.', 1;

    IF HAS_PERMS_BY_NAME(DB_NAME(), N'DATABASE', N'ALTER') <> 0
        THROW 53716, 'Runtime puede alterar la base.', 1;

    IF HAS_PERMS_BY_NAME(DB_NAME(), N'DATABASE', N'CREATE TABLE') <> 0
        THROW 53717, 'Runtime puede crear tablas.', 1;

    IF HAS_PERMS_BY_NAME(DB_NAME(), N'DATABASE', N'CREATE PROCEDURE') <> 0
        THROW 53718, 'Runtime puede crear procedimientos.', 1;

    IF HAS_PERMS_BY_NAME(N'prod.ordenes', N'OBJECT', N'UPDATE') <> 0
        THROW 53719, 'Runtime puede actualizar directamente produccion.', 1;

    IF HAS_PERMS_BY_NAME(N'prod.fichajes', N'OBJECT', N'INSERT') <> 0
        THROW 53720, 'Runtime puede insertar directamente fichajes.', 1;

    IF HAS_PERMS_BY_NAME(N'prod.reservas_palet', N'OBJECT', N'DELETE') <> 0
        THROW 53721, 'Runtime puede borrar directamente reservas.', 1;

    IF HAS_PERMS_BY_NAME(N'nav.operaciones', N'OBJECT', N'INSERT') <> 0
        THROW 53722, 'Runtime puede insertar directamente operaciones NAV.', 1;

    IF HAS_PERMS_BY_NAME(N'imp.trabajos_impresion', N'OBJECT', N'INSERT') <> 0
        THROW 53723, 'Runtime puede insertar directamente trabajos de impresion.', 1;
END TRY
BEGIN CATCH
    REVERT;
    THROW;
END CATCH;
REVERT;

SELECT
    a.tipo_evento,
    COUNT(*) AS eventos,
    COUNT(DISTINCT a.correlacion_id) AS correlaciones
FROM aud.eventos a
JOIN prod.ordenes o ON o.orden_id = a.orden_id
WHERE o.numero_orden LIKE N'ZZ11-%'
GROUP BY a.tipo_evento
ORDER BY a.tipo_evento;

PRINT N'PRUEBAS 011 AUDITORIA Y PERMISOS: OK';
