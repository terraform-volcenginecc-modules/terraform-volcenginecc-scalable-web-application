# 高可用三层 Web 应用 Terraform 方案

本工程基于 `volcenginecc` Provider，在火山引擎上部署一套高可用、可扩展的三层 Web 应用基础设施，覆盖网络、计算、负载均衡、数据库和对象存储等核心资源。

## 1. 业务背景

企业 Web 应用在生产环境落地时，通常会遇到以下问题：

- **部署链路长**：VPC、子网、安全组、ECS、负载均衡、数据库、对象存储等资源需要跨多个控制台手工配置，容易遗漏步骤。
- **环境一致性差**：测试、预发、生产环境如果依赖人工搭建，参数和拓扑容易不一致，后续排障成本高。
- **高可用要求高**：公网入口、应用服务器和数据库都需要具备跨可用区容灾能力，避免单点故障影响业务访问。
- **安全边界复杂**：互联网入口、Web 层、App 层和数据层访问路径不同，需要通过安全组、私网负载均衡和 RDS 白名单进行隔离。
- **扩展和回收成本高**：业务高峰期需要快速扩容，验证结束后也需要可靠销毁资源，降低闲置成本。

本方案通过 Terraform 将上述基础设施标准化、模块化，帮助用户快速完成三层 Web 应用的基础环境交付。

## 2. 方案概述

整体采用经典三层架构：

- **接入层**：公网 NLB 承接互联网流量，并转发到 Web 层 ECS。
- **Web 层**：多台 Web ECS 跨可用区部署，处理前端访问请求。
- **内部分发层**：私网 NLB 在 VPC 内部将 Web 层请求分发到 App 层。
- **App 层**：多台 App ECS 跨可用区部署，处理核心业务逻辑。
- **数据层**：RDS MySQL 主备实例承载结构化数据，TOS Bucket 存储非结构化数据。
- **安全控制**：统一安全组控制 ECS 入站访问，RDS 白名单默认放行 VPC 网段。

```mermaid
flowchart LR
    classDef user fill:#FFF7E6,stroke:#FA8C16,color:#873800,stroke-width:1px;
    classDef network fill:#E6F4FF,stroke:#1677FF,color:#003A8C,stroke-width:1px;
    classDef compute fill:#F6FFED,stroke:#52C41A,color:#135200,stroke-width:1px;
    classDef lb fill:#F9F0FF,stroke:#722ED1,color:#22075E,stroke-width:1px;
    classDef data fill:#FFF1F0,stroke:#F5222D,color:#820014,stroke-width:1px;
    classDef note fill:#F5F5F5,stroke:#8C8C8C,color:#262626,stroke-dasharray: 4 3;

    Client["互联网用户<br/>Browser / API Client"]:::user

    subgraph VPC["火山引擎 VPC<br/>10.1.0.0/16"]
        direction LR

        subgraph Net["网络与安全"]
            direction TB
            SG["Security Group<br/>SSH / Web / App 端口"]:::network
            SubnetA["Subnet A<br/>cn-beijing-a<br/>10.1.2.0/24"]:::network
            SubnetB["Subnet B<br/>cn-beijing-b<br/>10.1.3.0/24"]:::network
        end

        subgraph Ingress["接入层"]
            direction TB
            PublicNLB["公网 NLB<br/>TCP :80<br/>Cross-Zone Enabled"]:::lb
        end

        subgraph WebTier["Web 层"]
            direction TB
            WebA["Web ECS 01<br/>AZ A"]:::compute
            WebB["Web ECS 02<br/>AZ B"]:::compute
        end

        subgraph InternalLB["内部分发层"]
            direction TB
            PrivateNLB["私网 NLB<br/>TCP :8080<br/>VPC 内访问"]:::lb
        end

        subgraph AppTier["App 层"]
            direction TB
            AppA["App ECS 01<br/>AZ A"]:::compute
            AppB["App ECS 02<br/>AZ B"]:::compute
        end

        subgraph Database["数据库层"]
            direction TB
            RDS["RDS MySQL<br/>DoubleNode 主备"]:::data
            DB["业务数据库<br/>tf_db"]:::data
            AllowList["RDS Allow List<br/>放行 VPC CIDR"]:::data
        end
    end

    TOS["TOS Bucket<br/>对象 / 图片 / 日志"]:::data

    Client --> PublicNLB
    PublicNLB --> WebA
    PublicNLB --> WebB
    WebA --> PrivateNLB
    WebB --> PrivateNLB
    PrivateNLB --> AppA
    PrivateNLB --> AppB
    AppA --> RDS
    AppB --> RDS
    RDS --> DB
    AllowList -.-> RDS
    AppA --> TOS
    AppB --> TOS

    SG -.-> WebA
    SG -.-> WebB
    SG -.-> AppA
    SG -.-> AppB

    SubnetA -.-> WebA
    SubnetA -.-> AppA
    SubnetB -.-> WebB
    SubnetB -.-> AppB

    PublicNLB -.-> N1["公网入口<br/>健康检查 / 跨 AZ 转发"]:::note
    PrivateNLB -.-> N2["内部调用<br/>Web 到 App 解耦"]:::note
    RDS -.-> N3["主备容灾<br/>结构化数据持久化"]:::note
    TOS -.-> N4["弹性存储<br/>非结构化数据"]:::note
```

