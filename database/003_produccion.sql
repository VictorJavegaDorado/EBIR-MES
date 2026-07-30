SET NOCOUNT ON;
SET XACT_ABORT ON;

IF DB_NAME() <> N'EBIR_MES_TEST'
    THROW 51000, 'Script permitido unicamente en EBIR_MES_TEST.', 1;

BEGIN TRANSACTION;

CREATE TABLE prod.ordenes
(
    orden_id bigint IDENTITY(1,1) NOT NULL
        CONSTRAINT PK_prod_ordenes PRIMARY KEY,
    orden_uid uniqueidentifier NOT NULL
        CONSTRAINT DF_prod_ordenes_uid DEFAULT (NEWSEQUENTIALID()),
    empresa_nav_id bigint NOT NULL,
    numero_orden nvarchar(30) NOT NULL,
    producto_codigo nvarchar(50) NOT NULL,
    producto_descripcion nvarchar(250) NOT NULL,
    producto_barcode nvarchar(100) NULL,
    lote nvarchar(50) NOT NULL,
    cantidad_objetivo int NOT NULL,
    cantidad_buena_acumulada int NOT NULL CONSTRAINT DF_prod_ordenes_buenas DEFAULT (0),
    cantidad_reservada_activa int NOT NULL CONSTRAINT DF_prod_ordenes_reservada DEFAULT (0),
    cantidad_scrap_acumulada int NOT NULL CONSTRAINT DF_prod_ordenes_scrap DEFAULT (0),
    tiempo_ejecucion_nav_min decimal(12,1) NOT NULL,
    modo_trabajo nvarchar(20) NOT NULL CONSTRAINT DF_prod_ordenes_modo DEFAULT (N'NORMAL'),
    estado nvarchar(30) NOT NULL CONSTRAINT DF_prod_ordenes_estado DEFAULT (N'IMPORTADA'),
    datos_nav_originales nvarchar(max) NOT NULL,
    importada_utc datetime2(3) NOT NULL CONSTRAINT DF_prod_ordenes_importada DEFAULT (SYSUTCDATETIME()),
    finalizada_utc datetime2(3) NULL,
    version rowversion NOT NULL,
    CONSTRAINT FK_prod_ordenes_empresa FOREIGN KEY (empresa_nav_id)
        REFERENCES nav.empresas (empresa_nav_id),
    CONSTRAINT UQ_prod_ordenes_uid UNIQUE (orden_uid),
    CONSTRAINT UQ_prod_ordenes_empresa_numero UNIQUE (empresa_nav_id, numero_orden),
    CONSTRAINT CK_prod_ordenes_objetivo CHECK (cantidad_objetivo > 0),
    CONSTRAINT CK_prod_ordenes_buenas CHECK (cantidad_buena_acumulada >= 0),
    CONSTRAINT CK_prod_ordenes_reservada CHECK (cantidad_reservada_activa >= 0),
    CONSTRAINT CK_prod_ordenes_scrap CHECK (cantidad_scrap_acumulada >= 0),
    CONSTRAINT CK_prod_ordenes_limite
        CHECK (cantidad_buena_acumulada + cantidad_reservada_activa <= cantidad_objetivo),
    CONSTRAINT CK_prod_ordenes_tiempo CHECK (tiempo_ejecucion_nav_min > 0),
    CONSTRAINT CK_prod_ordenes_modo CHECK (modo_trabajo IN (N'NORMAL', N'MULTILINEA')),
    CONSTRAINT CK_prod_ordenes_estado
        CHECK (estado IN (N'IMPORTADA', N'ABIERTA', N'PICO_PENDIENTE', N'PENDIENTE_CIERRE',
                          N'PENDIENTE_NAV', N'ERROR_NAV', N'FINALIZADA', N'REVISION')),
    CONSTRAINT CK_prod_ordenes_numero CHECK (LEN(LTRIM(RTRIM(numero_orden))) > 0),
    CONSTRAINT CK_prod_ordenes_producto CHECK (LEN(LTRIM(RTRIM(producto_codigo))) > 0),
    CONSTRAINT CK_prod_ordenes_lote CHECK (LEN(LTRIM(RTRIM(lote))) > 0),
    CONSTRAINT CK_prod_ordenes_json CHECK (ISJSON(datos_nav_originales) = 1)
);

