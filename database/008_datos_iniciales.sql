SET NOCOUNT ON;
SET XACT_ABORT ON;

IF DB_NAME() <> N'EBIR_MES_TEST'
    THROW 51000, 'Script permitido unicamente en EBIR_MES_TEST.', 1;

BEGIN TRANSACTION;

IF NOT EXISTS (SELECT 1 FROM cfg.centros_trabajo WHERE codigo = N'CT-01')
    INSERT cfg.centros_trabajo (codigo, nombre)
    VALUES (N'CT-01', N'Paterna Sede Central');

IF NOT EXISTS (SELECT 1 FROM cfg.turnos WHERE codigo = N'MANANA')
    INSERT cfg.turnos (codigo, nombre, hora_inicio, hora_fin, admite_extension)
    VALUES (N'MANANA', N'Turno de mañana', '06:00', '14:00', 0);

IF NOT EXISTS (SELECT 1 FROM cfg.turnos WHERE codigo = N'TARDE')
    INSERT cfg.turnos (codigo, nombre, hora_inicio, hora_fin, admite_extension)
    VALUES (N'TARDE', N'Turno de tarde', '14:00', '22:00', 1);

IF NOT EXISTS (SELECT 1 FROM seg.roles WHERE codigo = N'OPERARIO')
    INSERT seg.roles (codigo, nombre, es_productivo)
    VALUES (N'OPERARIO', N'Operario', 1);

IF NOT EXISTS (SELECT 1 FROM seg.roles WHERE codigo = N'SUPERVISOR')
    INSERT seg.roles (codigo, nombre, es_productivo)
    VALUES (N'SUPERVISOR', N'Supervisor', 1);

IF NOT EXISTS (SELECT 1 FROM seg.roles WHERE codigo = N'APROVISIONADOR')
    INSERT seg.roles (codigo, nombre, es_productivo)
    VALUES (N'APROVISIONADOR', N'Aprovisionador', 0);

IF NOT EXISTS (SELECT 1 FROM nav.entornos WHERE codigo = N'EBIRTEST')
    INSERT nav.entornos (codigo, nombre)
    VALUES (N'EBIRTEST', N'Entorno de pruebas EBIRTEST');

DECLARE @motivos TABLE
(
    categoria nvarchar(20),
    codigo nvarchar(50),
    descripcion nvarchar(150),
    requiere_descripcion bit,
    orden_visual smallint
);

INSERT @motivos VALUES
(N'LUNA', N'RAYA_RAYADA', N'Raya / rayada', 0, 10),
(N'LUNA', N'DESPORTILLADA', N'Desportillada', 0, 20),
(N'LUNA', N'PICADA', N'Picada', 0, 30),
(N'LUNA', N'BURBUJA', N'Burbuja', 0, 40),
(N'LUNA', N'ROTA_LINEA', N'Rota línea', 0, 50),
(N'LUNA', N'LOGO_NOK', N'Logo NOK', 0, 60),
(N'LUNA', N'OTROS', N'Otros / sin clasificar', 1, 70),
(N'LUNA', N'ARENADO', N'Arenado', 0, 80),
(N'LUNA', N'ACABADO_SERIGRAFIA', N'Acabado / serigrafía', 0, 90),
(N'LUNA', N'MOTA_POLVO', N'Mota / polvo', 0, 100),
(N'LUNA', N'OXIDO', N'Óxido', 0, 110),
(N'LUNA', N'MANCHA', N'Mancha', 0, 120),
(N'LUNA', N'CORROSION', N'Corrosión', 0, 130),
(N'LUNA', N'VIDRIO_GENERICO', N'Vidrio (defecto genérico)', 0, 140),
(N'LUNA', N'ROTA_LOGISTICA', N'Rota logística', 0, 150),
(N'COMPONENTE', N'ROTO_PROCESO', N'Componentes rotos en proceso', 0, 10),
(N'COMPONENTE', N'TIRA_LED_FUNDIDA', N'Tira/LED fundida', 0, 20),
(N'COMPONENTE', N'CAJA_ROTA', N'Caja rota', 0, 30),
(N'COMPONENTE', N'KIT_DRIVER_SENSOR_NOK', N'Kit/driver/sensor no funciona', 0, 40),
(N'COMPONENTE', N'MARCO_ROTO_RAYADO', N'Marco roto/rayado', 0, 50),
(N'COMPONENTE', N'PERFIL_DEFECTUOSO', N'Perfil defectuoso', 0, 60),
(N'COMPONENTE', N'ARMAZON_DEFECTUOSO', N'Armazón defectuoso', 0, 70),
(N'COMPONENTE', N'ETIQUETA_EMBALAJE', N'Etiqueta embalaje defectuosa', 0, 80),
(N'COMPONENTE', N'MARCO_REPROCESO', N'Marco pelado/abierto (reproceso)', 0, 90),
(N'COMPONENTE', N'REFLECTOR_DEFECTUOSO', N'Reflector defectuoso', 0, 100),
(N'COMPONENTE', N'MARCO_DANO_DECORADO', N'Marco daño decorado', 0, 110),
(N'COMPONENTE', N'CANTONERA_DANO_DECORADO', N'Cantonera daño decorado', 0, 120),
(N'COMPONENTE', N'TIRA_GLOW', N'Tira glow (defecto)', 0, 130),
(N'COMPONENTE', N'PUERTA_ROTA', N'Puerta rota', 0, 140),
(N'COMPONENTE', N'TUBO_LED_DEFECTO', N'Tubo LED defecto', 0, 150);

INSERT [log].motivos_scrap
(
    categoria, codigo, descripcion, requiere_descripcion, orden_visual
)
SELECT
    m.categoria, m.codigo, m.descripcion, m.requiere_descripcion, m.orden_visual
FROM @motivos m
WHERE NOT EXISTS
(
    SELECT 1
    FROM [log].motivos_scrap d
    WHERE d.categoria = m.categoria
      AND d.codigo = m.codigo
);

COMMIT;
