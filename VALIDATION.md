# 真实验证记录

Provider：`volcengine/volcenginecc` `0.0.70`（工程 `.terraform.lock.hcl` 锁定；本轮由 `0.0.47` 升级到当前最新稳定版 `0.0.70`）。本次维护执行环境：Terraform 1.15.2、linux_amd64。

## 本次维护（规范化）验证结果

本轮先对既有工程做规范化并复验到 Plan 级别（下表），随后按用户需求执行了完整生命周期实测（见后文「全生命周期实测」章节）：

| 阶段 | 结果 | 证据 |
| --- | --- | --- |
| init | 通过 | `.aiac/runs/<时间>/init.log`；升级到 0.0.70 后重新 init，并用 `terraform providers lock` 生成 linux_amd64 / linux_arm64 / darwin_amd64 / darwin_arm64 四平台校验和 |
| fmt -check | 通过 | `.aiac/runs/<时间>/fmt.log`；`terraform fmt -recursive` 无改动 |
| validate | 通过 | `.aiac/runs/<时间>/validate.log`；全部字段与 0.0.70 Schema 一致 |
| plan | **通过** | `.aiac/runs/<时间>/plan.log`；使用真实 AK/SK 与注入的敏感变量，`-detailed-exitcode` 返回有变更 |

**Plan 结果**：`create=17, update=0, delete=0, replace=0, read=0, no-op=0`，无需人工确认。展开地址与确认清单完全一致：

- network：`volcenginecc_vpc_vpc.main` ×1、`volcenginecc_vpc_subnet.this[0..1]` ×2、`volcenginecc_vpc_security_group.main` ×1
- compute：`volcenginecc_ecs_instance.web[0..1]` ×2、`volcenginecc_ecs_instance.app[0..1]` ×2
- load_balancer：`volcenginecc_clb_nlb.internet/intranet` ×2、`volcenginecc_clb_nlb_server_group.web/app` ×2、`volcenginecc_clb_nlb_listener.internet/intranet` ×2
- database：`volcenginecc_rdsmysql_instance.main` ×1、`volcenginecc_rdsmysql_database.main` ×1
- storage：`volcenginecc_tos_bucket.main` ×1

合计 **17 个资源全部为 create**，与文档「17 个资源」及 `.aiac/resources.json` 一致，无非预期 replace/delete。

> Plan 时敏感凭证由环境变量注入（`VOLCENGINE_ACCESS_KEY/SECRET_KEY`、`TF_VAR_ecs_password`、`TF_VAR_rds_super_account_password`），未写入源码或交付包。

## 历史真实部署记录（前序交付）

本工程在纳入本次规范化前，已在 `cn-beijing` 完成真实 `terraform apply`，17 个资源全部创建成功（VPC×1、Subnet×2、SecurityGroup×1、ECS×4、NLB×2、ServerGroup×2、Listener×2、RDS 实例×1、RDS 库×1、TOS 桶×1），详见 README §4.5 的实测资源 ID 表。落地过程中针对真实云端响应做的加固（VPC force-replace、安全组描述/规则冲突、NLB 服务关联角色、ECS 跨 AZ 规格、TOS 桶名 plantimestamp、嵌套属性 drift 屏蔽、enable_* 降级开关）均已沉淀到代码，详见 README §4.6。

> 说明：上述历史 apply 的原始 State 已作为测试产物在本次规范化中清理（不入交付包）；本次维护未重新执行 apply，业务连通性验证（README §4.4）需在实际部署后由使用者执行。

## 全生命周期实测（0.0.70，2026-09-18）

按文档《使用说明》在 `cn-beijing` 用独立前缀 `tf-clb2`、独立桶名 `tf-clb2-tos-20260918` 执行完整生命周期（fmt → init → validate → plan → apply → 二次 plan → destroy → state list）。凭证与敏感密码由环境变量注入，未入库。

| 阶段 | 结果 | 关键证据 |
| --- | --- | --- |
| fmt / init / validate | 通过 | 无改动、Provider 0.0.70 初始化成功、字段校验通过 |
| plan | 通过 | `Plan: 17 to add, 0 to change, 0 to destroy` |
| apply | **通过** | `Apply complete! Resources: 17 added, 0 changed, 0 destroyed`；RDS 实例 `mysql-6c2cbd09fd09` + 库 `tf_db`、公网/私网 NLB、ECS×4、TOS 桶 `tf-clb2-tos-20260918` 均创建成功 |
| 二次 plan（幂等） | **通过** | `No changes. Your infrastructure matches the configuration.`，`-detailed-exitcode` 返回 0 |
| destroy | **通过（一次重试）** | 首轮销毁 9 个后，私网 NLB 监听器偶发 `GeneralServiceException: delete failed` 中止；重跑 `terraform destroy` 后剩余 8 个全部删除，`Destroy complete! Resources: 8 destroyed` |
| state list | **通过** | 最终 `terraform state list` 为空，无残留 |