CREATE TABLE nav.componentes_orden
(
    componente_orden_id bigint IDENTITY(1,1) NOT NULL
        CONSTRAINT PK_nav_componentes_orden PRIMARY KEY,
    orden_id bigint NOT NULL,
    codigo_componente nvarchar(50) NOT NULL,
    descripcion nvarchar(250) NOT NULL,
    unidad_medida nvarchar(20) NULL,
    cantidad_teorica decimal(18,4) NULL,
    datos_nav_originales nvarchar(max) NULL,
    consultado_utc datetime2(3) NOT NULL CONSTRAINT DF_nav_componentes_consultado DEFAULT (SYSUTCDATETIME()),
    CONSTRAINT FK_nav_componentes_orden FOREIGN KEY (orden_id)
        REFERENCES prod.ordenes (orden_id),
    CONSTRAINT UQ_nav_componentes_orden_codigo UNIQUE (orden_id, codigo_componente),
    CONSTRAINT CK_nav_componentes_cantidad CHECK (cantidad_teorica IS NULL OR cantidad_teorica >= 0),
    CONSTRAINT CK_nav_componentes_json
        CHECK (datos_nav_originales IS NULL OR ISJSON(datos_nav_originales) = 1)
);

CREATE TABLE prod.formatos_palet_orden
(
    formato_palet_orden_id bigint IDENTITY(1,1) NOT NULL
        CONSTRAINT PK_prod_formatos_palet_orden PRIMARY KEY,
    orden_id bigint NOT NULL,
    codigo_formato nvarchar(50) NOT NULL,
    unidades_por_palet int NOT NULL,
    descripcion nvarchar(150) NULL,
    es_predeterminado_nav bit NOT NULL CONSTRAINT DF_prod_formatos_predeterminado DEFAULT (0),
    datos_nav_originales nvarchar(max) NULL,
    activo bit NOT NULL CONSTRAINT DF_prod_formatos_activo DEFAULT (1),
    consultado_utc datetime2(3) NOT NULL CONSTRAINT DF_prod_formatos_consultado DEFAULT (SYSUTCDATETIME()),
    version rowversion NOT NULL,
    CONSTRAINT FK_prod_formatos_orden FOREIGN KEY (orden_id)
        REFERENCES prod.ordenes (orden_id),
    CONSTRAINT UQ_prod_formatos_id_orden UNIQUE (formato_palet_orden_id, orden_id),
    CONSTRAINT UQ_prod_formatos_orden_codigo UNIQUE (orden_id, codigo_formato),
    CONSTRAINT CK_prod_formatos_codigo CHECK (LEN(LTRIM(RTRIM(codigo_formato))) > 0),
    CONSTRAINT CK_prod_formatos_unidades CHECK (unidades_por_palet > 0),
    CONSTRAINT CK_prod_formatos_json
        CHECK (datos_nav_originales IS NULL OR ISJSON(datos_nav_originales) = 1)
);

