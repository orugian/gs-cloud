# GS-Cloud — Ingestão Automatizada de Telemetria Aeroespacial

Solução **serverless** na AWS que ingere arquivos de telemetria aeroespacial de um **bucket S3** para uma **base relacional (RDS MySQL)** de forma **automática**, evidencia a automação no **CloudWatch** e permite **explorar os dados** no **MySQL Workbench**. A base já é modelada preparada para um **RAG** futuro.

> **Matéria:** Plataformas, Serviços Cognitivos & Cloud Computing — **Tema:** API na nuvem com RAG

## Arquitetura (resumo)

```
upload .csv ─► S3 (bucket raw) ─►(evento ObjectCreated)─► Lambda (Python)
                                                              │
                                       INSERT (pymysql) ──────┼────► RDS MySQL
                                       logs + métricas ───────┘        │
                                              ▼                        │
                                        CloudWatch              MySQL Workbench
```

Detalhes, decisões e diagrama completo em **[docs/01-design.md](docs/01-design.md)**.

## Estrutura

| Caminho | O quê |
|---|---|
| `docs/01-design.md` | Documento de planejamento e arquitetura (entregável principal) |
| `docs/02-roteiro-execucao.md` | Roteiro técnico (Terraform **ou** Console) + coleta de evidências |
| **`docs/03-guia-aws-console.md`** | **Guia definitivo de execução no Console (para a entrega)** |
| **`docs/04-relatorio-modelo.md`** | **Modelo de relatório (preencher → exportar PDF)** |
| **`evidencias/`** | **Onde salvar os prints (nomes já definidos)** |
| `sql/schema.sql` | DDL do RDS + consultas de exploração |
| `lambda/ingest/handler.py` | Função Lambda de ingestão |
| `lambda/build/ingest.zip` | Lambda já empacotada (pronta p/ upload no Console) |
| `infra/terraform/` | Infra como código (VPC, S3, RDS, Lambda, IAM, CloudWatch) |
| `data/*.csv` | Arquivos de teste (feliz + com erro) |
| `build.ps1` / `build.sh` | Empacota a Lambda (handler + pymysql) |

## Entrega (Console AWS)

Siga **[docs/03-guia-aws-console.md](docs/03-guia-aws-console.md)** → salve os prints em `evidencias/` → preencha **[docs/04-relatorio-modelo.md](docs/04-relatorio-modelo.md)** e exporte em PDF.

## Começar rápido (Terraform)

```powershell
./build.ps1
cd infra/terraform
Copy-Item terraform.tfvars.example terraform.tfvars   # preencha bucket/senha/IP
terraform init
terraform apply
# rode sql/schema.sql no Workbench, depois:
aws s3 cp ../../data/telemetria_exemplo.csv s3://<bucket_nome>/incoming/exemplo.csv
```

Passo a passo completo e como coletar as evidências: **[docs/02-roteiro-execucao.md](docs/02-roteiro-execucao.md)**.

## Stack

S3 · Lambda (Python 3.12, PyMySQL) · RDS MySQL 8 · CloudWatch (logs/métricas EMF/alarme/dashboard) · SQS (DLQ) · VPC + S3 Gateway Endpoint · IAM · Terraform

> 💸 Lembre de rodar `terraform destroy` ao terminar para não sair do Free Tier.
