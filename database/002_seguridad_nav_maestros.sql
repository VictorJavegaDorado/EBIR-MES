SET NOCOUNT ON;
SET XACT_ABORT ON;

IF DB_NAME() <> N'EBIR_MES_TEST'
    THROW 51000, 'Script permitido unicamente en EBIR_MES_TEST.', 1;

BEGIN TRANSACTION;

CREATE TABLE seg.empleados
(
    empleado_id bigint IDENTITY(1,1) NOT NULL
        CONSTRAINT PK_seg_empleados PRIMARY KEY,
    codigo_nav nvarchar(30) NOT NULL,
    nombre_completo nvarchar(200) NOT NULL,
    cargo nvarchar(100) NULL,
    alias nvarchar(100) NULL,
    rol_interno_nav nvarchar(100) NULL,
    proceso_codigo nvarchar(50) NULL,
    tipo_mano_obra nvarchar(20) NULL,
    grupo_turno nvarchar(30) NULL,
    activo_nav bit NOT NULL CONSTRAINT DF_seg_empleados_activo_nav DEFAULT (1),
    activo_mes bit NOT NULL CONSTRAINT DF_seg_empleados_activo_mes DEFAULT (1),
    creado_utc datetime2(3) NOT NULL CONSTRAINT DF_seg_empleados_creado DEFAULT (SYSUTCDATETIME()),
    sincronizado_nav_utc datetime2(3) NOT NULL,
    anonimizado_utc datetime2(3) NULL,
    version rowversion NOT NULL,
    CONSTRAINT UQ_seg_empleados_codigo_nav UNIQUE (codigo_nav),
    CONSTRAINT CK_seg_empleados_codigo CHECK (LEN(LTRIM(RTRIM(codigo_nav))) > 0),
    CONSTRAINT CK_seg_empleados_nombre CHECK (LEN(LTRIM(RTRIM(nombre_completo))) > 0),
    CONSTRAINT CK_seg_empleados_anonimizado
        CHECK (anonimizado_utc IS NULL OR activo_mes = 0)
);

CREATE TABLE seg.credenciales_rfid
(
    credencial_rfid_id bigint IDENTITY(1,1) NOT NULL
        CONSTRAINT PK_seg_credenciales_rfid PRIMARY KEY,
    empleado_id bigint NOT NULL,
    rfid_busqueda varbinary(32) NOT NULL,
    ultimos_caracteres nvarchar(8) NULL,
    desde_utc datetime2(3) NOT NULL,
    hasta_utc datetime2(3) NULL,
    activa bit NOT NULL,
    motivo_baja nvarchar(250) NULL,
    version rowversion NOT NULL,
    CONSTRAINT FK_seg_credenciales_rfid_empleado FOREIGN KEY (empleado_id)
        REFERENCES seg.empleados (empleado_id),
    CONSTRAINT CK_seg_credenciales_rfid_vigencia
        CHECK (hasta_utc IS NULL OR hasta_utc >= desde_utc),
    CONSTRAINT CK_seg_credenciales_rfid_huella
        CHECK (DATALENGTH(rfid_busqueda) = 32),
    CONSTRAINT CK_seg_credenciales_rfid_activa
        CHECK ((activa = 1 AND hasta_utc IS NULL) OR
               (activa = 0 AND hasta_utc IS NOT NULL))
);

CREATE TABLE seg.roles
(
    rol_id smallint IDENTITY(1,1) NOT NULL
        CONSTRAINT PK_seg_roles PRIMARY KEY,
    codigo nvarchar(30) NOT NULL,
    nombre nvarchar(100) NOT NULL,
    es_productivo bit NOT NULL CONSTRAINT DF_seg_roles_productivo DEFAULT (0),
    activo bit NOT NULL CONSTRAINT DF_seg_roles_activo DEFAULT (1),
    CONSTRAINT UQ_seg_roles_codigo UNIQUE (codigo),
    CONSTRAINT CK_seg_roles_codigo CHECK (LEN(LTRIM(RTRIM(codigo))) > 0),
    CONSTRAINT CK_seg_roles_nombre CHECK (LEN(LTRIM(RTRIM(nombre))) > 0)
);

CREATE TABLE seg.empleados_roles
(
    empleado_rol_id bigint IDENTITY(1,1) NOT NULL
        CONSTRAINT PK_seg_empleados_roles PRIMARY KEY,
    empleado_id bigint NOT NULL,
    rol_id smallint NOT NULL,
    desde_utc datetime2(3) NOT NULL,
    hasta_utc datetime2(3) NULL,
    asignado_por_empleado_id bigint NULL,
    asignado_por_cuenta nvarchar(256) NULL,
    motivo nvarchar(250) NULL,
    version rowversion NOT NULL,
    CONSTRAINT FK_seg_empleados_roles_empleado FOREIGN KEY (empleado_id)
        REFERENCES seg.empleados (empleado_id),
    CONSTRAINT FK_seg_empleados_roles_rol FOREIGN KEY (rol_id)
        REFERENCES seg.roles (rol_id),
    CONSTRAINT FK_seg_empleados_roles_asignador FOREIGN KEY (asignado_por_empleado_id)
        REFERENCES seg.empleados (empleado_id),
    CONSTRAINT CK_seg_empleados_roles_vigencia
        CHECK (hasta_utc IS NULL OR hasta_utc >= desde_utc),
    CONSTRAINT CK_seg_empleados_roles_autor
        CHECK (asignado_por_empleado_id IS NOT NULL OR asignado_por_cuenta IS NOT NULL)
);

