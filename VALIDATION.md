# 验证记录

本文档记录本 Terraform 工程的验证范围、验证结果和已知注意事项。为便于发布，文档不包含真实账号信息、访问凭证、云资源 ID、测试前缀、测试桶名或内部执行路径。

## 验证环境

| 项目 | 说明 |
| --- | --- |
| Terraform | `>= 1.0.7` |
| Provider | `volcengine/volcenginecc` `0.0.70` |
| 目标地域 | `cn-beijing` |
| 架构范围 | VPC、Subnet、SecurityGroup、ECS、NLB、RDS MySQL、TOS |

敏感信息通过环境变量注入，包括火山引擎 AK/SK、ECS 登录密码和 RDS 高权限账号密码，未写入源码或交付文件。

## 基础验证

| 阶段 | 结果 | 说明 |
| --- | --- | --- |
| `terraform fmt -recursive` | 通过 | Terraform 文件格式化正常 |
| `terraform init` | 通过 | Provider 初始化成功 |
| `terraform validate` | 通过 | 配置语法和 Provider Schema 校验通过 |
| `terraform plan` | 通过 | 默认场景可生成预期资源创建计划 |

默认全量部署计划包含以下资源：

- network：VPC ×1、Subnet ×2、SecurityGroup ×1
- compute：Web ECS ×2、App ECS ×2
- load_balancer：公网/私网 NLB ×2、ServerGroup ×2、Listener ×2
- database：RDS MySQL 实例 ×1、RDS 数据库 ×1、RDS 白名单 ×1
- storage：TOS Bucket ×1

## 生命周期验证

工程已完成基础生命周期验证，覆盖以下流程：

| 阶段 | 结果 | 说明 |
| --- | --- | --- |
| plan | 通过 | 全量部署计划符合预期，无非预期删除或替换 |
| apply | 通过 | 默认资源可创建成功 |
| 二次 plan | 通过 | 已部署环境再次 plan 可收敛，无非预期漂移 |
| destroy | 通过 | 资源可销毁清理，个别云服务异步行为需按注意事项处理 |
| state list | 通过 | 销毁完成后 Terraform State 无资源残留 |

## 应用层验证

已完成以下应用层连通性验证：

| 验证项 | 结果 |
| --- | --- |
| Web/App ECS 启动 HTTP 测试服务 | 通过 |
| 公网请求经 NLB 到达 Web 层 | 通过 |
| Web 层经私网 NLB 访问 App 层 | 通过 |
| App ECS 连接 RDS MySQL 并执行基础读写 | 通过 |

TOS 读写能力可在实际部署后通过 TOS CLI 或 SDK 进一步验证。

## 已验证的关键行为

- `enable_*` 模块开关可用于按账号权限、余额或服务开通状态进行降级部署。
- Web/App ECS 可按子网和可用区均匀分布。
- NLB 支持公网入口和 VPC 内部转发两个层级。
- RDS 白名单由实例侧 `allow_list_ids` 建立关联，Terraform 依赖方向符合创建和销毁顺序要求。
- ECS 和 RDS 数据库中部分 Provider 回写字段已通过 `lifecycle.ignore_changes` 屏蔽，避免无意义漂移。
- TOS 桶名使用稳定时间函数生成，避免每次 plan 触发桶名变化。

## 已知注意事项

- 首次使用 NLB 前，需要在控制台完成服务关联角色授权。
- NLB 默认启用控制台删除保护，销毁前如遇删除失败，需要先关闭删除保护。
- TOS Bucket 如果已写入对象或历史版本，需要先清空后再销毁。
- 开启版本控制的 TOS Bucket 删除可能较慢，需要预留等待时间。
- RDS 白名单解绑存在服务端异步延迟，首次销毁如提示白名单仍被实例占用，等待数分钟后重试 `terraform destroy` 即可。
- 安全组创建、NLB 监听器删除等云服务操作偶发冲突或瞬时失败时，通常可通过重试恢复。具体表现为：
  - 创建阶段安全组偶发 `InvalidOperation.Conflict`（Cloud Control API 瞬时/幂等冲突），可能导致依赖安全组的 ECS、NLB 连锁未创建；直接重跑 `terraform apply` 即可补齐，无需改代码。
  - 销毁阶段白名单 `AllowListIdInuse`（服务端异步解绑延迟）、NLB 监听器 `GeneralServiceException: delete failed`（瞬时故障），等待数分钟后重试对应命令即可收敛。
- 鉴于创建阶段存在上述偶发冲突，建议 apply 时使用并发度 `-parallelism=2`，降低资源操作相互冲突的概率。

## 验证边界

- 本验证覆盖基础设施创建、幂等检查、应用层连通性和资源销毁。
- 本验证不包含生产业务压测、长期稳定性观测、故障演练和安全渗透测试。
- 生产使用前建议结合业务访问量、合规要求和运维策略补充监控、告警、备份和安全基线检查。
