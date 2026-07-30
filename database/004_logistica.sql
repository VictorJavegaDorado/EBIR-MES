SET NOCOUNT ON;
SET XACT_ABORT ON;

IF DB_NAME() <> N'EBIR_MES_TEST'
    THROW 51000, 'Script permitido unicamente en EBIR_MES_TEST.', 1;

BEGIN TRANSACTION;

CREATE TABLE [log].motivos_scrap
(
    motivo_scrap_id smallint IDENTITY(1,1) NOT NULL
        CONSTRAINT PK_log_motivos_scrap PRIMARY KEY,
    categoria nvarchar(20) NOT NULL,
    codigo nvarchar(50) NOT NULL,
    descripcion nvarchar(150) NOT NULL,
    requiere_descripcion bit NOT NULL CONSTRAINT DF_log_motivos_descripcion DEFAULT (0),
    activo bit NOT NULL CONSTRAINT DF_log_motivos_activo DEFAULT (1),
    orden_visual smallint NOT NULL CONSTRAINT DF_log_motivos_orden DEFAULT (0),
    CONSTRAINT UQ_log_motivos_categoria_codigo UNIQUE (categoria, codigo),
    CONSTRAINT CK_log_motivos_categoria CHECK (categoria IN (N'LUNA', N'COMPONENTE')),
    CONSTRAINT CK_log_motivos_orden CHECK (orden_visual >= 0)
);

CREATE TABLE [log].scrap
(
    scrap_id bigint IDENTITY(1,1) NOT NULL
        CONSTRAINT PK_log_scrap PRIMARY KEY,
    scrap_uid uniqueidentifier NOT NULL
        CONSTRAINT DF_log_scrap_uid DEFAULT (NEWSEQUENTIALID()),
    orden_id bigint NOT NULL,
    sesion_linea_id bigint NOT NULL,
    linea_id bigint NOT NULL,
    componente_orden_id bigint NOT NULL,
    componente_codigo_snapshot nvarchar(50) NOT NULL,
    componente_descripcion_snapshot nvarchar(250) NOT NULL,
    motivo_scrap_id smallint NOT NULL,
    cantidad int NOT NULL,
    descripcion nvarchar(1000) NULL,
    registrado_por_empleado_id bigint NOT NULL,
    registrado_utc datetime2(3) NOT NULL CONSTRAINT DF_log_scrap_registrado DEFAULT (SYSUTCDATETIME()),
    version rowversion NOT NULL,
    CONSTRAINT FK_log_scrap_sesion_orden_linea FOREIGN KEY (sesion_linea_id, orden_id, linea_id)
        REFERENCES prod.sesiones_linea (sesion_linea_id, orden_id, linea_id),
    CONSTRAINT FK_log_scrap_componente_orden FOREIGN KEY (componente_orden_id, orden_id)
        REFERENCES nav.componentes_orden (componente_orden_id, orden_id),
    CONSTRAINT FK_log_scrap_motivo FOREIGN KEY (motivo_scrap_id)
        REFERENCES [log].motivos_scrap (motivo_scrap_id),
    CONSTRAINT FK_log_scrap_autor FOREIGN KEY (registrado_por_empleado_id)
        REFERENCES seg.empleados (empleado_id),
    CONSTRAINT UQ_log_scrap_uid UNIQUE (scrap_uid),
    CONSTRAINT UQ_log_scrap_id_orden UNIQUE (scrap_id, orden_id),
    CONSTRAINT CK_log_scrap_cantidad CHECK (cantidad > 0)
);

