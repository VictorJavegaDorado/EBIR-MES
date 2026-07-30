SET NOCOUNT ON;
SET XACT_ABORT ON;

IF DB_NAME() <> N'EBIR_MES_TEST'
    THROW 51000, 'Script permitido unicamente en EBIR_MES_TEST.', 1;

BEGIN TRANSACTION;

IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = N'cfg') EXEC(N'CREATE SCHEMA cfg AUTHORIZATION dbo;');
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = N'seg') EXEC(N'CREATE SCHEMA seg AUTHORIZATION dbo;');
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = N'prod') EXEC(N'CREATE SCHEMA prod AUTHORIZATION dbo;');
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = N'log') EXEC(N'CREATE SCHEMA [log] AUTHORIZATION dbo;');
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = N'nav') EXEC(N'CREATE SCHEMA nav AUTHORIZATION dbo;');
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = N'imp') EXEC(N'CREATE SCHEMA imp AUTHORIZATION dbo;');
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = N'aud') EXEC(N'CREATE SCHEMA aud AUTHORIZATION dbo;');

CREATE TABLE cfg.centros_trabajo
(
    centro_trabajo_id bigint IDENTITY(1,1) NOT NULL
        CONSTRAINT PK_cfg_centros_trabajo PRIMARY KEY,
    codigo nvarchar(30) NOT NULL,
    nombre nvarchar(100) NOT NULL,
    activo bit NOT NULL CONSTRAINT DF_cfg_centros_trabajo_activo DEFAULT (1),
    creado_utc datetime2(3) NOT NULL CONSTRAINT DF_cfg_centros_trabajo_creado DEFAULT (SYSUTCDATETIME()),
    desactivado_utc datetime2(3) NULL,
    version rowversion NOT NULL,
    CONSTRAINT UQ_cfg_centros_trabajo_codigo UNIQUE (codigo),
    CONSTRAINT CK_cfg_centros_trabajo_codigo
        CHECK (LEN(LTRIM(RTRIM(codigo))) > 0),
    CONSTRAINT CK_cfg_centros_trabajo_nombre
        CHECK (LEN(LTRIM(RTRIM(nombre))) > 0),
    CONSTRAINT CK_cfg_centros_trabajo_desactivacion
        CHECK ((activo = 1 AND desactivado_utc IS NULL) OR
               (activo = 0 AND desactivado_utc IS NOT NULL))
);

CREATE TABLE cfg.lineas
(
    linea_id bigint IDENTITY(1,1) NOT NULL
        CONSTRAINT PK_cfg_lineas PRIMARY KEY,
    centro_trabajo_id bigint NOT NULL,
    codigo nvarchar(20) NOT NULL,
    nombre nvarchar(100) NOT NULL,
    descripcion nvarchar(250) NULL,
    activa bit NOT NULL CONSTRAINT DF_cfg_lineas_activa DEFAULT (1),
    creado_utc datetime2(3) NOT NULL CONSTRAINT DF_cfg_lineas_creado DEFAULT (SYSUTCDATETIME()),
    desactivado_utc datetime2(3) NULL,
    version rowversion NOT NULL,
    CONSTRAINT FK_cfg_lineas_centro FOREIGN KEY (centro_trabajo_id)
        REFERENCES cfg.centros_trabajo (centro_trabajo_id),
    CONSTRAINT UQ_cfg_lineas_centro_codigo UNIQUE (centro_trabajo_id, codigo),
    CONSTRAINT CK_cfg_lineas_codigo
        CHECK (LEN(LTRIM(RTRIM(codigo))) > 0),
    CONSTRAINT CK_cfg_lineas_nombre
        CHECK (LEN(LTRIM(RTRIM(nombre))) > 0),
    CONSTRAINT CK_cfg_lineas_desactivacion
        CHECK ((activa = 1 AND desactivado_utc IS NULL) OR
               (activa = 0 AND desactivado_utc IS NOT NULL))
);

CREATE TABLE cfg.dispositivos
(
    dispositivo_id bigint IDENTITY(1,1) NOT NULL
        CONSTRAINT PK_cfg_dispositivos PRIMARY KEY,
    codigo nvarchar(30) NOT NULL,
    nombre nvarchar(100) NOT NULL,
    tipo nvarchar(30) NOT NULL,
    nombre_equipo nvarchar(128) NULL,
    direccion_red nvarchar(255) NULL,
    activo bit NOT NULL CONSTRAINT DF_cfg_dispositivos_activo DEFAULT (1),
    ultima_conexion_utc datetime2(3) NULL,
    creado_utc datetime2(3) NOT NULL CONSTRAINT DF_cfg_dispositivos_creado DEFAULT (SYSUTCDATETIME()),
    version rowversion NOT NULL,
    CONSTRAINT UQ_cfg_dispositivos_codigo UNIQUE (codigo),
    CONSTRAINT CK_cfg_dispositivos_codigo
        CHECK (LEN(LTRIM(RTRIM(codigo))) > 0),
    CONSTRAINT CK_cfg_dispositivos_nombre
        CHECK (LEN(LTRIM(RTRIM(nombre))) > 0)
);

CREATE TABLE cfg.impresoras
(
    impresora_id bigint IDENTITY(1,1) NOT NULL
        CONSTRAINT PK_cfg_impresoras PRIMARY KEY,
    codigo nvarchar(30) NOT NULL,
    nombre nvarchar(100) NOT NULL,
    modelo nvarchar(100) NOT NULL,
    nombre_red nvarchar(255) NULL,
    direccion_ip varchar(45) NULL,
    protocolo nvarchar(30) NULL,
    resolucion_dpi smallint NULL,
    activa bit NOT NULL CONSTRAINT DF_cfg_impresoras_activa DEFAULT (1),
    creado_utc datetime2(3) NOT NULL CONSTRAINT DF_cfg_impresoras_creado DEFAULT (SYSUTCDATETIME()),
    version rowversion NOT NULL,
    CONSTRAINT UQ_cfg_impresoras_codigo UNIQUE (codigo),
    CONSTRAINT CK_cfg_impresoras_codigo
        CHECK (LEN(LTRIM(RTRIM(codigo))) > 0),
    CONSTRAINT CK_cfg_impresoras_nombre
        CHECK (LEN(LTRIM(RTRIM(nombre))) > 0),
    CONSTRAINT CK_cfg_impresoras_dpi CHECK (resolucion_dpi IS NULL OR resolucion_dpi > 0)
);

CREATE TABLE cfg.turnos
(
    turno_id smallint IDENTITY(1,1) NOT NULL
        CONSTRAINT PK_cfg_turnos PRIMARY KEY,
    codigo nvarchar(20) NOT NULL,
    nombre nvarchar(50) NOT NULL,
    hora_inicio time(0) NOT NULL,
    hora_fin time(0) NOT NULL,
    admite_extension bit NOT NULL CONSTRAINT DF_cfg_turnos_extension DEFAULT (0),
    activo bit NOT NULL CONSTRAINT DF_cfg_turnos_activo DEFAULT (1),
    CONSTRAINT UQ_cfg_turnos_codigo UNIQUE (codigo),
    CONSTRAINT CK_cfg_turnos_codigo CHECK (LEN(LTRIM(RTRIM(codigo))) > 0),
    CONSTRAINT CK_cfg_turnos_horas CHECK (hora_inicio <> hora_fin)
);

COMMIT;
