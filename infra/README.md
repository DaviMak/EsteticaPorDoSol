# Infraestrutura IaaS — Google Cloud

Provisionamento da aplicação em **máquinas virtuais com rede configurada à mão**:
VPC própria, subnet pública e privada, regras de firewall, NAT gateway e dois
servidores configurados manualmente.

É o caminho oposto ao do `DEPLOY.md`, que usa Cloud Run (serverless). Ali a
plataforma esconde a infraestrutura; aqui ela é o objeto do trabalho.

---

## Arquitetura

```
                        Internet
                           │  :80
    ┌──────────────────────┼────────────────────────────────┐
    │  VPC  estetica-vpc  (modo custom)                     │
    │                      ▼                                │
    │  ┌─────────────────────────────────────────┐          │
    │  │ subnet-publica          10.10.1.0/24    │          │
    │  │                                          │          │
    │  │   vm-app   e2-micro · IP externo         │          │
    │  │   Nginx :80  ──►  Kestrel 127.0.0.1:5000 │          │
    │  │   systemd mantém o processo no ar        │          │
    │  └────────────────────┬────────────────────┘          │
    │                       │  :3306                        │
    │  ┌────────────────────▼────────────────────┐          │
    │  │ subnet-privada          10.10.2.0/24    │          │
    │  │                                          │          │
    │  │   vm-db    e2-micro · SEM IP externo     │          │
    │  │   MySQL 8 instalado e configurado à mão  │          │
    │  └─────────────────────────────────────────┘          │
    │                                                        │
    │  Cloud Router + Cloud NAT  →  saída da subnet privada  │
    └────────────────────────────────────────────────────────┘
```

### Equivalência com a AWS

Se o enunciado do trabalho usa vocabulário da AWS:

| AWS | Google Cloud | Aqui |
|---|---|---|
| EC2 | Compute Engine | `vm-app`, `vm-db` |
| VPC | VPC | `estetica-vpc` |
| Subnet | Subnet | `subnet-publica`, `subnet-privada` |
| Security group | Firewall rule | `estetica-allow-*` |
| NAT Gateway | Cloud NAT | `estetica-nat` |
| Internet Gateway | implícito na VPC | — |
| ECS | não existe equivalente direto | app roda direto na VM |

### Regras de firewall

A VPC em modo *custom* **nega todo o tráfego de entrada por padrão**. Só o
necessário é aberto, e sempre mirando **tags** em vez de endereços IP:

| Regra | Origem | Destino | Portas |
|---|---|---|---|
| `estetica-allow-http` | `0.0.0.0/0` | tag `app` | 80, 443 |
| `estetica-allow-ssh-iap` | `35.235.240.0/20` | tags `app`, `db` | 22 |
| `estetica-allow-mysql` | tag `app` | tag `db` | 3306 |

Três decisões que valem explicar numa apresentação:

- **O banco não é alcançável da internet.** A `vm-db` não tem IP externo, e a
  porta 3306 só aceita origem com a tag `app` — nem outra VM da mesma subnet
  entra.
- **SSH nunca fica exposto.** `35.235.240.0/20` é a faixa fixa do
  Identity-Aware Proxy do Google. O acesso passa por ele, autenticado por IAM,
  e por isso funciona até na VM sem IP público.
- **O Cloud NAT existe por necessidade.** Sem IP externo, a `vm-db` não
  conseguiria baixar o MySQL pelo apt. O NAT dá saída sem dar entrada.

---

## Como executar

Duplo clique em **`infra.bat`**, ou pelo terminal:

```powershell
.\infra.ps1                 # provisiona tudo (leva de 10 a 20 minutos)
.\infra.ps1 -SomenteApp     # só reenvia o código e republica
.\infra.ps1 -Destruir       # apaga a infraestrutura
```

Pré-requisitos: `gcloud` instalado e autenticado (`gcloud auth login`), e um
projeto GCP com billing ativo. **Não** é necessário ter .NET SDK nem Docker na
máquina local — a compilação acontece dentro da `vm-app`.

O script é idempotente: rodar de novo preserva o que já existe.

### Arquivos

| Arquivo | Papel |
|---|---|
| `infra.ps1` | Orquestrador: cria rede e VMs, envia o código, publica e valida |
| `infra.bat` | Lançador de duplo clique (contorna a ExecutionPolicy) |
| `vm-db-startup.sh` | Roda na `vm-db` no primeiro boot: instala e configura o MySQL |
| `vm-app-startup.sh` | Roda na `vm-app` no primeiro boot: .NET, Nginx e systemd |