CREATE TABLE prod.sesiones_linea
(
    sesion_linea_id bigint IDENTITY(1,1) NOT NULL
        CONSTRAINT PK_prod_sesiones_linea PRIMARY KEY,
    sesion_uid uniqueidentifier NOT NULL
        CONSTRAINT DF_prod_sesiones_uid DEFAULT (NEWSEQUENTIALID()),
    orden_id bigint NOT NULL,
    linea_id bigint NOT NULL,
    turno_id smallint NOT NULL,
    formato_palet_orden_id bigint NOT NULL,
    fecha_operativa date NOT NULL,
    estado nvarchar(30) NOT NULL CONSTRAINT DF_prod_sesiones_estado DEFAULT (N'CARGADA'),
    cambio_turno_pendiente bit NOT NULL CONSTRAINT DF_prod_sesiones_cambio DEFAULT (0),
    cargada_utc datetime2(3) NOT NULL CONSTRAINT DF_prod_sesiones_cargada DEFAULT (SYSUTCDATETIME()),
    iniciada_utc datetime2(3) NULL,
    finalizada_utc datetime2(3) NULL,
    motivo_fin nvarchar(50) NULL,
    cargada_por_empleado_id bigint NOT NULL,
    cerrada_por_empleado_id bigint NULL,
    version rowversion NOT NULL,
    CONSTRAINT FK_prod_sesiones_orden FOREIGN KEY (orden_id)
        REFERENCES prod.ordenes (orden_id),
    CONSTRAINT FK_prod_sesiones_linea FOREIGN KEY (linea_id)
        REFERENCES cfg.lineas (linea_id),
    CONSTRAINT FK_prod_sesiones_turno FOREIGN KEY (turno_id)
        REFERENCES cfg.turnos (turno_id),
    CONSTRAINT FK_prod_sesiones_formato_orden FOREIGN KEY (formato_palet_orden_id, orden_id)
        REFERENCES prod.formatos_palet_orden (formato_palet_orden_id, orden_id),
    CONSTRAINT FK_prod_sesiones_cargada_por FOREIGN KEY (cargada_por_empleado_id)
        REFERENCES seg.empleados (empleado_id),
    CONSTRAINT FK_prod_sesiones_cerrada_por FOREIGN KEY (cerrada_por_empleado_id)
        REFERENCES seg.empleados (empleado_id),
    CONSTRAINT UQ_prod_sesiones_uid UNIQUE (sesion_uid),
    CONSTRAINT UQ_prod_sesiones_id_orden UNIQUE (sesion_linea_id, orden_id),
    CONSTRAINT UQ_prod_sesiones_id_linea UNIQUE (sesion_linea_id, linea_id),
    CONSTRAINT CK_prod_sesiones_estado
        CHECK (estado IN (N'CARGADA', N'PRODUCIENDO', N'SIN_OPERARIOS', N'STANDBY',
                          N'PICO_PENDIENTE', N'FINALIZADA_TURNO', N'ORDEN_COMPLETADA',
                          N'CANCELADA_SIN_PRODUCCION', N'BLOQUEADA')),
    CONSTRAINT CK_prod_sesiones_fechas
        CHECK (finalizada_utc IS NULL OR finalizada_utc >= cargada_utc)
);

CREATE TABLE prod.estados_linea
(
    linea_id bigint NOT NULL
        CONSTRAINT PK_prod_estados_linea PRIMARY KEY,
    sesion_linea_id bigint NULL,
    estado nvarchar(30) NOT NULL CONSTRAINT DF_prod_estados_linea_estado DEFAULT (N'LIBRE'),
    motivo_bloqueo nvarchar(250) NULL,
    actualizado_utc datetime2(3) NOT NULL CONSTRAINT DF_prod_estados_linea_actualizado DEFAULT (SYSUTCDATETIME()),
    version rowversion NOT NULL,
    CONSTRAINT FK_prod_estados_linea_linea FOREIGN KEY (linea_id)
        REFERENCES cfg.lineas (linea_id),
    CONSTRAINT FK_prod_estados_linea_sesion FOREIGN KEY (sesion_linea_id, linea_id)
        REFERENCES prod.sesiones_linea (sesion_linea_id, linea_id),
    CONSTRAINT CK_prod_estados_linea_estado
        CHECK (estado IN (N'LIBRE', N'ORDEN_CARGADA', N'PRODUCIENDO', N'SIN_OPERARIOS',
                          N'STANDBY', N'PICO_PENDIENTE', N'PENDIENTE_NAV',
                          N'BLOQUEADA', N'FUERA_SERVICIO'))
);

CREATE TABLE prod.fichajes
(
    fichaje_id bigint IDENTITY(1,1) NOT NULL
        CONSTRAINT PK_prod_fichajes PRIMARY KEY,
    fichaje_uid uniqueidentifier NOT NULL
        CONSTRAINT DF_prod_fichajes_uid DEFAULT (NEWSEQUENTIALID()),
    sesion_linea_id bigint NOT NULL,
    linea_id bigint NOT NULL,
    empleado_id bigint NOT NULL,
    entrada_utc datetime2(3) NOT NULL,
    salida_utc datetime2(3) NULL,
    estado nvarchar(20) NOT NULL CONSTRAINT DF_prod_fichajes_estado DEFAULT (N'ABIERTO'),
    cerrado_por_sistema bit NOT NULL CONSTRAINT DF_prod_fichajes_sistema DEFAULT (0),
    corregido_por_empleado_id bigint NULL,
    motivo_correccion nvarchar(500) NULL,
    version rowversion NOT NULL,
    CONSTRAINT FK_prod_fichajes_sesion_linea FOREIGN KEY (sesion_linea_id, linea_id)
        REFERENCES prod.sesiones_linea (sesion_linea_id, linea_id),
    CONSTRAINT FK_prod_fichajes_empleado FOREIGN KEY (empleado_id)
        REFERENCES seg.empleados (empleado_id),
    CONSTRAINT FK_prod_fichajes_corrector FOREIGN KEY (corregido_por_empleado_id)
        REFERENCES seg.empleados (empleado_id),
    CONSTRAINT UQ_prod_fichajes_uid UNIQUE (fichaje_uid),
    CONSTRAINT CK_prod_fichajes_estado CHECK (estado IN (N'ABIERTO', N'CERRADO', N'CORREGIDO')),
    CONSTRAINT CK_prod_fichajes_fechas CHECK (salida_utc IS NULL OR salida_utc >= entrada_utc),
    CONSTRAINT CK_prod_fichajes_correccion
        CHECK (corregido_por_empleado_id IS NULL OR motivo_correccion IS NOT NULL)
);