## 3. IaC 设计

### 3.1 资源清单

本工程默认开启全部模块时，会创建以下资源：

| Terraform 资源 | 用途 |
| --- | --- |
| `volcenginecc_vpc_vpc` | 创建业务 VPC，提供隔离的网络空间 |
| `volcenginecc_vpc_subnet` ×2 | 创建跨可用区子网，承载 ECS、NLB 和 RDS |
| `volcenginecc_vpc_security_group` | 创建统一安全组，控制 SSH、Web 和 App 端口访问 |
| `volcenginecc_ecs_instance` (Web) ×2 | 创建 Web 层 ECS，接收公网 NLB 转发的流量 |
| `volcenginecc_ecs_instance` (App) ×2 | 创建 App 层 ECS，处理业务逻辑并访问数据层 |
| `volcenginecc_clb_nlb` (internet) | 创建公网 NLB，作为互联网访问入口 |
| `volcenginecc_clb_nlb_server_group` (web) | 创建 Web 后端服务器组，绑定 Web ECS |
| `volcenginecc_clb_nlb_listener` (internet) | 创建公网 NLB 监听器，默认监听 TCP 80 |
| `volcenginecc_clb_nlb` (intranet) | 创建私网 NLB，承载 Web 到 App 的内部流量 |
| `volcenginecc_clb_nlb_server_group` (app) | 创建 App 后端服务器组，绑定 App ECS |
| `volcenginecc_clb_nlb_listener` (intranet) | 创建私网 NLB 监听器，默认监听 TCP 8080 |
| `volcenginecc_rdsmysql_instance` | 创建 RDS MySQL 主备实例 |
| `volcenginecc_rdsmysql_allow_list` | 创建 RDS 白名单，默认放行 VPC 网段 |
| `volcenginecc_rdsmysql_database` | 创建业务数据库并授权高权限账号读写 |
| `volcenginecc_tos_bucket` | 创建 TOS 对象存储桶，用于图片、文件、日志等非结构化数据 |

说明：

- Web 和 App ECS 数量由 `web_instance_count`、`app_instance_count` 控制，默认各 2 台。
- 子网数量由 `availability_zones` 和 `subnet_cidrs` 控制，默认 2 个可用区。
- RDS 白名单在 `allow_list_cidrs` 非空时创建；根模块默认会放行当前 VPC CIDR。

### 3.2 工程结构

工程采用模块化设计，根模块负责编排，各子模块封装具体资源：

```text
.
├── main.tf                         # 根模块编排，按依赖关系调用各子模块
├── variables.tf                    # 全局变量定义，包括地域、规格、开关和密码变量
├── outputs.tf                      # 输出关键资源 ID、地址和名称
├── providers.tf                    # volcenginecc Provider 配置
├── versions.tf                     # Terraform 与 Provider 版本约束
├── locals.tf                       # 通用标签和 TOS 桶名等局部变量
├── terraform.tfvars.example        # 示例变量文件
├── examples/                       # 场景化 tfvars 示例
│   ├── compute-only.tfvars.example
│   └── network-only.tfvars.example
└── modules/
    ├── network/                    # VPC、Subnet、Security Group
    ├── compute/                    # Web / App ECS
    ├── load_balancer/              # 公网 / 私网 NLB、服务器组、监听器
    ├── database/                   # RDS MySQL、数据库、白名单
    └── storage/                    # TOS Bucket
```