### 本轮实测发现的两个真实行为（非代码缺陷）

1. **开启版本控制的 TOS 桶 destroy 需等待轮询周期**：`volcenginecc_tos_bucket`（`enable_version_status=Enabled`）删除时 Provider 约每 30 分钟轮询一次删除状态，本次桶在 `30m10s` 完成删除。这是 Provider 行为，销毁整体耗时会因此偏长；建议销毁时预留该等待窗口，不要误判为卡死。
2. **NLB 监听器偶发删除失败**：destroy 过程中 CLB NLBListener 可能返回 `GeneralServiceException: delete failed`（服务端偶发）。**重跑 `terraform destroy` 即可恢复并清空**，与 README §4.5 建议的降并发/必要时重试一致。

> 本轮未做应用层业务连通性测试（Web/App HTTP、`mysql` 登录、`tos cp` 读写），这些需在实际部署且 ECS 内启动服务后按 README §4.4 执行。

## 应用层额外验证与方案修改（0.0.70，2026-09-18，前缀 tf-clb3）

按《【IaC】最佳实践》对「高可用、安全可扩展的 Web 应用部署」的额外验证要求，重新 apply 一套资源（前缀 `tf-clb3`）并完成应用层业务验证：

| 额外验证项 | 结果 |
| --- | --- |
| ① Web/App ECS 启动 80 端口测试服务 | 通过（两台 Web 各返回自身 hostname） |
| ② 公网经 NLB 到达不同可用区 Web 实例 | 通过（关闭会话保持后请求跨 cn-beijing-a/b 轮询命中两台 Web） |
| ③ App ECS 连接 RDS 主备 + 基础读写 | 通过（`VERSION()=5.7.44-53-log`，建表/插入/查询/删表成功） |

为使上述验证通过，本轮对 TF 方案做了如下修改并已沉淀到代码：

1. **新增 RDS 白名单**（缺口修复）：`database` 模块新增 `volcenginecc_rdsmysql_allow_list`，用 `user_allow_list`（默认放行本 VPC 网段 `var.vpc_cidr`）定义放行 CIDR；新增变量 `rds_allow_list_cidrs`。修复前 App ECS 连 RDS 报 `ERROR 2003 (110)` 超时（实例默认无白名单）。关联关系的建立方式在后续版本经实测调整（见「白名单销毁缺陷的最终修复」），最终改为由实例侧 `allow_list_ids` 引用白名单 ID。
2. **会话保持参数化 + timeout 修复**：NLB 服务器组新增 `session_persistence_enabled`（根变量 `nlb_session_persistence_enabled`，默认 `true`），并将 `session_persistence_timeout = enabled ? 100 : null`。修复前关闭会话保持时仍下发 timeout，Apply 报 `InvalidSessionPersistenceTimeout.Malformed`。
3. **新增业务验证辅助输出**：根 `outputs.tf` 增加 `web_instance_private_ips` / `app_instance_private_ips` / `internet_nlb_dns_name` / `intranet_nlb_dns_name`，便于应用层验证。

### 已知限制：RDS 白名单销毁死锁（初版结论，已在最终版更正）

初版实现由白名单通过 `associated_instances` 反向引用实例，Terraform 据此判定"白名单依赖实例"，销毁时总是先删白名单而被服务端拒绝（`OperationDenied.AllowListIdInuse`）；当时判断为「Terraform 销毁顺序无法纠正的死锁」，处置办法为先 `-target` 删实例或 `state rm` 白名单。**此结论已在最终版（前缀 tf-clb4）经全生命周期实测更正**，详见下文「白名单销毁缺陷的最终修复与实测」。

## 白名单销毁缺陷的最终修复与实测（0.0.70，2026-09-20，前缀 tf-clb4，发布最终版）

本轮为验证白名单销毁缺陷的修复，用独立前缀 `tf-clb4`、并按需求**跳过 TOS**（`enable_tos=false`）重跑完整生命周期。凭证与敏感密码由环境变量注入，未入库。

### 代码修复：反转白名单与实例的依赖方向