Os dois `.sh` são *startup scripts* do Compute Engine — o próprio Google os
executa como root na primeira inicialização da VM. Ambos são idempotentes por
arquivo marcador, porque o startup script roda **a cada boot**, não só no
primeiro.

---

## Configuração do servidor

### `vm-app` — camada de aplicação

- **.NET 10 SDK** instalado pelo script oficial da Microsoft, não pelo apt: os
  repositórios do Ubuntu ficam versões atrás e o projeto exige `net10.0`.
- **Kestrel** escuta apenas em `127.0.0.1:5000` — nunca fica exposto.
- **Nginx** atende a porta 80 e repassa para o Kestrel, encaminhando
  `X-Forwarded-For` e `X-Forwarded-Proto`.
- **systemd** (`estetica.service`) reinicia a aplicação em caso de falha e
  religa no boot. Roda com um usuário de serviço sem shell.
- Segredos ficam em `/etc/estetica.env`, modo `600` — fora da unidade systemd,
  cujo conteúdo é legível por qualquer usuário.

### `vm-db` — camada de dados

- **MySQL 8** via apt, com `bind-address = 0.0.0.0` para aceitar a subnet
  pública. A proteção fica na regra de firewall, não no bind.
- O usuário da aplicação é criado como `estetica_app@'10.10.1.%'` — restrito à
  faixa da subnet pública. *(MySQL não aceita CIDR aqui: `10.10.1.0/24` é
  inválido, o formato é o curinga.)*
- `innodb_buffer_pool_size` reduzido para caber em 1 GB de RAM.

### Swap nas duas VMs

A `e2-micro` tem **1 GB de RAM**. Sem um swapfile de 2 GB, o MySQL é morto pelo
OOM killer na inicialização e o `dotnet publish` morre no meio da compilação.
Ambos os startup scripts criam o swap antes de instalar qualquer coisa.

---

## Custo

As duas VMs somam algo em torno de **R$ 60 a 100/mês** ligadas 24 horas. VM
parada cobra apenas o disco (poucos reais).

```powershell
# pausar sem apagar nada
gcloud compute instances stop vm-app vm-db --zone=southamerica-east1-a --project=estetica-por-do-sol

# religar
gcloud compute instances start vm-app vm-db --zone=southamerica-east1-a --project=estetica-por-do-sol
```

---

## Diagnóstico

Todo acesso SSH passa pelo IAP — inclusive na VM sem IP externo:

```powershell
# logs do provisionamento inicial
gcloud compute ssh vm-app --zone=southamerica-east1-a --tunnel-through-iap `
  --command="sudo journalctl -u google-startup-scripts -n 60"

# logs da aplicação
gcloud compute ssh vm-app --zone=southamerica-east1-a --tunnel-through-iap `
  --command="sudo journalctl -u estetica -n 60"

# testar a conexão com o banco a partir da vm-app
gcloud compute ssh vm-app --zone=southamerica-east1-a --tunnel-through-iap `
  --command="sudo apt-get install -y mysql-client && mysql -h <IP-INTERNO-DB> -u estetica_app -p"
```

| Sintoma | Causa provável |
|---|---|
| `502 Bad Gateway` no Nginx | A aplicação não subiu — veja `journalctl -u estetica` |
| App sobe e cai em loop | Migration falhando ou banco inacessível |
| `Access denied for user` | Senha divergente entre `/etc/estetica.env` e o MySQL |
| Timeout ao conectar no banco | Falta a tag `app` na VM, ou a regra `estetica-allow-mysql` |
| Startup script não termina | Sem Cloud NAT a `vm-db` não baixa pacotes e trava no apt |
| `bash: \r: command not found` | Script `.sh` salvo com CRLF — precisa ser LF |

---

## Diferenças em relação ao deploy no Cloud Run

O mesmo código roda nas duas arquiteturas, com uma diferença de configuração:

| | Cloud Run | VM + Nginx |
|---|---|---|
| TLS | termina no proxy do Google | não configurado (só HTTP:80) |
| `UseHttpsRedirection` | **ligado** | **desligado** via `UseHttpsRedirection=false` |
| `UseForwardedHeaders` | necessário | necessário |
| Migrations | no startup | no startup |

O interruptor existe porque, atrás do Nginx servindo apenas HTTP, o
redirecionamento mandaria o navegador para uma porta 443 que ninguém escuta.
Para habilitar HTTPS de verdade seria preciso um domínio e um certificado
(Let's Encrypt via certbot no Nginx).
