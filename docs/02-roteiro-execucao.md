# Roteiro de Execução e Coleta de Evidências

Dois caminhos para subir a solução: **A) Terraform** (reproduzível) ou **B) Console AWS** (manual, bom para os prints). Os dois usam o **mesmo** `handler.py` e o **mesmo** `schema.sql`. No fim, a seção **C) Evidências** lista o que coletar.

> ⚠️ **Custos:** tudo cabe no Free Tier, mas **derrube os recursos ao terminar** (passo final) para não gerar cobrança.

---

## Pré-requisitos

- Conta AWS com permissão de admin (ou equivalente).
- **MySQL Workbench** instalado.
- Para o caminho A: **Terraform >= 1.5**, **AWS CLI** configurada (`aws configure`) e **Python 3.12 + pip**.
- Descubra seu IP público (para liberar o Workbench): acesse <https://checkip.amazonaws.com>.

---

## A) Caminho Terraform (recomendado)

```powershell
# 1. Empacotar a Lambda (gera lambda/build/ingest.zip)
./build.ps1            # no Windows
# ./build.sh           # no Linux/Mac

# 2. Configurar variáveis
cd infra/terraform
Copy-Item terraform.tfvars.example terraform.tfvars
#   edite terraform.tfvars: bucket_name, db_password, my_ip_cidr

# 3. Provisionar (RDS leva ~10 min)
terraform init
terraform apply        # confirme com "yes"
```

Ao final, o Terraform imprime `bucket_nome`, `rds_endpoint`, `lambda_nome` e `log_group`. Anote.

**Criar as tabelas:** conecte o Workbench no `rds_endpoint` (ver seção C) e rode todo o [`sql/schema.sql`](../sql/schema.sql).

**Disparar a ingestão:**
```powershell
aws s3 cp ../../data/telemetria_exemplo.csv s3://<bucket_nome>/incoming/telemetria_exemplo.csv
```
O upload dispara a Lambda automaticamente. Pule para a seção **C) Evidências**.

---

## B) Caminho Console AWS (manual)

### B.1 — Criar o bucket S3
S3 → **Create bucket** → nome único (ex.: `gs-cloud-aero-seunome`) → região `us-east-1` → **Create**.

### B.2 — Criar o RDS MySQL
RDS → **Create database** → **Standard create** → **MySQL** → template **Free tier** →
- DB instance identifier: `gs-cloud-mysql`
- Master username: `admin` / defina a senha
- Instance: `db.t3.micro`; Storage: 20 GB
- **Connectivity → Public access: Yes**
- VPC security group: crie/edite para liberar a porta **3306** ao **seu IP** (e depois ao SG da Lambda)
- Additional config → **Initial database name: `aeroespacial`**
→ **Create database** (leva ~10 min). Anote o **Endpoint**.

Conecte o Workbench (seção C) e rode o [`sql/schema.sql`](../sql/schema.sql).

### B.3 — Criar a função Lambda
Lambda → **Create function** → **Author from scratch** →
- Nome: `gs-cloud-ingestao`; Runtime: **Python 3.12**
- Após criar: **Upload from → .zip file** → suba o `lambda/build/ingest.zip` (rode `./build.ps1` antes)
- **Configuration → General**: Timeout **60s**, Memory **256 MB**
- **Configuration → Environment variables**: `DB_HOST`, `DB_PORT=3306`, `DB_USER`, `DB_PASSWORD`, `DB_NAME=aeroespacial`, `CW_NAMESPACE=GSCloud/Ingestao`
- **Configuration → VPC**: selecione a VPC/subnets do RDS e um SG que alcance o RDS (e ajuste o SG do RDS para aceitar o SG da Lambda na 3306)
- **Configuration → Permissions** (role da Lambda): adicione permissão `s3:GetObject` no bucket e a managed policy **AWSLambdaVPCAccessExecutionRole** (métricas saem via EMF, não precisa de `cloudwatch:PutMetricData`). Se for usar a DLQ opcional, adicione também `sqs:SendMessage` na fila.

### B.4 — Ligar o gatilho do S3
Na Lambda → **Add trigger** → **S3** → bucket do passo B.1 → event type **All object create events** → suffix **`.csv`** → **Add**.

### B.5 — Disparar
S3 → bucket → **Upload** → envie `data/telemetria_exemplo.csv`. A Lambda roda automaticamente.