- **改动**：白名单资源 `volcenginecc_rdsmysql_allow_list` 不再声明 `associated_instances`（不再反向引用实例）；改由实例 `volcenginecc_rdsmysql_instance` 的 `allow_list_ids` 引用白名单 `allow_list_id` 建立关联。
- **效果**：依赖图从「白名单依赖实例」反转为「实例依赖白名单」，Terraform 销毁顺序变为**先删实例、后删白名单**，创建顺序为**先建白名单、后建实例**。
- **验证 schema 依据**：`volcenginecc_rdsmysql_instance.allow_list_ids` 为 `optional+computed`（set of string），支持显式赋值；`volcenginecc_rdsmysql_allow_list.associated_instances` 为 `optional+computed`，不设置即不由白名单侧建立反向引用。

### 全生命周期实测结果

| 阶段 | 结果 | 关键证据 |
| --- | --- | --- |
| validate | 通过 | 反转依赖后 `terraform validate` 通过，无循环依赖 |
| plan | 通过 | `Plan: 17 to add, 0 to change, 0 to destroy`（因跳过 TOS，实际创建为 16 个资源 + 白名单，计入白名单后与依赖链一致） |
| apply | **通过（一次重试）** | 白名单先创建（16s），RDS 实例（3m13s）+ 库创建成功，`allow_list_ids` 自实例侧正确绑定；首轮安全组偶发 `InvalidOperation.Conflict` 致依赖它的 ECS/NLB 未建，重跑 apply 补齐 11 个，`Apply complete! Resources: 11 added` |
| destroy | **通过（一次重试）** | 首轮按正确顺序先删实例（3m12s）后删白名单，但白名单因服务端异步解绑延迟报 `OperationDenied.AllowListIdInuse`；等待数分钟重跑 destroy，白名单 **2 秒秒删**，剩余 9 个全部清空，`Destroy complete! Resources: 9 destroyed` |
| state list | **通过** | 最终 `terraform state list` 为空，云上无残留 |

### 关键结论（更正初版判断）

1. **依赖方向修复是必要且正确的**：它让 Terraform 严格「先删实例、后删白名单」，消除了初版"永久卡死、`depends_on`/`-target` 无法纠正"的顺序性死锁。
2. **但仍无法一次销毁成功**：真正的残余缺陷是**火山服务端对"实例↔白名单"关联的解绑是异步的**。实例在 Terraform 层删除完成的瞬间，服务端可能尚未释放关联，此时删白名单仍报 `AllowListIdInuse`。这是 Provider/服务端固有行为，纯 Terraform 编排无法根治。
3. **正确的处置策略**：首次 `terraform destroy` 若白名单报 `AllowListIdInuse`，**等待约 2–3 分钟让服务端完成解绑，重跑 `terraform destroy` 即可秒删清空**；或在销毁前 `state rm` 白名单、删完实例后手动删除。已写入 README §4.6 / §4.7。
4. **附带**：安全组创建、NLB 监听器删除均偶发瞬时错误（`InvalidOperation.Conflict` / `GeneralServiceException`），同属重试即恢复。

> tf-clb4 实测同样由环境变量注入 `VOLCENGINE_ACCESS_KEY/SECRET_KEY`、`TF_VAR_ecs_password`、`TF_VAR_rds_super_account_password`，未写入源码或交付包；本轮按需求 `enable_tos=false`，未创建 TOS 资源。

## 验证边界

- 本工程已达 **apply + 幂等 + 应用层业务验证（①②③）+ destroy 无残留** 级别（2026-09-18，0.0.70）。基础生命周期于前缀 tf-clb2 验证，应用层额外验证于前缀 tf-clb3 验证，白名单销毁缺陷的最终修复于前缀 tf-clb4 验证（2026-09-20，发布最终版）。
- NLB 首次使用需先创建服务关联角色 `ServiceRoleForLoadBalancer`（见 PERMISSIONS.md 与 README §4.1）。
- 公网入口仅 SSH(22)/Web(80)，生产建议收敛 SSH 来源。
- destroy 注意事项：TOS 版本控制桶删除需等待约 30 分钟轮询周期；NLB 监听器偶发删除失败可重跑 destroy；**RDS 白名单已改为实例侧 `allow_list_ids` 绑定，销毁顺序正确，但因服务端异步解绑延迟，首次删白名单可能报 `AllowListIdInuse`，等待 2–3 分钟重跑 `terraform destroy` 即可秒删清空**（见上「白名单销毁缺陷的最终修复与实测」）。
