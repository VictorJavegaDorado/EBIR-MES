/*
Paquete 049A - Asignacion de jefes de linea.
Base exclusiva: EBIR_MES_TEST.

Crea cfg.lineas_jefes: relacion vigente entre una linea y el supervisor
(jefe de linea) responsable. El panel de fabricacion filtra las lineas por
jefe con esta tabla y la etiqueta en la vista de planta. mes_runtime solo la
lee (SELECT sobre el esquema cfg concedido por 009). El paquete no inserta
datos: el reparto real se entrega en un paquete de datos posterior.
*/
SET NOCOUNT ON;
SET XACT_ABORT ON;

IF DB_NAME() <> N'EBIR_MES_TEST'
    THROW 51000, 'Script permitido unicamente en EBIR_MES_TEST.', 1;
GO

IF OBJECT_ID(N'cfg.lineas', N'U') IS NULL
 OR OBJECT_ID(N'seg.empleados', N'U') IS NULL
 OR OBJECT_ID(N'seg.empleados_roles', N'U') IS NULL
    THROW 51160, 'El paquete 049A requiere los maestros de lineas y empleados.', 1;
GO

IF OBJECT_ID(N'cfg.lineas_jefes', N'U') IS NOT NULL
    THROW 51161, 'cfg.lineas_jefes ya existe; el paquete 049A no se reinstala.', 1;
GO

BEGIN TRY
    BEGIN TRANSACTION;

    CREATE TABLE cfg.lineas_jefes
    (
        linea_jefe_id bigint IDENTITY(1,1) NOT NULL
            CONSTRAINT PK_cfg_lineas_jefes PRIMARY KEY,
        linea_id bigint NOT NULL,
        empleado_id bigint NOT NULL,
        asignado_desde_utc datetime2(3) NOT NULL
            CONSTRAINT DF_cfg_lineas_jefes_desde DEFAULT (SYSUTCDATETIME()),
        asignado_hasta_utc datetime2(3) NULL,
        asignado_por_empleado_id bigint NULL,
        asignado_por_cuenta nvarchar(256) NULL,
        motivo nvarchar(250) NULL,
        version rowversion NOT NULL,
        CONSTRAINT FK_cfg_lineas_jefes_linea FOREIGN KEY (linea_id)
            REFERENCES cfg.lineas (linea_id),
        CONSTRAINT FK_cfg_lineas_jefes_empleado FOREIGN KEY (empleado_id)
            REFERENCES seg.empleados (empleado_id),
        CONSTRAINT FK_cfg_lineas_jefes_asignador FOREIGN KEY (asignado_por_empleado_id)
            REFERENCES seg.empleados (empleado_id),
        CONSTRAINT CK_cfg_lineas_jefes_vigencia
            CHECK (asignado_hasta_utc IS NULL OR asignado_hasta_utc >= asignado_desde_utc),
        CONSTRAINT CK_cfg_lineas_jefes_autor
            CHECK (asignado_por_empleado_id IS NOT NULL OR asignado_por_cuenta IS NOT NULL)
    );

    /* Una linea tiene como maximo un jefe vigente; un jefe puede tener varias lineas. */
    CREATE UNIQUE INDEX UX_cfg_lineas_jefes_linea_vigente
        ON cfg.lineas_jefes (linea_id)
        WHERE asignado_hasta_utc IS NULL;

    CREATE INDEX IX_cfg_lineas_jefes_empleado_vigente
        ON cfg.lineas_jefes (empleado_id)
        INCLUDE (linea_id)
        WHERE asignado_hasta_utc IS NULL;

    IF OBJECT_ID(N'cfg.lineas_jefes', N'U') IS NULL
     OR NOT EXISTS
        (
            SELECT 1 FROM sys.indexes
            WHERE object_id = OBJECT_ID(N'cfg.lineas_jefes')
              AND name = N'UX_cfg_lineas_jefes_linea_vigente'
        )
        THROW 51162, 'El contrato 049A no quedo publicado completamente.', 1;

    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;
GO
