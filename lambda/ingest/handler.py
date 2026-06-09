"""
GS-Cloud — Lambda de ingestao de telemetria aeroespacial.

Disparada por evento S3 (ObjectCreated). Para cada arquivo .csv:
  1. le o objeto do S3;
  2. valida o cabecalho e cada linha (precisao decimal preservada);
  3. faz upsert das missoes (por codigo_missao);
  4. insere a telemetria em lote no RDS MySQL (idempotente: INSERT IGNORE);
  5. grava trilha em `ingestao_log`;
  6. publica metricas via EMF (namespace GSCloud/Ingestao).

Variaveis de ambiente esperadas:
  DB_HOST, DB_USER, DB_PASSWORD, DB_NAME (default 'aeroespacial'),
  DB_PORT (default 3306), CW_NAMESPACE (default 'GSCloud/Ingestao').
"""

import csv
import io
import json
import logging
import os
import time
from datetime import datetime, timezone
from decimal import Decimal, InvalidOperation
from urllib.parse import unquote_plus

import boto3
import pymysql

logger = logging.getLogger()
logger.setLevel(logging.INFO)

s3 = boto3.client("s3")

DB_HOST = os.environ["DB_HOST"]
DB_USER = os.environ["DB_USER"]
DB_PASSWORD = os.environ["DB_PASSWORD"]
DB_NAME = os.environ.get("DB_NAME", "aeroespacial")
DB_PORT = int(os.environ.get("DB_PORT", "3306"))
CW_NAMESPACE = os.environ.get("CW_NAMESPACE", "GSCloud/Ingestao")

BATCH_SIZE = 500
COLUNAS_OBRIGATORIAS = ("codigo_missao", "timestamp_leitura")
COLUNAS_MEDIDAS = (
    "altitude_m", "velocidade_ms", "temperatura_c", "pressao_pa",
    "vibracao_g", "combustivel_pct", "latitude", "longitude",
)

# Conexao reutilizada entre invocacoes "quentes" (reduz latencia e
# o numero de conexoes abertas no RDS db.t3.micro).
_conn = None


def _get_conn():
    """Devolve a conexao global, reconectando se tiver caido."""
    global _conn
    if _conn is not None:
        try:
            _conn.ping(reconnect=True)
            return _conn
        except Exception:
            try:
                _conn.close()
            except Exception:
                pass
            _conn = None
    _conn = pymysql.connect(
        host=DB_HOST, user=DB_USER, password=DB_PASSWORD,
        database=DB_NAME, port=DB_PORT, charset="utf8mb4",
        autocommit=False, connect_timeout=10,
        cursorclass=pymysql.cursors.Cursor,
    )
    return _conn


def _num(value):
    """Valida e converte uma medida numerica preservando a precisao (Decimal).

    '' -> None. Texto invalido -> ValueError (tratado como erro de linha).
    """
    if value is None:
        return None
    value = value.strip()
    if value == "":
        return None
    try:
        return Decimal(value)
    except InvalidOperation:
        raise ValueError(f"valor numerico invalido: {value!r}")


def _parse_timestamp(value):
    """ISO 8601 (com 'Z', offset ou sem) -> formato MySQL DATETIME(6) em UTC."""
    if value is None or value.strip() == "":
        raise ValueError("timestamp_leitura vazio")
    raw = value.strip().replace("Z", "+00:00")
    dt = datetime.fromisoformat(raw)
    if dt.tzinfo is not None:
        dt = dt.astimezone(timezone.utc).replace(tzinfo=None)
    return dt.strftime("%Y-%m-%d %H:%M:%S.%f")


def _get_or_create_missao(cur, codigo, cache):
    """Upsert idempotente da missao; retorna id_missao (com cache em memoria)."""
    if codigo in cache:
        return cache[codigo]
    cur.execute(
        "INSERT INTO missao (codigo_missao) VALUES (%s) "
        "ON DUPLICATE KEY UPDATE id_missao = LAST_INSERT_ID(id_missao)",
        (codigo,),
    )
    cur.execute("SELECT LAST_INSERT_ID()")
    id_missao = cur.fetchone()[0]
    cache[codigo] = id_missao
    return id_missao


def _inserir_lote(cur, lote):
    """INSERT IGNORE (idempotente). Retorna quantas linhas foram realmente inseridas."""
    cur.executemany(
        "INSERT IGNORE INTO telemetria "
        "(id_missao, timestamp_leitura, altitude_m, velocidade_ms, temperatura_c, "
        " pressao_pa, vibracao_g, combustivel_pct, latitude, longitude, status_sensor, arquivo_origem) "
        "VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)",
        lote,
    )
    return cur.rowcount or 0


def _registrar_log(cur, *, key, bucket, lidas, inseridas, erros, status, mensagem,
                   request_id, iniciado_em, finalizado_em):
    cur.execute(
        "INSERT INTO ingestao_log "
        "(nome_arquivo, bucket, qtd_linhas_lidas, qtd_linhas_inseridas, qtd_erros, "
        " status, mensagem, request_id, iniciado_em, finalizado_em) "
        "VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)",
        (key, bucket, lidas, inseridas, erros, status, mensagem, request_id,
         iniciado_em.strftime("%Y-%m-%d %H:%M:%S.%f"),
         finalizado_em.strftime("%Y-%m-%d %H:%M:%S.%f")),
    )