CREATE TABLE [log].revisiones_scrap
(
    revision_scrap_id bigint IDENTITY(1,1) NOT NULL
        CONSTRAINT PK_log_revisiones_scrap PRIMARY KEY,
    revision_uid uniqueidentifier NOT NULL
        CONSTRAINT DF_log_revisiones_uid DEFAULT (NEWSEQUENTIALID()),
    scrap_id bigint NOT NULL,
    orden_id bigint NOT NULL,
    numero_revision int NOT NULL,
    componente_orden_id bigint NOT NULL,
    componente_codigo_snapshot nvarchar(50) NOT NULL,
    componente_descripcion_snapshot nvarchar(250) NOT NULL,
    motivo_scrap_id smallint NOT NULL,
    cantidad int NOT NULL,
    descripcion nvarchar(1000) NULL,
    es_anulacion bit NOT NULL CONSTRAINT DF_log_revisiones_anulacion DEFAULT (0),
    ajustado_por_supervisor_id bigint NOT NULL,
    motivo_ajuste nvarchar(500) NOT NULL,
    ajustado_utc datetime2(3) NOT NULL CONSTRAINT DF_log_revisiones_fecha DEFAULT (SYSUTCDATETIME()),
    CONSTRAINT FK_log_revisiones_scrap_orden FOREIGN KEY (scrap_id, orden_id)
        REFERENCES [log].scrap (scrap_id, orden_id),
    CONSTRAINT FK_log_revisiones_componente_orden FOREIGN KEY (componente_orden_id, orden_id)
        REFERENCES nav.componentes_orden (componente_orden_id, orden_id),
    CONSTRAINT FK_log_revisiones_motivo FOREIGN KEY (motivo_scrap_id)
        REFERENCES [log].motivos_scrap (motivo_scrap_id),
    CONSTRAINT FK_log_revisiones_supervisor FOREIGN KEY (ajustado_por_supervisor_id)
        REFERENCES seg.empleados (empleado_id),
    CONSTRAINT UQ_log_revisiones_uid UNIQUE (revision_uid),
    CONSTRAINT UQ_log_revisiones_numero UNIQUE (scrap_id, numero_revision),
    CONSTRAINT CK_log_revisiones_numero CHECK (numero_revision > 0),
    CONSTRAINT CK_log_revisiones_cantidad
        CHECK ((es_anulacion = 0 AND cantidad > 0) OR
               (es_anulacion = 1 AND cantidad = 0)),
    CONSTRAINT CK_log_revisiones_motivo CHECK (LEN(LTRIM(RTRIM(motivo_ajuste))) > 0)
);