### 3.3 核心代码示例

根模块通过 `enable_*` 开关控制各能力模块是否启用，以下为关键编排逻辑节选：

```hcl
module "network" {
  source             = "./modules/network"
  name_prefix        = var.name_prefix
  vpc_cidr           = var.vpc_cidr
  availability_zones = var.availability_zones
  subnet_cidrs       = var.subnet_cidrs
  # ...
}

module "compute" {
  source = "./modules/compute"
  count  = var.enable_compute ? 1 : 0

  vpc_id            = module.network.vpc_id
  subnet_ids        = module.network.subnet_ids
  subnet_zone_ids   = module.network.subnet_zone_ids
  security_group_id = module.network.security_group_id
  image_id          = var.image_id
  instance_type     = var.instance_type
  # ...
}

module "load_balancer" {
  source = "./modules/load_balancer"
  count  = var.enable_load_balancer && var.enable_compute ? 1 : 0

  vpc_id           = module.network.vpc_id
  subnet_ids       = module.network.subnet_ids
  web_instance_ids = module.compute[0].web_instance_ids
  app_instance_ids = module.compute[0].app_instance_ids
  # ...
}
```

ECS 模块通过 `count.index % length(subnet_ids)` 将实例均匀分布到多个可用区：

```hcl
resource "volcenginecc_ecs_instance" "web" {
  count         = var.web_instance_count
  instance_name = format("%s-web-%02d", var.name_prefix, count.index + 1)
  instance_type = var.instance_type
  zone_id       = var.subnet_zone_ids[count.index % length(var.subnet_ids)]

  primary_network_interface = {
    subnet_id          = var.subnet_ids[count.index % length(var.subnet_ids)]
    security_group_ids = [var.security_group_id]
  }
}
```

## 4. 使用说明

### 4.1 环境准备

本工程执行前需要完成以下准备：

1. 安装 Terraform，版本需满足 `versions.tf` 中的约束。
2. 开通火山引擎 VPC、ECS、CLB/NLB、RDS MySQL、TOS 服务。
3. 在 NLB 控制台完成首次授权，创建服务关联角色 `ServiceRoleForLoadBalancer`。
4. 准备可用的 ECS 镜像 ID，例如公共镜像的 `image-xxxx`。
5. 确认目标可用区下 ECS 规格、RDS 规格和库存可用。
6. 为执行账号准备权限，至少包含 VPC、ECS、CLB/NLB、RDS、TOS 的创建、查询、更新和删除权限。

推荐使用环境变量注入访问凭证：

```bash
export VOLCENGINE_ACCESS_KEY="your_access_key"
export VOLCENGINE_SECRET_KEY="your_secret_key"
export VOLCENGINE_REGION="cn-beijing"
```

敏感变量不要写入 `terraform.tfvars`，建议通过环境变量注入：

```bash
export TF_VAR_ecs_password="<your_ecs_password>"
export TF_VAR_rds_super_account_password="<your_rds_password>"
```

复制示例变量文件并按需修改：

```bash
cp terraform.tfvars.example terraform.tfvars
```

重点确认以下参数：

| 参数 | 说明 |
| --- | --- |
| `region` | 部署地域 |
| `availability_zones` | 可用区列表，默认 `cn-beijing-a`、`cn-beijing-b` |
| `subnet_cidrs` | 子网 CIDR，需要与可用区数量对应 |
| `image_id` | ECS 镜像 ID，必须按实际地域填写 |
| `instance_type` | ECS 实例规格 |
| `rds_node_spec` | RDS 节点规格 |
| `tos_bucket_name` | TOS 桶名，全局唯一；不填则自动生成 |

### 4.2 场景化部署示例

**全量部署：**

适用于权限、余额和服务开通均满足要求的账号，会创建网络、ECS、NLB、RDS 和 TOS。

