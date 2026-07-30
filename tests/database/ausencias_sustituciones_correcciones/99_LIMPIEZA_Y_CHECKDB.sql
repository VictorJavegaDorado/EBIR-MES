/*
Pruebas 012 - limpieza total y comprobacion de integridad.
Estado: preparado para revision; no ejecutado.
Requiere autorizacion separada para limpieza y DBCC CHECKDB.
No llama a NAV, RFID, dispositivos ni impresoras.
*/
SET NOCOUNT ON;
SET XACT_ABORT ON;

IF DB_NAME() <> N'EBIR_MES_TEST'
    THROW 54900, 'Pruebas permitidas unicamente en EBIR_MES_TEST.', 1;

DECLARE @ordenes TABLE
(
    orden_id bigint NOT NULL PRIMARY KEY
);
INSERT @ordenes
SELECT orden_id
FROM prod.ordenes
WHERE numero_orden LIKE N'ZZ12-%';

DECLARE @lineas TABLE
(
    linea_id bigint NOT NULL PRIMARY KEY
);
INSERT @lineas
SELECT linea_id
FROM cfg.lineas
WHERE codigo LIKE N'ZZ12-%';

DECLARE @empleados TABLE
(
    empleado_id bigint NOT NULL PRIMARY KEY
);
INSERT @empleados
SELECT empleado_id
FROM seg.empleados
WHERE codigo_nav LIKE N'ZZ12-%';

DECLARE @impresoras TABLE
(
    impresora_id bigint NOT NULL PRIMARY KEY
);
INSERT @impresoras
SELECT impresora_id
FROM cfg.impresoras
WHERE codigo = N'ZZ12-PRN';

DECLARE @empresas TABLE
(
    empresa_nav_id bigint NOT NULL PRIMARY KEY
);
INSERT @empresas
SELECT empresa_nav_id
FROM nav.empresas
WHERE codigo = N'ZZTEST_012';

IF (SELECT COUNT(*) FROM @ordenes) <> 4
 OR (SELECT COUNT(*) FROM @lineas) <> 6
 OR (SELECT COUNT(*) FROM @empleados) <> 6
 OR (SELECT COUNT(*) FROM @impresoras) <> 1
 OR (SELECT COUNT(*) FROM @empresas) <> 1
    THROW 54901, 'Los fixtures 012 no existen o estan incompletos; no se limpia.', 1;