CREATE TABLE [log].solicitudes_reaprovisionamiento
(
    solicitud_id bigint IDENTITY(1,1) NOT NULL
        CONSTRAINT PK_log_solicitudes PRIMARY KEY,
    solicitud_uid uniqueidentifier NOT NULL
        CONSTRAINT DF_log_solicitudes_uid DEFAULT (NEWSEQUENTIALID()),
    orden_id bigint NOT NULL,
    linea_id bigint NOT NULL,
    sesion_linea_id bigint NOT NULL,
    scrap_id bigint NULL,
    componente_orden_id bigint NOT NULL,
    cantidad_solicitada int NOT NULL,
    estado nvarchar(20) NOT NULL CONSTRAINT DF_log_solicitudes_estado DEFAULT (N'PENDIENTE'),
    solicitada_por_empleado_id bigint NOT NULL,
    asignada_a_empleado_id bigint NULL,
    solicitada_utc datetime2(3) NOT NULL CONSTRAINT DF_log_solicitudes_fecha DEFAULT (SYSUTCDATETIME()),
    aceptada_utc datetime2(3) NULL,
    en_camino_utc datetime2(3) NULL,
    entregada_utc datetime2(3) NULL,
    rechazada_utc datetime2(3) NULL,
    cancelada_utc datetime2(3) NULL,
    motivo_rechazo nvarchar(500) NULL,
    motivo_cancelacion nvarchar(500) NULL,
    version rowversion NOT NULL,
    CONSTRAINT FK_log_solicitudes_sesion_orden_linea FOREIGN KEY (sesion_linea_id, orden_id, linea_id)
        REFERENCES prod.sesiones_linea (sesion_linea_id, orden_id, linea_id),
    CONSTRAINT FK_log_solicitudes_scrap_orden FOREIGN KEY (scrap_id, orden_id)
        REFERENCES [log].scrap (scrap_id, orden_id),
    CONSTRAINT FK_log_solicitudes_componente_orden FOREIGN KEY (componente_orden_id, orden_id)
        REFERENCES nav.componentes_orden (componente_orden_id, orden_id),
    CONSTRAINT FK_log_solicitudes_solicitante FOREIGN KEY (solicitada_por_empleado_id)
        REFERENCES seg.empleados (empleado_id),
    CONSTRAINT FK_log_solicitudes_asignada FOREIGN KEY (asignada_a_empleado_id)
        REFERENCES seg.empleados (empleado_id),
    CONSTRAINT UQ_log_solicitudes_uid UNIQUE (solicitud_uid),
    CONSTRAINT CK_log_solicitudes_cantidad CHECK (cantidad_solicitada > 0),
    CONSTRAINT CK_log_solicitudes_estado
        CHECK (estado IN (N'PENDIENTE', N'ACEPTADA', N'EN_CAMINO', N'ENTREGADA', N'RECHAZADA', N'CANCELADA')),
    CONSTRAINT CK_log_solicitudes_rechazo
        CHECK (estado <> N'RECHAZADA' OR (rechazada_utc IS NOT NULL AND motivo_rechazo IS NOT NULL)),
    CONSTRAINT CK_log_solicitudes_cancelacion
        CHECK (estado <> N'CANCELADA' OR (cancelada_utc IS NOT NULL AND motivo_cancelacion IS NOT NULL)),
    CONSTRAINT CK_log_solicitudes_transiciones
        CHECK (
            estado = N'PENDIENTE'
            OR (estado = N'ACEPTADA' AND asignada_a_empleado_id IS NOT NULL AND aceptada_utc IS NOT NULL)
            OR (estado = N'EN_CAMINO' AND asignada_a_empleado_id IS NOT NULL AND aceptada_utc IS NOT NULL AND en_camino_utc IS NOT NULL)
            OR (estado = N'ENTREGADA' AND asignada_a_empleado_id IS NOT NULL AND aceptada_utc IS NOT NULL AND en_camino_utc IS NOT NULL AND entregada_utc IS NOT NULL)
            OR (estado = N'RECHAZADA' AND rechazada_utc IS NOT NULL AND motivo_rechazo IS NOT NULL)
            OR (estado = N'CANCELADA' AND cancelada_utc IS NOT NULL AND motivo_cancelacion IS NOT NULL)
        )
);

CREATE TABLE [log].historial_solicitudes
(
    historial_solicitud_id bigint IDENTITY(1,1) NOT NULL
        CONSTRAINT PK_log_historial_solicitudes PRIMARY KEY,
    solicitud_id bigint NOT NULL,
    estado_anterior nvarchar(20) NULL,
    estado_nuevo nvarchar(20) NOT NULL,
    empleado_id bigint NOT NULL,
    fecha_utc datetime2(3) NOT NULL CONSTRAINT DF_log_historial_fecha DEFAULT (SYSUTCDATETIME()),
    comentario nvarchar(500) NULL,
    CONSTRAINT FK_log_historial_solicitud FOREIGN KEY (solicitud_id)
        REFERENCES [log].solicitudes_reaprovisionamiento (solicitud_id),
    CONSTRAINT FK_log_historial_empleado FOREIGN KEY (empleado_id)
        REFERENCES seg.empleados (empleado_id),
    CONSTRAINT CK_log_historial_estado_anterior
        CHECK (estado_anterior IS NULL OR estado_anterior IN
               (N'PENDIENTE', N'ACEPTADA', N'EN_CAMINO', N'ENTREGADA', N'RECHAZADA', N'CANCELADA')),
    CONSTRAINT CK_log_historial_estado_nuevo
        CHECK (estado_nuevo IN
               (N'PENDIENTE', N'ACEPTADA', N'EN_CAMINO', N'ENTREGADA', N'RECHAZADA', N'CANCELADA'))
);

COMMIT;