CREATE TABLE prod.paros_operario
(
    paro_operario_id bigint IDENTITY(1,1) NOT NULL
        CONSTRAINT PK_prod_paros_operario PRIMARY KEY,
    fichaje_id bigint NOT NULL,
    motivo nvarchar(30) NOT NULL,
    inicio_utc datetime2(3) NOT NULL,
    fin_utc datetime2(3) NULL,
    estado nvarchar(20) NOT NULL CONSTRAINT DF_prod_paros_estado DEFAULT (N'ABIERTO'),
    version rowversion NOT NULL,
    CONSTRAINT FK_prod_paros_fichaje FOREIGN KEY (fichaje_id)
        REFERENCES prod.fichajes (fichaje_id),
    CONSTRAINT CK_prod_paros_motivo CHECK (motivo IN (N'WC', N'PAUSA_CALOR')),
    CONSTRAINT CK_prod_paros_estado CHECK (estado IN (N'ABIERTO', N'CERRADO')),
    CONSTRAINT CK_prod_paros_fechas CHECK (fin_utc IS NULL OR fin_utc >= inicio_utc)
);

CREATE TABLE prod.paradas_linea
(
    parada_linea_id bigint IDENTITY(1,1) NOT NULL
        CONSTRAINT PK_prod_paradas_linea PRIMARY KEY,
    sesion_linea_id bigint NOT NULL,
    tipo nvarchar(30) NOT NULL,
    inicio_utc datetime2(3) NOT NULL,
    fin_utc datetime2(3) NULL,
    iniciada_por_empleado_id bigint NOT NULL,
    cerrada_por_empleado_id bigint NULL,
    version rowversion NOT NULL,
    CONSTRAINT FK_prod_paradas_sesion FOREIGN KEY (sesion_linea_id)
        REFERENCES prod.sesiones_linea (sesion_linea_id),
    CONSTRAINT FK_prod_paradas_iniciada FOREIGN KEY (iniciada_por_empleado_id)
        REFERENCES seg.empleados (empleado_id),
    CONSTRAINT FK_prod_paradas_cerrada FOREIGN KEY (cerrada_por_empleado_id)
        REFERENCES seg.empleados (empleado_id),
    CONSTRAINT CK_prod_paradas_tipo CHECK (tipo IN (N'STANDBY_ALMUERZO', N'SIN_OPERARIOS')),
    CONSTRAINT CK_prod_paradas_fechas CHECK (fin_utc IS NULL OR fin_utc >= inicio_utc)
);

