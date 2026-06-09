# Guia Definitivo — Execução no Console AWS (para a entrega)

Este é o **caminho recomendado para a entrega**: tudo pelo Console (sem instalar Terraform/CLI). Cada fase indica **o que fazer**, **onde** e **qual print salvar** em `evidencias/`.

> O `roteiro 02` tem uma variante com Lambda **dentro da VPC** (mais segura, mais passos). Aqui usamos o caminho **mais simples e confiável**: Lambda fora de VPC + RDS público. Funciona 100% para a tarefa; a única ressalva de segurança (porta 3306) está sinalizada na Fase 1 e é resolvida na limpeza.

**Regra de ouro:** faça **tudo na mesma região** — use **N. Virginia (us-east-1)**. Confira no canto superior direito do Console em cada serviço.

---

## Fase 0 — Preparação local (2 min)

1. **Lambda já empacotada:** o arquivo `lambda/build/ingest.zip` já existe (eu gerei). Se algum dia precisar refazer: `./build.ps1`.
2. **Descubra seu IP público:** abra <https://checkip.amazonaws.com> e anote (ex.: `200.1.2.3`). Você vai usar como `200.1.2.3/32`.
3. Tenha em mãos os arquivos `sql/schema.sql` e `data/telemetria_exemplo.csv`.

---

## Fase 1 — RDS MySQL (comece por aqui, leva ~10 min) 🟢 Evidência 01

Console → **RDS** → **Create database**:
- **Standard create** → **MySQL** → Engine version **8.0.x** → Template **Free tier**.
- **DB instance identifier:** `gs-cloud-mysql`
- **Master username:** `admin` · **Master password:** defina e **ANOTE**.
- **Instance:** `db.t3.micro` · **Storage:** 20 GB (desmarque o autoscaling).
- **Connectivity → Public access: `Yes`** · VPC: `default`.
  - **VPC security group:** *Create new* → nome `gs-cloud-rds-sg`.
- **Additional configuration → Initial database name:** `aeroespacial`
- **Create database** → aguarde o status **Available**.
- Clique na instância e **anote o Endpoint** (ex.: `gs-cloud-mysql.xxxx.us-east-1.rds.amazonaws.com`).

📸 **Evidência 01** → `evidencias/01-rds-criado.png` (tela do RDS com **Endpoint** e status **Available**).

### Ajustar o Security Group (liberar a porta 3306)
Console → **EC2** → **Security Groups** → `gs-cloud-rds-sg` → **Inbound rules** → **Edit inbound rules**:
- **Regra 1:** Type `MySQL/Aurora (3306)` · Source **My IP** (para o Workbench).
- **Regra 2:** Type `MySQL/Aurora (3306)` · Source `0.0.0.0/0` — **temporária**, para a Lambda (que está fora da VPC) conectar.
  > ⚠️ A regra 2 abre o banco à internet (protegido por senha). É aceitável para um trabalho curto **se você derrubar tudo no fim** (Fase 10). Não deixe ligado.
- **Save rules**.

---

## Fase 2 — Bucket S3 🟢 Evidência 02

Console → **S3** → **Create bucket**:
- **Bucket name:** `gs-cloud-aero-SEUNOME` (precisa ser único no mundo) · Region **us-east-1** · resto no padrão → **Create bucket**.

📸 **Evidência 02** → `evidencias/02-bucket-criado.png`.

---

## Fase 3 — Conectar o Workbench e criar as tabelas (RDS precisa estar *Available*) 🟢 Evidências 03 e 04

1. Abra o **MySQL Workbench** → **＋** (nova conexão):
   - **Hostname:** endpoint do RDS · **Port:** `3306` · **Username:** `admin` · **Password:** *Store in Vault* → a senha.
   - **Test Connection** → deve aparecer *Successfully made the MySQL connection*.
   📸 **Evidência 03** → `evidencias/03-workbench-conexao.png`.
2. Abra a conexão → **File → Open SQL Script** → `sql/schema.sql` → execute tudo (⚡ ícone do raio).
3. Clique em **Refresh** nos Schemas → abra `aeroespacial` → **Tables** (devem aparecer `missao`, `telemetria`, `ingestao_log`, `documento_rag`).
   📸 **Evidência 04** → `evidencias/04-schema-criado.png`.

---

## Fase 4 — Função Lambda 🟢 Evidências 05 e 06

Console → **Lambda** → **Create function**:
- **Author from scratch** · **Function name:** `gs-cloud-ingestao` · **Runtime: Python 3.12** · Architecture `x86_64` → **Create function**.

1. **Subir o código:** aba **Code** → **Upload from → .zip file** → selecione `lambda/build/ingest.zip` → **Save**.
2. **⚠️ Ajustar o handler (passo crítico):** **Runtime settings → Edit** → **Handler:** `handler.lambda_handler` → **Save**.
   *(O padrão vem `lambda_function.lambda_handler`; nosso arquivo é `handler.py`, então tem que trocar — senão dá erro de import.)*
   📸 **Evidência 05** → `evidencias/05-lambda-criada.png` (visão geral com Runtime e Handler).
3. **Configuration → General configuration → Edit:** Timeout **1 min 0 s** · Memory **256 MB** → **Save**.
4. **Configuration → Environment variables → Edit → Add** estas 6:

   | Key | Value |
   |---|---|
   | `DB_HOST` | endpoint do RDS |
   | `DB_PORT` | `3306` |
   | `DB_USER` | `admin` |
   | `DB_PASSWORD` | sua senha |
   | `DB_NAME` | `aeroespacial` |
   | `CW_NAMESPACE` | `GSCloud/Ingestao` |

   **Save**. 📸 **Evidência 06** → `evidencias/06-lambda-env.png` (**borre/oculte a senha** no print).
