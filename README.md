# Estética Pôr do Sol — Kubernetes com Minikube

Sistema de gestão para lava car/estética automotiva rodando em um cluster Kubernetes local com Minikube.

---

## Pré-requisitos

Antes de começar, certifique-se de ter instalado:

- [Docker Desktop](https://www.docker.com/products/docker-desktop)
- [Minikube](https://minikube.sigs.k8s.io/docs/start/)
- [kubectl](https://kubernetes.io/docs/tasks/tools/)
- [.NET 10 SDK](https://dotnet.microsoft.com/download) *(apenas para rodar migrations pois o sistema é feito em C#)*

---

## Arquitetura

O projeto é composto por dois componentes rodando no cluster:

|        Componente      |        Imagem       | Réplicas | Porta |
|------------------------|---------------------|----------|-------|
| Aplicação ASP.NET Core | esteticapordosol:v1 |     2    |  8080 |
| Banco de dados MySQL   |      mysql:8.0      |     1    |  3306 |

A comunicação entre a aplicação e o banco é feita internamente pelo serviço `db` do Kubernetes, sem expor o banco externamente.

---

## Passo a passo

### 1. Clonar o repositório

```bash
git clone https://github.com/DaviMak/EsteticaPorDoSol.git
cd EsteticaPorDoSol
```

### 2. Iniciar o Minikube

Comandos executados pelo terminal do VS Code (utilizando o PowerShell):

```bash
minikube start
```

### 3. Configurar o Docker para usar o ambiente do Minikube

Este comando é obrigatório — sem ele o Minikube não encontra a imagem local da aplicação. Execute-o **uma vez por sessão de terminal**: caso feche o terminal e abra um novo, será necessário rodá-lo novamente antes de executar qualquer `docker build`.

```bash
minikube docker-env | Invoke-Expression
```

### 4. Build da imagem Docker da aplicação

Este processo porde demorar alguns minutos na primeira vez que for usado

```bash
docker build -t esteticapordosol:v1 .
```

### 5. Aplicar os manifestos Kubernetes

Para aplicar toda a infraestrutura declarativa de uma única vez (o Kubernetes gerencia a ordem correta de inicialização dos recursos automaticamente), execute:

```bash
kubectl apply -f k8s/
```

*(Caso prefira aplicar os arquivos individualmente seguindo a ordem de dependências, execute o bloco abaixo):*

```bash
kubectl apply -f k8s/secret.yaml
kubectl apply -f k8s/configmap.yaml
kubectl apply -f k8s/pvc-mysql.yaml
kubectl apply -f k8s/deployment-mysql.yaml
kubectl apply -f k8s/service-mysql.yaml
kubectl apply -f k8s/deployment-app.yaml
kubectl apply -f k8s/service-app.yaml
```

### 6. Aguardar os pods ficarem prontos

```bash
kubectl get pods -o wide
```

Aguarde até todos os pods estarem com status `Running`. Pode levar alguns minutos na primeira execução pois o MySQL precisa inicializar.

### 7. Rodar as migrations do banco de dados

Este passo só é necessário **uma única vez** na primeira execução. O projeto utiliza um **PersistentVolumeClaim** (`mysql-pvc`) que garante que os dados do banco sobrevivem mesmo que o pod do MySQL seja deletado ou reiniciado — ao contrário de um container sem volume, onde os dados seriam perdidos a cada reinício.

Caso ainda não tenha a ferramenta do Entity Framework instalada, execute:

```powershell
dotnet tool install --global dotnet-ef
```

Abra **dois terminais**:

**Terminal 1 — Port-forward:**
```bash
kubectl port-forward service/db 3307:3306
```

**Terminal 2 — Migrations (Executar obrigatoriamente no PowerShell):**
```powershell
$env:DB_CONNECTION_STRING="server=localhost;port=3307;database=DbEsteticaPorDoSol;user=root;password=senha123;"
dotnet ef database update
```

Após as migrations, pode fechar o Terminal 1. A partir daqui, mesmo deletando pods, os dados continuarão persistidos.

### 8. Acessar a aplicação

```bash
minikube service estetica-app-service
```

O navegador abrirá automaticamente com a aplicação rodando.

**Credenciais de acesso:**
- Usuário: `kelvin`
- Senha: `12345`

---

## Verificando o cluster

### Listar todos os pods
```bash
kubectl get pods -o wide
```

### Listar os services
```bash
kubectl get services
```

### Listar os deployments
```bash
kubectl get deployments
```

---

## Demonstrando a recriação automática de pods

O Kubernetes recria automaticamente qualquer pod que for deletado. Para demonstrar:

```bash
# Deletar um pod
kubectl delete pod <nome-do-pod>

# Verificar imediatamente — o Kubernetes recria em segundos
kubectl get pods -o wide
```

---

## Estrutura dos arquivos Kubernetes

```
k8s/
├── secret.yaml           # Senha do banco em base64
├── configmap.yaml        # Nome do banco de dados
├── pvc-mysql.yaml        # PersistentVolumeClaim para persistência dos dados
├── deployment-mysql.yaml # Deploy do MySQL com 1 réplica
├── service-mysql.yaml    # Serviço interno do banco (ClusterIP)
├── deployment-app.yaml   # Deploy da aplicação com 2 réplicas
└── service-app.yaml      # Serviço externo da aplicação (LoadBalancer)
```

---

## Integrantes

| Davi Mak
| Pedro Soares
| Joãozin