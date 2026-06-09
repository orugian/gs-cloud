# Evidências (prints)

Salve aqui os prints da execução, **com exatamente estes nomes** (o modelo de relatório
`docs/04-relatorio-modelo.md` já os referencia). Formato: `.png` (ou `.jpg`).

| Arquivo | O que capturar | Fase do guia |
|---|---|---|
| `01-rds-criado.png` | RDS com **Endpoint** e status **Available** | 1 |
| `02-bucket-criado.png` | Bucket S3 criado | 2 |
| `03-workbench-conexao.png` | Workbench: *Successfully made the MySQL connection* | 3 |
| `04-schema-criado.png` | Schema `aeroespacial` com as 4 tabelas | 3 |
| `05-lambda-criada.png` | Lambda criada (Runtime Python 3.12, Handler `handler.lambda_handler`) | 4 |
| `06-lambda-env.png` | Variáveis de ambiente (**borre a senha**) | 4 |
| `07-lambda-trigger.png` | Diagrama da Lambda com o gatilho S3 | 5 |
| `08-upload-csv.png` | Objeto `.csv` dentro do bucket | 6 |
| `09-cloudwatch-logs.png` | Log stream com `arquivo_recebido` / `ingestao_concluida` | 7 |
| `10-cloudwatch-metricas.png` | Métricas `GSCloud/Ingestao` (LinhasInseridas etc.) | 7 |
| `11-ingestao-log.png` | `SELECT * FROM ingestao_log` no Workbench | 8 |
| `12-telemetria-volume.png` | Volume por missão (JOIN + GROUP BY) | 8 |
| `13-exploracao.png` | Query de picos/médias | 8 |
| `14-erro-parcial.png` | *(opcional)* `ingestao_log` com `status=PARCIAL` | 9 |
| `15-idempotencia.png` | *(opcional)* reupload com `qtd_linhas_inseridas=0` | 9 |

> Dica: padronize a janela e use o nome exato — assim o relatório fica montado sozinho.