```bash
terraform init
terraform plan -out=tfplan
terraform apply -parallelism=1 tfplan
```

**仅部署网络底座：**

适用于先验证 VPC、子网和安全组权限的场景。

```bash
cp examples/network-only.tfvars.example terraform.tfvars
terraform plan -out=tfplan
terraform apply tfplan
```

**部署网络与计算资源：**

适用于暂不创建 NLB、RDS、TOS，只验证 ECS 创建与跨可用区部署的场景。

```bash
cp examples/compute-only.tfvars.example terraform.tfvars
terraform plan -out=tfplan
terraform apply -parallelism=1 tfplan
```

**按需关闭付费资源：**

如果账号暂未开通某些服务，可在 `terraform.tfvars` 中关闭对应模块：

```hcl
enable_compute       = true
enable_load_balancer = true
enable_rds           = false
enable_tos           = false
```

### 4.3 部署预期结果

部署成功后，默认会得到：

- 1 个 VPC、2 个跨可用区子网和 1 个安全组。
- 2 台 Web ECS 和 2 台 App ECS。
- 1 个公网 NLB、1 个私网 NLB、2 个服务器组和 2 个监听器。
- 1 个 RDS MySQL 主备实例、1 个业务数据库和 1 个 RDS 白名单。
- 1 个 TOS Bucket。

可通过以下命令查看 Terraform 输出：

```bash
terraform output
```

常用输出包括：

| 输出 | 说明 |
| --- | --- |
| `vpc_id` | VPC ID |
| `subnet_ids` | 子网 ID 列表 |
| `web_instance_ids` / `app_instance_ids` | Web / App ECS ID 列表 |
| `web_instance_private_ips` / `app_instance_private_ips` | Web / App ECS 私网 IP 列表 |
| `internet_nlb_id` | 公网 NLB ID |
| `intranet_nlb_id` | 私网 NLB ID |
| `internet_nlb_dns_name` | 公网 NLB DNS 名称 |
| `intranet_nlb_dns_name` | 私网 NLB DNS 名称 |
| `rds_instance_id` | RDS 实例 ID |
| `rds_database_name` | RDS 业务数据库名 |
| `tos_bucket_name` | TOS 桶名 |

基础验证建议：

- 在 Web ECS 上启动 HTTP 测试服务，确认公网 NLB 后端健康检查为正常。
- 在 App ECS 上启动服务，确认私网 NLB 后端健康检查为正常。
- 在 App ECS 上连接 RDS Endpoint，确认数据库账号和白名单配置可用。
- 使用 TOS CLI 或 SDK 上传测试对象，确认对象存储可写。

### 4.4 销毁资源

销毁前请确认业务数据已备份，TOS 桶中对象已清空。

```bash
terraform destroy -parallelism=1
```

注意事项：

- NLB 默认启用控制台删除保护，如销毁失败，需要先在控制台关闭删除保护。
- TOS Bucket 如果已有对象或历史版本，需要先清空后再销毁。
- RDS 白名单解绑可能存在异步延迟，如首次销毁报占用，等待数分钟后重新执行 `terraform destroy`。
- 销毁会删除 Terraform 管理的全部资源，请勿在生产环境误执行。

## 5. 总结

本方案的主要优势：

- **一键交付**：通过 Terraform 标准化创建网络、计算、负载均衡、数据库和存储资源。
- **高可用设计**：ECS、子网、NLB 和 RDS 采用跨可用区部署思路，降低单可用区故障影响。
- **模块化复用**：按 `network`、`compute`、`load_balancer`、`database`、`storage` 拆分模块，便于按需组合。
- **安全可控**：凭证通过敏感变量传入，App 与数据层访问限制在 VPC 内部。
- **场景化部署**：通过 `enable_*` 开关支持全量部署、网络验证、计算验证和受限账号降级部署。

未来可继续扩展：

- 增加 Redis、消息队列等中间件模块，支撑更复杂的应用架构。
- 接入 CDN、WAF、TLS 证书和域名解析，完善公网访问链路。
- 增加日志、监控、告警和自动伸缩能力，提升运维可观测性。
- 接入远端 Backend 管理 Terraform State，支持团队协作和 CI/CD 流水线。
