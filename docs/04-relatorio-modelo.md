# Relatório — Ingestão Automatizada na Nuvem (Telemetria Aeroespacial)

> Preencha os campos `[...]`, cole os prints na pasta `evidencias/` com os nomes indicados e exporte este arquivo para **PDF**.

**Matéria:** Plataformas, Serviços Cognitivos & Cloud Computing
**Tema:** API na nuvem com RAG
**Aluno(a):** [seu nome / RM]
**Data:** [data]
**Repositório:** [link do GitHub]

---

## 1. Objetivo

Solução **serverless** que ingere arquivos de telemetria aeroespacial enviados a um **bucket S3** e, de forma **automática**, grava os dados em uma base relacional **RDS MySQL**, com a automação evidenciada no **CloudWatch** e os dados explorados via **MySQL Workbench**. (Detalhamento em `docs/01-design.md`.)

## 2. Arquitetura

```
upload .csv ─► S3 (bucket) ─►(evento ObjectCreated)─► Lambda (Python) ─► RDS MySQL
                                          │                                   │
                                     CloudWatch (logs + métricas)        MySQL Workbench
```

A Lambda valida cada linha, resolve a missão, insere a telemetria em lote (idempotente) e registra a execução na tabela de auditoria `ingestao_log`.

## 3. Serviços AWS utilizados

| Serviço | Papel |
|---|---|
| Amazon S3 | Recebe os arquivos `.csv` (landing zone) |
| AWS Lambda (Python 3.12) | Ingestão serverless: lê o S3 e grava no RDS |
| Amazon RDS (MySQL 8) | Base relacional de destino |
| Amazon CloudWatch | Logs + métricas (EMF) = evidência da automação |
| IAM | Permissões mínimas da função |

## 4. Execução e evidências

**4.1 RDS provisionado**
![Evidência 01](../evidencias/01-rds-criado.png)

**4.2 Bucket S3**
![Evidência 02](../evidencias/02-bucket-criado.png)

**4.3 Conexão ao banco e criação do schema**
![Evidência 03](../evidencias/03-workbench-conexao.png)
![Evidência 04](../evidencias/04-schema-criado.png)

**4.4 Função Lambda**
![Evidência 05](../evidencias/05-lambda-criada.png)
![Evidência 06](../evidencias/06-lambda-env.png)

**4.5 Gatilho automático (S3 → Lambda)**
![Evidência 07](../evidencias/07-lambda-trigger.png)

**4.6 Ingestão disparada pelo upload**
![Evidência 08](../evidencias/08-upload-csv.png)

## 5. Automação evidenciada (CloudWatch)

**5.1 Logs da execução automática**
![Evidência 09](../evidencias/09-cloudwatch-logs.png)

**5.2 Métricas da ingestão**
![Evidência 10](../evidencias/10-cloudwatch-metricas.png)

> A automação dispara sem intervenção: o evento `ObjectCreated` do S3 invoca a Lambda, que processa e grava no RDS. Os logs e métricas acima comprovam a execução.

## 6. Exploração dos dados (MySQL Workbench → RDS)

**6.1 Trilha de auditoria da ingestão**
![Evidência 11](../evidencias/11-ingestao-log.png)

**6.2 Volume ingerido por missão**
![Evidência 12](../evidencias/12-telemetria-volume.png)

**6.3 Análise (picos e médias)**
![Evidência 13](../evidencias/13-exploracao.png)

## 7. (Opcional) Robustez

**7.1 Tratamento de erro (status PARCIAL)**
![Evidência 14](../evidencias/14-erro-parcial.png)

**7.2 Idempotência (reprocessamento sem duplicar)**
![Evidência 15](../evidencias/15-idempotencia.png)

## 8. Conclusão

[2–4 linhas: o que foi demonstrado — armazenamento na nuvem, ingestão automática serverless, evidência no CloudWatch e exploração no Workbench — e como a base já está preparada para a etapa de RAG.]

## 9. Preparação para RAG (trabalho futuro)

A modelagem já contempla `missao.descricao` (texto) e a tabela `documento_rag` (conteúdo + metadados + embedding), permitindo, numa próxima etapa, gerar embeddings e expor uma API de perguntas (RAG) sobre os dados ingeridos.