CREATE TABLE cfg.lineas_dispositivos
(
    linea_dispositivo_id bigint IDENTITY(1,1) NOT NULL
        CONSTRAINT PK_cfg_lineas_dispositivos PRIMARY KEY,
    linea_id bigint NOT NULL,
    dispositivo_id bigint NOT NULL,
    asignado_desde_utc datetime2(3) NOT NULL,
    asignado_hasta_utc datetime2(3) NULL,
    asignado_por_empleado_id bigint NULL,
    asignado_por_cuenta nvarchar(256) NULL,
    motivo nvarchar(250) NULL,
    version rowversion NOT NULL,
    CONSTRAINT FK_cfg_lineas_dispositivos_linea FOREIGN KEY (linea_id)
        REFERENCES cfg.lineas (linea_id),
    CONSTRAINT FK_cfg_lineas_dispositivos_dispositivo FOREIGN KEY (dispositivo_id)
        REFERENCES cfg.dispositivos (dispositivo_id),
    CONSTRAINT FK_cfg_lineas_dispositivos_empleado FOREIGN KEY (asignado_por_empleado_id)
        REFERENCES seg.empleados (empleado_id),
    CONSTRAINT CK_cfg_lineas_dispositivos_vigencia
        CHECK (asignado_hasta_utc IS NULL OR asignado_hasta_utc >= asignado_desde_utc),
    CONSTRAINT CK_cfg_lineas_dispositivos_autor
        CHECK (asignado_por_empleado_id IS NOT NULL OR asignado_por_cuenta IS NOT NULL)
);

CREATE TABLE cfg.lineas_impresoras
(
    linea_impresora_id bigint IDENTITY(1,1) NOT NULL
        CONSTRAINT PK_cfg_lineas_impresoras PRIMARY KEY,
    linea_id bigint NOT NULL,
    impresora_id bigint NOT NULL,
    es_principal bit NOT NULL,
    asignado_desde_utc datetime2(3) NOT NULL,
    asignado_hasta_utc datetime2(3) NULL,
    asignado_por_empleado_id bigint NULL,
    asignado_por_cuenta nvarchar(256) NULL,
    motivo nvarchar(250) NULL,
    version rowversion NOT NULL,
    CONSTRAINT FK_cfg_lineas_impresoras_linea FOREIGN KEY (linea_id)
        REFERENCES cfg.lineas (linea_id),
    CONSTRAINT FK_cfg_lineas_impresoras_impresora FOREIGN KEY (impresora_id)
        REFERENCES cfg.impresoras (impresora_id),
    CONSTRAINT FK_cfg_lineas_impresoras_empleado FOREIGN KEY (asignado_por_empleado_id)
        REFERENCES seg.empleados (empleado_id),
    CONSTRAINT CK_cfg_lineas_impresoras_vigencia
        CHECK (asignado_hasta_utc IS NULL OR asignado_hasta_utc >= asignado_desde_utc),
    CONSTRAINT CK_cfg_lineas_impresoras_autor
        CHECK (asignado_por_empleado_id IS NOT NULL OR asignado_por_cuenta IS NOT NULL)
);

CREATE TABLE nav.entornos
(
    entorno_nav_id smallint IDENTITY(1,1) NOT NULL
        CONSTRAINT PK_nav_entornos PRIMARY KEY,
    codigo nvarchar(30) NOT NULL,
    nombre nvarchar(100) NOT NULL,
    activo bit NOT NULL CONSTRAINT DF_nav_entornos_activo DEFAULT (1),
    CONSTRAINT UQ_nav_entornos_codigo UNIQUE (codigo),
    CONSTRAINT CK_nav_entornos_codigo CHECK (LEN(LTRIM(RTRIM(codigo))) > 0),
    CONSTRAINT CK_nav_entornos_nombre CHECK (LEN(LTRIM(RTRIM(nombre))) > 0)
);

CREATE TABLE nav.empresas
(
    empresa_nav_id bigint IDENTITY(1,1) NOT NULL
        CONSTRAINT PK_nav_empresas PRIMARY KEY,
    entorno_nav_id smallint NOT NULL,
    codigo nvarchar(50) NOT NULL,
    nombre nvarchar(150) NOT NULL,
    activo bit NOT NULL CONSTRAINT DF_nav_empresas_activo DEFAULT (1),
    CONSTRAINT FK_nav_empresas_entorno FOREIGN KEY (entorno_nav_id)
        REFERENCES nav.entornos (entorno_nav_id),
    CONSTRAINT UQ_nav_empresas_entorno_codigo UNIQUE (entorno_nav_id, codigo),
    CONSTRAINT CK_nav_empresas_codigo CHECK (LEN(LTRIM(RTRIM(codigo))) > 0),
    CONSTRAINT CK_nav_empresas_nombre CHECK (LEN(LTRIM(RTRIM(nombre))) > 0)
);

COMMIT;