def _emitir_metricas(inseridas, erros, duracao_ms):
    """Publica metricas via EMF (Embedded Metric Format).

    A Lambda apenas imprime uma linha JSON no log; o CloudWatch detecta o bloco
    `_aws` e cria as metricas automaticamente -- SEM chamada de API, logo funciona
    de dentro da VPC sem NAT nem VPC endpoint pago.
    """
    emf = {
        "_aws": {
            "Timestamp": int(time.time() * 1000),
            "CloudWatchMetrics": [{
                "Namespace": CW_NAMESPACE,
                "Dimensions": [["Funcao"]],
                "Metrics": [
                    {"Name": "ArquivosProcessados", "Unit": "Count"},
                    {"Name": "LinhasInseridas", "Unit": "Count"},
                    {"Name": "LinhasComErro", "Unit": "Count"},
                    {"Name": "DuracaoMs", "Unit": "Milliseconds"},
                ],
            }],
        },
        "Funcao": "ingestao-telemetria",
        "ArquivosProcessados": 1,
        "LinhasInseridas": inseridas,
        "LinhasComErro": erros,
        "DuracaoMs": round(duracao_ms, 1),
    }
    print(json.dumps(emf))  # stdout -> CloudWatch Logs -> metricas via EMF


def _processar_objeto(bucket, key, request_id):
    """Le um CSV do S3 e grava no RDS. Retorna dict com o resumo."""
    t0 = time.time()
    iniciado_em = datetime.now(timezone.utc).replace(tzinfo=None)

    obj = s3.get_object(Bucket=bucket, Key=key)
    leitor = csv.DictReader(io.StringIO(obj["Body"].read().decode("utf-8-sig")))

    conn = _get_conn()
    try:
        with conn.cursor() as cur:
            # Cabecalho invalido -> falha controlada (auditada), sem reprocessar.
            faltando = [c for c in COLUNAS_OBRIGATORIAS if c not in (leitor.fieldnames or [])]
            if faltando:
                msg = f"colunas obrigatorias ausentes: {faltando}"
                _registrar_log(cur, key=key, bucket=bucket, lidas=0, inseridas=0, erros=0,
                               status="ERRO", mensagem=msg, request_id=request_id,
                               iniciado_em=iniciado_em, finalizado_em=datetime.now(timezone.utc).replace(tzinfo=None))
                conn.commit()
                _emitir_metricas(0, 0, (time.time() - t0) * 1000.0)
                resumo = {"evento": "ingestao_rejeitada", "arquivo": key, "status": "ERRO", "motivo": msg}
                logger.error(json.dumps(resumo))
                return resumo

            lidas = erros = inseridas = 0
            lote = []
            cache_missao = {}

            for linha in leitor:
                lidas += 1
                try:
                    codigo = (linha.get("codigo_missao") or "").strip()
                    if not codigo:
                        raise ValueError("codigo_missao vazio")
                    id_missao = _get_or_create_missao(cur, codigo, cache_missao)
                    registro = (
                        id_missao,
                        _parse_timestamp(linha.get("timestamp_leitura")),
                        *[_num(linha.get(c)) for c in COLUNAS_MEDIDAS],
                        (linha.get("status_sensor") or "").strip() or None,
                        key,
                    )
                    lote.append(registro)
                except Exception as e:  # linha invalida nao derruba o arquivo todo
                    erros += 1
                    logger.warning(json.dumps({
                        "evento": "linha_invalida", "arquivo": key, "linha": lidas, "erro": str(e),
                    }))
                    continue

                if len(lote) >= BATCH_SIZE:
                    inseridas += _inserir_lote(cur, lote)
                    lote.clear()

            if lote:
                inseridas += _inserir_lote(cur, lote)

            finalizado_em = datetime.now(timezone.utc).replace(tzinfo=None)
            status = "SUCESSO" if erros == 0 else ("ERRO" if inseridas == 0 else "PARCIAL")
            duplicadas = lidas - erros - inseridas
            _registrar_log(cur, key=key, bucket=bucket, lidas=lidas, inseridas=inseridas, erros=erros,
                           status=status,
                           mensagem=f"{inseridas} inseridas, {duplicadas} duplicadas ignoradas, {erros} erros",
                           request_id=request_id, iniciado_em=iniciado_em, finalizado_em=finalizado_em)
        conn.commit()
    except Exception:
        try:
            conn.rollback()
        except Exception:
            pass
        raise

    duracao_ms = (time.time() - t0) * 1000.0
    _emitir_metricas(inseridas, erros, duracao_ms)
    resumo = {
        "evento": "ingestao_concluida", "arquivo": key, "bucket": bucket,
        "linhas_lidas": lidas, "linhas_inseridas": inseridas, "duplicadas": duplicadas,
        "erros": erros, "status": status, "duracao_ms": round(duracao_ms, 1),
        "request_id": request_id,
    }
    logger.info(json.dumps(resumo))
    return resumo


def lambda_handler(event, context):
    """Entry point. Trata 1..N registros do evento S3."""
    request_id = getattr(context, "aws_request_id", "local")
    resultados = []
    for record in event.get("Records", []):
        bucket = record["s3"]["bucket"]["name"]
        key = unquote_plus(record["s3"]["object"]["key"])
        logger.info(json.dumps({"evento": "arquivo_recebido", "bucket": bucket, "arquivo": key}))
        resultados.append(_processar_objeto(bucket, key, request_id))

    return {"statusCode": 200, "body": json.dumps({"processados": resultados})}