### B.6 — Extras opcionais (o Terraform já cria; no manual são opcionais)
- **DLQ:** SQS → crie a fila `gs-cloud-ingestao-dlq` → na Lambda, **Configuration → Asynchronous invocation → DLQ**, aponte para a fila (a role precisa de `sqs:SendMessage`).
- **Dashboard:** CloudWatch → Dashboards → **Create** → adicione widgets das métricas `GSCloud/Ingestao` e de `AWS/Lambda` (Invocations/Errors).

---

## C) Conectar o MySQL Workbench ao RDS

1. Workbench → **+** (nova conexão MySQL).
2. **Hostname:** o endpoint do RDS · **Port:** 3306 · **Username:** `admin` · **Password:** (a definida).
3. **Test Connection** → deve conectar (se falhar, revise o Security Group / seu IP).
4. Rode o `schema.sql` (uma vez) e depois as consultas de exploração.

---

## D) Evidências para o relatório (prints)

Colete, na ordem, para comprovar a **automação** e a **exploração**:

| # | Evidência | Onde | O que mostra |
|---|---|---|---|
| 1 | Arquivo no bucket | S3 → objeto `incoming/telemetria_exemplo.csv` | Ingestão no S3 |
| 2 | **Invocação da Lambda** | CloudWatch → Log groups → `/aws/lambda/gs-cloud-ingestao` → último stream | Automação disparou sozinha |
| 3 | **Logs estruturados** | mesmo log: linhas `arquivo_recebido` e `ingestao_concluida` (JSON com linhas inseridas e duração) | A Lambda leu o S3 e gravou no RDS |
| 4 | **Métricas** | CloudWatch → Metrics → `GSCloud/Ingestao` → `LinhasInseridas`, `ArquivosProcessados`, `DuracaoMs` | Telemetria da automação |
| 5 | **Dashboard** | CloudWatch → Dashboards → `gs-cloud-ingestao` | Tudo em um print |
| 6 | Alarme | CloudWatch → Alarms → `gs-cloud-erros-ingestao` | Tratamento de falhas |
| 7 | **Trilha no banco** | Workbench: `SELECT * FROM ingestao_log ORDER BY finalizado_em DESC;` | Auditoria da ingestão |
| 8 | **Dados gravados** | Workbench: `SELECT COUNT(*) FROM telemetria;` e o `SELECT` de volume por missão | RDS populado automaticamente |
| 9 | **Exploração** | Workbench: consultas de picos/médias do `schema.sql` | Análise dos dados |

### Evidências opcionais (deixam o relatório mais forte)

- **Tratamento de erro (`PARCIAL`):** suba `data/telemetria_com_erros.csv`. A linha com `altitude_m = SENSOR_FALHOU` é rejeitada; em `ingestao_log` o `status` fica `PARCIAL` com `qtd_erros = 1`, e o alarme dispara.
- **Idempotência:** suba o **mesmo** `telemetria_exemplo.csv` de novo. A nova linha em `ingestao_log` mostra `qtd_linhas_inseridas = 0` (duplicadas ignoradas) — `SELECT COUNT(*) FROM telemetria` não muda.
- **DLQ:** SQS → fila `gs-cloud-ingestao-dlq` permanece vazia no caminho feliz (prova que nada se perdeu).

---

## E) Limpeza (evita cobrança)

```powershell
# Caminho Terraform
cd infra/terraform
terraform destroy      # confirme com "yes"
```
No caminho manual: apague nesta ordem → trigger/Lambda → RDS (sem snapshot final) → objetos e bucket S3 → log group, dashboard e alarme do CloudWatch → fila SQS (DLQ).

---

## Troubleshooting rápido

| Sintoma | Causa provável | Ação |
|---|---|---|
| Workbench não conecta | SG do RDS não libera seu IP, ou `Public access = No` | Ajuste o SG (porta 3306 ao seu IP) e o flag de acesso público |
| Lambda dá timeout | Não alcança o RDS (VPC/SG) | Lambda e RDS na mesma VPC; SG do RDS aceitando o SG da Lambda |
| Lambda: `Access Denied` no S3 | Role sem `s3:GetObject` | Adicione a permissão no bucket |
| `terraform apply` falha no `filebase64sha256` | Zip não existe | Rode `./build.ps1` (ou `./build.sh`) antes do apply |
| Lambda na VPC não lê o S3 | Falta o Gateway Endpoint do S3 | O Terraform já cria; no manual, crie o VPC Endpoint do S3 |
