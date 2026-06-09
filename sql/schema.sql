-- =====================================================================
-- GS-Cloud — Telemetria Aeroespacial
-- Schema do RDS MySQL 8.x
-- Execute este script UMA vez no MySQL Workbench após criar o RDS.
-- =====================================================================

CREATE DATABASE IF NOT EXISTS aeroespacial
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_0900_ai_ci;

USE aeroespacial;

-- ---------------------------------------------------------------------
-- 1) Missões / voos (cabeçalho). `descricao` é texto livre -> combustível p/ RAG.
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS missao (
  id_missao     INT UNSIGNED NOT NULL AUTO_INCREMENT,
  codigo_missao VARCHAR(40)  NOT NULL,
  nome          VARCHAR(160) NULL,
  veiculo       VARCHAR(120) NULL,
  origem        VARCHAR(120) NULL,
  destino       VARCHAR(120) NULL,
  data_inicio   DATETIME(6)  NULL,
  data_fim      DATETIME(6)  NULL,
  descricao     TEXT         NULL,
  criado_em     TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id_missao),
  UNIQUE KEY uq_missao_codigo (codigo_missao)
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- 2) Telemetria (alta volumetria) — alvo da ingestão do CSV.
--    Medições em DECIMAL (precisão exata) e timestamp com microssegundos.
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS telemetria (
  id_telemetria     BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  id_missao         INT UNSIGNED    NOT NULL,
  timestamp_leitura DATETIME(6)     NOT NULL,
  altitude_m        DECIMAL(10,3)   NULL,
  velocidade_ms     DECIMAL(10,3)   NULL,
  temperatura_c     DECIMAL(7,3)    NULL,
  pressao_pa        DECIMAL(12,3)   NULL,
  vibracao_g        DECIMAL(8,4)    NULL,
  combustivel_pct   DECIMAL(6,3)    NULL,
  latitude          DECIMAL(9,6)    NULL,
  longitude         DECIMAL(9,6)    NULL,
  status_sensor     VARCHAR(40)     NULL,
  arquivo_origem    VARCHAR(255)    NULL,
  criado_em         TIMESTAMP       NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id_telemetria),
  -- Idempotencia: cada missao so tem uma leitura por instante. A reingestao
  -- do mesmo arquivo (INSERT IGNORE) nao gera duplicatas. Esta chave tambem
  -- cobre a FK em id_missao (coluna mais a esquerda) e consultas por missao+tempo.
  UNIQUE KEY uq_tel_leitura (id_missao, timestamp_leitura),
  KEY idx_tel_ts (timestamp_leitura),
  CONSTRAINT fk_tel_missao FOREIGN KEY (id_missao)
    REFERENCES missao (id_missao)
    ON UPDATE CASCADE ON DELETE RESTRICT
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- 3) Log de ingestão — EVIDÊNCIA da automação dentro do próprio banco.
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS ingestao_log (
  id_ingestao          BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  nome_arquivo         VARCHAR(255)    NOT NULL,
  bucket               VARCHAR(120)    NOT NULL,
  qtd_linhas_lidas     INT UNSIGNED    NOT NULL DEFAULT 0,
  qtd_linhas_inseridas INT UNSIGNED    NOT NULL DEFAULT 0,
  qtd_erros            INT UNSIGNED    NOT NULL DEFAULT 0,
  status               ENUM('SUCESSO','PARCIAL','ERRO') NOT NULL,
  mensagem             VARCHAR(1000)   NULL,
  request_id           VARCHAR(80)     NULL,
  iniciado_em          DATETIME(6)     NOT NULL,
  finalizado_em        DATETIME(6)     NOT NULL,
  PRIMARY KEY (id_ingestao),
  KEY idx_log_arquivo (nome_arquivo),
  KEY idx_log_fim (finalizado_em)
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- 4) Preparação RAG (etapa futura) — documentos + embeddings.
--    `embedding` fica como JSON (placeholder do vetor). Em produção:
--    MySQL 9 type VECTOR, ou migrar p/ pgvector / OpenSearch.
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS documento_rag (
  id_documento BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  id_missao    INT UNSIGNED    NULL,
  fonte        VARCHAR(120)    NULL,
  conteudo     TEXT            NOT NULL,
  metadados    JSON            NULL,
  embedding    JSON            NULL,
  criado_em    TIMESTAMP       NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id_documento),
  KEY idx_doc_missao (id_missao),
  CONSTRAINT fk_doc_missao FOREIGN KEY (id_missao)
    REFERENCES missao (id_missao)
    ON UPDATE CASCADE ON DELETE SET NULL
) ENGINE=InnoDB;

-- =====================================================================
-- Consultas de EXPLORAÇÃO (rodar no Workbench após a ingestão)
-- =====================================================================

-- Volume ingerido por missão
-- SELECT m.codigo_missao, COUNT(*) AS leituras,
--        MIN(t.timestamp_leitura) AS inicio, MAX(t.timestamp_leitura) AS fim
-- FROM telemetria t JOIN missao m ON m.id_missao = t.id_missao
-- GROUP BY m.codigo_missao;

-- Trilha de automação (evidência)
-- SELECT nome_arquivo, qtd_linhas_inseridas, qtd_erros, status, finalizado_em
-- FROM ingestao_log ORDER BY finalizado_em DESC;

-- Picos de telemetria por missão
-- SELECT m.codigo_missao,
--        MAX(t.altitude_m)     AS altitude_max_m,
--        AVG(t.velocidade_ms)  AS vel_media_ms,
--        MAX(t.temperatura_c)  AS temp_max_c
-- FROM telemetria t JOIN missao m ON m.id_missao = t.id_missao
-- GROUP BY m.codigo_missao;