BEGIN TRY
    BEGIN TRANSACTION;

    /* Auditoria: no debe impedir borrar autores, lineas, ordenes o sesiones. */
    DELETE a
    FROM aud.eventos a
    WHERE a.orden_id IN (SELECT orden_id FROM @ordenes)
       OR a.linea_id IN (SELECT linea_id FROM @lineas)
       OR a.empleado_id IN (SELECT empleado_id FROM @empleados);

    /* Impresion, en orden inverso de sus claves foraneas. */
    DELETE ii
    FROM imp.intentos_impresion ii
    JOIN imp.trabajos_impresion ti
      ON ti.trabajo_impresion_id = ii.trabajo_impresion_id
    JOIN imp.etiquetas e
      ON e.etiqueta_id = ti.etiqueta_id
    WHERE e.orden_id IN (SELECT orden_id FROM @ordenes);

    DELETE ti
    FROM imp.trabajos_impresion ti
    JOIN imp.etiquetas e
      ON e.etiqueta_id = ti.etiqueta_id
    WHERE e.orden_id IN (SELECT orden_id FROM @ordenes);

    DELETE FROM imp.etiquetas
    WHERE orden_id IN (SELECT orden_id FROM @ordenes);

    /* Integracion NAV local y sus intentos. */
    DELETE ni
    FROM nav.intentos_operacion ni
    JOIN nav.operaciones no
      ON no.operacion_nav_id = ni.operacion_nav_id
    WHERE no.orden_id IN (SELECT orden_id FROM @ordenes);

    DELETE FROM nav.operaciones
    WHERE orden_id IN (SELECT orden_id FROM @ordenes);

    /* Logistica, aunque 012 no crea registros en estas tablas. */
    DELETE hs
    FROM [log].historial_solicitudes hs
    JOIN [log].solicitudes_reaprovisionamiento sr
      ON sr.solicitud_id = hs.solicitud_id
    WHERE sr.orden_id IN (SELECT orden_id FROM @ordenes);

    DELETE FROM [log].solicitudes_reaprovisionamiento
    WHERE orden_id IN (SELECT orden_id FROM @ordenes);

    DELETE FROM [log].revisiones_scrap
    WHERE orden_id IN (SELECT orden_id FROM @ordenes);

    DELETE FROM [log].scrap
    WHERE orden_id IN (SELECT orden_id FROM @ordenes);

    /* Produccion: hijos de sesiones, palets y reservas. */
    DELETE FROM prod.sustituciones_capacidad
    WHERE sesion_linea_id IN
    (
        SELECT sesion_linea_id
        FROM prod.sesiones_linea
        WHERE orden_id IN (SELECT orden_id FROM @ordenes)
    );

    DELETE po
    FROM prod.paros_operario po
    JOIN prod.fichajes f ON f.fichaje_id = po.fichaje_id
    WHERE f.sesion_linea_id IN
    (
        SELECT sesion_linea_id
        FROM prod.sesiones_linea
        WHERE orden_id IN (SELECT orden_id FROM @ordenes)
    );

    DELETE FROM prod.paradas_linea
    WHERE sesion_linea_id IN
    (
        SELECT sesion_linea_id
        FROM prod.sesiones_linea
        WHERE orden_id IN (SELECT orden_id FROM @ordenes)
    );

    DELETE FROM prod.tramos_capacidad
    WHERE sesion_linea_id IN
    (
        SELECT sesion_linea_id
        FROM prod.sesiones_linea
        WHERE orden_id IN (SELECT orden_id FROM @ordenes)
    );

    DELETE FROM prod.fichajes
    WHERE sesion_linea_id IN
    (
        SELECT sesion_linea_id
        FROM prod.sesiones_linea
        WHERE orden_id IN (SELECT orden_id FROM @ordenes)
    );

    DELETE FROM prod.palets
    WHERE orden_id IN (SELECT orden_id FROM @ordenes);

    DELETE FROM prod.reservas_palet
    WHERE orden_id IN (SELECT orden_id FROM @ordenes);

    DELETE FROM prod.estados_linea
    WHERE linea_id IN (SELECT linea_id FROM @lineas);

    DELETE FROM prod.sesiones_linea
    WHERE orden_id IN (SELECT orden_id FROM @ordenes);

    DELETE FROM prod.formatos_palet_orden
    WHERE orden_id IN (SELECT orden_id FROM @ordenes);

    DELETE FROM nav.componentes_orden
    WHERE orden_id IN (SELECT orden_id FROM @ordenes);

    DELETE FROM prod.ordenes
    WHERE orden_id IN (SELECT orden_id FROM @ordenes);

    /* Configuracion sintetica de lineas e impresora. */
    DELETE FROM cfg.lineas_impresoras
    WHERE linea_id IN (SELECT linea_id FROM @lineas)
       OR impresora_id IN (SELECT impresora_id FROM @impresoras);

    DELETE FROM cfg.lineas_dispositivos
    WHERE linea_id IN (SELECT linea_id FROM @lineas);

    DELETE FROM cfg.lineas
    WHERE linea_id IN (SELECT linea_id FROM @lineas);

    DELETE FROM cfg.impresoras
    WHERE impresora_id IN (SELECT impresora_id FROM @impresoras);

    /* Identidades sinteticas y empresa NAV, ya sin referencias. */
    DELETE FROM seg.empleados_roles
    WHERE empleado_id IN (SELECT empleado_id FROM @empleados);

    DELETE FROM seg.credenciales_rfid
    WHERE empleado_id IN (SELECT empleado_id FROM @empleados);

    DELETE FROM seg.empleados
    WHERE empleado_id IN (SELECT empleado_id FROM @empleados);

    DELETE FROM nav.empresas
    WHERE empresa_nav_id IN (SELECT empresa_nav_id FROM @empresas);

    /* Ningun identificador de fixture puede sobrevivir. */
    IF EXISTS (SELECT 1 FROM prod.ordenes WHERE numero_orden LIKE N'ZZ12-%')
     OR EXISTS (SELECT 1 FROM cfg.lineas WHERE codigo LIKE N'ZZ12-%')
     OR EXISTS (SELECT 1 FROM seg.empleados WHERE codigo_nav LIKE N'ZZ12-%')
     OR EXISTS (SELECT 1 FROM cfg.impresoras WHERE codigo = N'ZZ12-PRN')
     OR EXISTS (SELECT 1 FROM nav.empresas WHERE codigo = N'ZZTEST_012')
     OR EXISTS
     (
         SELECT 1 FROM aud.eventos
         WHERE orden_id IN (SELECT orden_id FROM @ordenes)
            OR linea_id IN (SELECT linea_id FROM @lineas)
            OR empleado_id IN (SELECT empleado_id FROM @empleados)
     )
        THROW 54902, 'La limpieza de identificadores 012 fue incompleta.', 1;

    /* Los cinco catalogos iniciales deben sumar exactamente 37 filas. */
    IF (SELECT COUNT(*) FROM cfg.centros_trabajo) <> 1
     OR (SELECT COUNT(*) FROM cfg.turnos) <> 2
     OR (SELECT COUNT(*) FROM seg.roles) <> 3
     OR (SELECT COUNT(*) FROM nav.entornos) <> 1
     OR (SELECT COUNT(*) FROM [log].motivos_scrap) <> 30
        THROW 54903, 'Los catalogos iniciales no conservan sus 37 registros.', 1;

    /*
    Excluye los cinco catalogos anteriores y exige cero filas en las otras
    32 tablas. La consulta se construye solo desde metadatos de esta base.
    */
    DECLARE
        @filas_operativas bigint = 0,
        @sql nvarchar(max) = N'SET @total = 0;';

    SELECT @sql = @sql
        + N'SELECT @total = @total + COUNT_BIG(*) FROM '
        + QUOTENAME(SCHEMA_NAME(t.schema_id)) + N'.' + QUOTENAME(t.name) + N';'
    FROM sys.tables t
    WHERE t.is_ms_shipped = 0
      AND NOT
      (
          (SCHEMA_NAME(t.schema_id) = N'cfg' AND t.name IN (N'centros_trabajo', N'turnos'))
          OR (SCHEMA_NAME(t.schema_id) = N'seg' AND t.name = N'roles')
          OR (SCHEMA_NAME(t.schema_id) = N'nav' AND t.name = N'entornos')
          OR (SCHEMA_NAME(t.schema_id) = N'log' AND t.name = N'motivos_scrap')
      )
    ORDER BY SCHEMA_NAME(t.schema_id), t.name;

    EXEC sys.sp_executesql
        @sql,
        N'@total bigint OUTPUT',
        @total = @filas_operativas OUTPUT;

    IF @filas_operativas <> 0
        THROW 54904, 'Quedan filas fuera de los cinco catalogos iniciales.', 1;

    IF (SELECT COUNT(*) FROM sys.tables WHERE is_ms_shipped = 0) <> 37
        THROW 54905, 'El numero de tablas de usuario no es 37.', 1;

    IF (SELECT COUNT(*) FROM sys.procedures WHERE is_ms_shipped = 0) <> 16
        THROW 54906, 'El numero de procedimientos de usuario no es 16.', 1;

    IF OBJECT_ID(N'prod.recursos_efectivos_sesion', N'IF') IS NULL
        THROW 54908, 'La funcion interna del paquete 012 no permanece instalada.', 1;

    IF NOT EXISTS
    (
        SELECT 1
        FROM sys.database_role_members drm
        WHERE drm.role_principal_id = DATABASE_PRINCIPAL_ID(N'mes_runtime')
          AND drm.member_principal_id = USER_ID(N'EBIR\MES$')
    )
        THROW 54907, 'La limpieza altero la pertenencia de EBIR\MES$ a mes_runtime.', 1;

    COMMIT;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0
        ROLLBACK TRANSACTION;
    THROW;
END CATCH;

SELECT
    (SELECT COUNT(*) FROM sys.tables WHERE is_ms_shipped = 0) AS tablas,
    (SELECT COUNT(*) FROM sys.procedures WHERE is_ms_shipped = 0) AS procedimientos,
    CASE WHEN OBJECT_ID(N'prod.recursos_efectivos_sesion', N'IF') IS NOT NULL
         THEN 1 ELSE 0 END AS funciones_012,
    (SELECT COUNT(*) FROM cfg.centros_trabajo)
      + (SELECT COUNT(*) FROM cfg.turnos)
      + (SELECT COUNT(*) FROM seg.roles)
      + (SELECT COUNT(*) FROM nav.entornos)
      + (SELECT COUNT(*) FROM [log].motivos_scrap) AS registros_iniciales;

PRINT N'PRUEBAS 012 LIMPIEZA: OK';

DBCC CHECKDB (N'EBIR_MES_TEST')
WITH NO_INFOMSGS, ALL_ERRORMSGS;

PRINT N'PRUEBAS 012 DBCC CHECKDB: OK';