5. **Permissão de leitura no S3:** **Configuration → Permissions** → clique no nome da **Role** (abre o IAM) → **Add permissions → Attach policies** → busque **AmazonS3ReadOnlyAccess** → **Add permissions**.
   *(Os logs já funcionam pela `AWSLambdaBasicExecutionRole` que foi criada junto.)*

---

## Fase 5 — Gatilho do S3 🟢 Evidência 07

Lambda → **Function overview** → **Add trigger** → **S3**:
- **Bucket:** o da Fase 2 · **Event types:** *All object create events* · **Suffix:** `.csv`
- marque o aviso de **invocação recursiva** → **Add**.

📸 **Evidência 07** → `evidencias/07-lambda-trigger.png` (diagrama da Lambda com o S3 ligado).

---

## Fase 6 — Disparar a ingestão 🟢 Evidência 08

Console → **S3** → seu bucket → **Upload** → **Add files** → `data/telemetria_exemplo.csv` → **Upload**.
O upload dispara a Lambda **automaticamente**.

📸 **Evidência 08** → `evidencias/08-upload-csv.png` (objeto no bucket).

---

## Fase 7 — Evidências no CloudWatch 🟢 Evidências 09 e 10

1. **Logs:** Console → **CloudWatch** → **Log groups** → `/aws/lambda/gs-cloud-ingestao` → último **Log stream** → procure as linhas JSON `arquivo_recebido` e `ingestao_concluida` (mostram linhas inseridas e duração).
   📸 **Evidência 09** → `evidencias/09-cloudwatch-logs.png`.
2. **Métricas (EMF):** **CloudWatch → Metrics → All metrics → Custom namespaces → `GSCloud/Ingestao`** → `Funcao` → marque `LinhasInseridas`, `ArquivosProcessados`, `DuracaoMs` → veja o gráfico.
   *(Pode levar 1–2 min para aparecer após a 1ª execução.)*
   📸 **Evidência 10** → `evidencias/10-cloudwatch-metricas.png`.

---

## Fase 8 — Exploração dos dados no Workbench 🟢 Evidências 11, 12 e 13

Rode no Workbench (estão prontas em `sql/schema.sql`):

```sql
-- Evidência 11: trilha da automação
SELECT * FROM ingestao_log ORDER BY finalizado_em DESC;

-- Evidência 12: volume ingerido por missão
SELECT m.codigo_missao, COUNT(*) AS leituras,
       MIN(t.timestamp_leitura) AS inicio, MAX(t.timestamp_leitura) AS fim
FROM telemetria t JOIN missao m ON m.id_missao = t.id_missao
GROUP BY m.codigo_missao;

-- Evidência 13: exploração (picos e médias)
SELECT m.codigo_missao, MAX(t.altitude_m) AS altitude_max_m,
       AVG(t.velocidade_ms) AS vel_media_ms, MAX(t.temperatura_c) AS temp_max_c
FROM telemetria t JOIN missao m ON m.id_missao = t.id_missao
GROUP BY m.codigo_missao;
```
📸 `evidencias/11-ingestao-log.png` · `evidencias/12-telemetria-volume.png` · `evidencias/13-exploracao.png`.

---

## Fase 9 — (Opcional, recomendado) Erro tratado + idempotência 🟢 Evidências 14 e 15

- **Erro tratado:** suba `data/telemetria_com_erros.csv`. Depois rode a query da Evidência 11: a última linha terá **`status = PARCIAL`** e **`qtd_erros = 1`** (a linha com `SENSOR_FALHOU` foi rejeitada, o resto entrou).
  📸 `evidencias/14-erro-parcial.png`.
- **Idempotência:** suba o **mesmo** `telemetria_exemplo.csv` de novo. A nova linha em `ingestao_log` terá **`qtd_linhas_inseridas = 0`** (duplicadas ignoradas) e o `COUNT(*)` de `telemetria` não muda.
  📸 `evidencias/15-idempotencia.png`.

---

## Fase 10 — Limpeza (FAÇA depois de coletar todos os prints) ⚠️

Para **não gerar cobrança**, apague nesta ordem:
1. **Lambda** → Actions → Delete.
2. **RDS** → Modify (desmarque deletion protection se houver) → Delete → *skip final snapshot*.
3. **S3** → Empty bucket → Delete bucket.
4. **CloudWatch** → Log groups → delete `/aws/lambda/gs-cloud-ingestao`.
5. **EC2 → Security Groups** → delete `gs-cloud-rds-sg` (só depois que o RDS sumir).

---

## Checklist rápido

- [ ] 01 RDS Available + endpoint
- [ ] 02 Bucket criado
- [ ] 03 Workbench conectado
- [ ] 04 Tabelas criadas
- [ ] 05 Lambda criada (handler `handler.lambda_handler`)
- [ ] 06 Env vars (senha oculta)
- [ ] 07 Trigger S3
- [ ] 08 CSV no bucket
- [ ] 09 Logs CloudWatch
- [ ] 10 Métricas CloudWatch
- [ ] 11 ingestao_log
- [ ] 12 Volume por missão
- [ ] 13 Exploração
- [ ] 14 (opc.) Erro PARCIAL
- [ ] 15 (opc.) Idempotência
- [ ] Recursos derrubados (Fase 10)