CREATE TABLE prod.sustituciones_capacidad
(
    sustitucion_capacidad_id bigint IDENTITY(1,1) NOT NULL
        CONSTRAINT PK_prod_sustituciones PRIMARY KEY,
    sesion_linea_id bigint NOT NULL,
    operario_sustituido_id bigint NOT NULL,
    supervisor_sustituto_id bigint NOT NULL,
    fichaje_operario_id bigint NOT NULL,
    fichaje_supervisor_id bigint NOT NULL,
    inicio_utc datetime2(3) NOT NULL,
    fin_utc datetime2(3) NULL,
    estado nvarchar(20) NOT NULL CONSTRAINT DF_prod_sustituciones_estado DEFAULT (N'ACTIVA'),
    motivo nvarchar(250) NULL,
    version rowversion NOT NULL,
    CONSTRAINT FK_prod_sustituciones_sesion FOREIGN KEY (sesion_linea_id)
        REFERENCES prod.sesiones_linea (sesion_linea_id),
    CONSTRAINT FK_prod_sustituciones_operario FOREIGN KEY (operario_sustituido_id)
        REFERENCES seg.empleados (empleado_id),
    CONSTRAINT FK_prod_sustituciones_supervisor FOREIGN KEY (supervisor_sustituto_id)
        REFERENCES seg.empleados (empleado_id),
    CONSTRAINT FK_prod_sustituciones_fichaje_operario FOREIGN KEY (fichaje_operario_id)
        REFERENCES prod.fichajes (fichaje_id),
    CONSTRAINT FK_prod_sustituciones_fichaje_supervisor FOREIGN KEY (fichaje_supervisor_id)
        REFERENCES prod.fichajes (fichaje_id),
    CONSTRAINT CK_prod_sustituciones_distintos CHECK (operario_sustituido_id <> supervisor_sustituto_id),
    CONSTRAINT CK_prod_sustituciones_estado CHECK (estado IN (N'ACTIVA', N'FINALIZADA')),
    CONSTRAINT CK_prod_sustituciones_fechas CHECK (fin_utc IS NULL OR fin_utc >= inicio_utc)
);

CREATE TABLE prod.tramos_capacidad
(
    tramo_capacidad_id bigint IDENTITY(1,1) NOT NULL
        CONSTRAINT PK_prod_tramos_capacidad PRIMARY KEY,
    sesion_linea_id bigint NOT NULL,
    inicio_utc datetime2(3) NOT NULL,
    fin_utc datetime2(3) NULL,
    recursos_activos smallint NOT NULL,
    tiempo_nav_min_unidad decimal(12,1) NOT NULL,
    capacidad_teorica_hora decimal(18,4) NOT NULL,
    segundos_productivos int NOT NULL CONSTRAINT DF_prod_tramos_segundos DEFAULT (0),
    motivo_inicio nvarchar(50) NOT NULL,
    CONSTRAINT FK_prod_tramos_sesion FOREIGN KEY (sesion_linea_id)
        REFERENCES prod.sesiones_linea (sesion_linea_id),
    CONSTRAINT CK_prod_tramos_recursos CHECK (recursos_activos >= 0),
    CONSTRAINT CK_prod_tramos_tiempo CHECK (tiempo_nav_min_unidad > 0),
    CONSTRAINT CK_prod_tramos_capacidad CHECK (capacidad_teorica_hora >= 0),
    CONSTRAINT CK_prod_tramos_segundos CHECK (segundos_productivos >= 0),
    CONSTRAINT CK_prod_tramos_fechas CHECK (fin_utc IS NULL OR fin_utc >= inicio_utc)
);

CREATE TABLE prod.reservas_palet
(
    reserva_palet_id bigint IDENTITY(1,1) NOT NULL
        CONSTRAINT PK_prod_reservas_palet PRIMARY KEY,
    reserva_uid uniqueidentifier NOT NULL
        CONSTRAINT DF_prod_reservas_uid DEFAULT (NEWSEQUENTIALID()),
    orden_id bigint NOT NULL,
    sesion_linea_id bigint NOT NULL,
    cantidad_reservada int NOT NULL,
    estado nvarchar(20) NOT NULL CONSTRAINT DF_prod_reservas_estado DEFAULT (N'ACTIVA'),
    creada_por_empleado_id bigint NOT NULL,
    creada_utc datetime2(3) NOT NULL CONSTRAINT DF_prod_reservas_creada DEFAULT (SYSUTCDATETIME()),
    cerrada_utc datetime2(3) NULL,
    cancelada_por_empleado_id bigint NULL,
    motivo_cancelacion nvarchar(500) NULL,
    version rowversion NOT NULL,
    CONSTRAINT FK_prod_reservas_orden FOREIGN KEY (orden_id)
        REFERENCES prod.ordenes (orden_id),
    CONSTRAINT FK_prod_reservas_sesion_orden FOREIGN KEY (sesion_linea_id, orden_id)
        REFERENCES prod.sesiones_linea (sesion_linea_id, orden_id),
    CONSTRAINT FK_prod_reservas_creada_por FOREIGN KEY (creada_por_empleado_id)
        REFERENCES seg.empleados (empleado_id),
    CONSTRAINT FK_prod_reservas_cancelada_por FOREIGN KEY (cancelada_por_empleado_id)
        REFERENCES seg.empleados (empleado_id),
    CONSTRAINT UQ_prod_reservas_uid UNIQUE (reserva_uid),
    CONSTRAINT CK_prod_reservas_cantidad CHECK (cantidad_reservada > 0),
    CONSTRAINT CK_prod_reservas_estado CHECK (estado IN (N'ACTIVA', N'CONSUMIDA', N'CANCELADA')),
    CONSTRAINT CK_prod_reservas_cancelacion
        CHECK (estado <> N'CANCELADA' OR (cancelada_por_empleado_id IS NOT NULL AND motivo_cancelacion IS NOT NULL))
);

CREATE TABLE prod.palets
(
    palet_id bigint IDENTITY(1,1) NOT NULL
        CONSTRAINT PK_prod_palets PRIMARY KEY,
    palet_uid uniqueidentifier NOT NULL
        CONSTRAINT DF_prod_palets_uid DEFAULT (NEWSEQUENTIALID()),
    orden_id bigint NOT NULL,
    sesion_linea_id bigint NOT NULL,
    reserva_palet_id bigint NOT NULL,
    numero_palet int NOT NULL,
    codigo_visible nvarchar(100) NOT NULL,
    cantidad_buena int NOT NULL,
    es_parcial bit NOT NULL CONSTRAINT DF_prod_palets_parcial DEFAULT (0),
    motivo_parcial nvarchar(30) NULL,
    es_ultimo bit NOT NULL CONSTRAINT DF_prod_palets_ultimo DEFAULT (0),
    cerrado_por_empleado_id bigint NOT NULL,
    supervisor_responsable_id bigint NOT NULL,
    autorizado_por_supervisor_id bigint NULL,
    cerrado_utc datetime2(3) NOT NULL CONSTRAINT DF_prod_palets_cerrado DEFAULT (SYSUTCDATETIME()),
    estado nvarchar(20) NOT NULL CONSTRAINT DF_prod_palets_estado DEFAULT (N'CERRADO'),
    version rowversion NOT NULL,
    CONSTRAINT FK_prod_palets_orden FOREIGN KEY (orden_id)
        REFERENCES prod.ordenes (orden_id),
    CONSTRAINT FK_prod_palets_sesion_orden FOREIGN KEY (sesion_linea_id, orden_id)
        REFERENCES prod.sesiones_linea (sesion_linea_id, orden_id),
    CONSTRAINT FK_prod_palets_reserva FOREIGN KEY (reserva_palet_id)
        REFERENCES prod.reservas_palet (reserva_palet_id),
    CONSTRAINT FK_prod_palets_cerrado_por FOREIGN KEY (cerrado_por_empleado_id)
        REFERENCES seg.empleados (empleado_id),
    CONSTRAINT FK_prod_palets_supervisor FOREIGN KEY (supervisor_responsable_id)
        REFERENCES seg.empleados (empleado_id),
    CONSTRAINT FK_prod_palets_autorizado FOREIGN KEY (autorizado_por_supervisor_id)
        REFERENCES seg.empleados (empleado_id),
    CONSTRAINT UQ_prod_palets_uid UNIQUE (palet_uid),
    CONSTRAINT UQ_prod_palets_reserva UNIQUE (reserva_palet_id),
    CONSTRAINT UQ_prod_palets_orden_numero UNIQUE (orden_id, numero_palet),
    CONSTRAINT UQ_prod_palets_codigo UNIQUE (codigo_visible),
    CONSTRAINT CK_prod_palets_numero CHECK (numero_palet > 0),
    CONSTRAINT CK_prod_palets_codigo CHECK (LEN(LTRIM(RTRIM(codigo_visible))) > 0),
    CONSTRAINT CK_prod_palets_cantidad CHECK (cantidad_buena > 0),
    CONSTRAINT CK_prod_palets_parcial
        CHECK ((es_parcial = 0 AND motivo_parcial IS NULL) OR
               (es_parcial = 1 AND motivo_parcial IN (N'FIN_TURNO', N'FALTA_MATERIAL', N'ULTIMO_PALET'))),
    CONSTRAINT CK_prod_palets_ultimo
        CHECK (es_ultimo = 0 OR autorizado_por_supervisor_id IS NOT NULL),
    CONSTRAINT CK_prod_palets_estado CHECK (estado IN (N'CERRADO', N'ANULADO_TECNICO'))
);

COMMIT;
