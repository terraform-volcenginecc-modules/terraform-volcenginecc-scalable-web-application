# 执行与验证权限清单

本清单按工程实际编排的资源动作整理，供管理员按资源范围与测试前缀配置最小权限，不建议直接授予账号管理员权限。Cloud Control（volcenginecc）在底层调用对应云服务的 OpenAPI，需同时满足 Cloud Control 通道权限与下列各云服务的动作权限。

> 说明：本次维护未重新调用 Cloud Control `DescribeResourceType` 采集精确 `handler.permissions`。以下按各资源涉及的服务动作类别列出；生产环境请以目标账号的实际 handler 权限清单为准，并结合资源 TRN 限定范围。

## 前置人工授权

- **NLB 服务关联角色**：首次使用 NLB 前必须创建服务关联角色 `ServiceRoleForLoadBalancer`（控制台首次进入授权，或调用 `iam:CreateServiceLinkedRole`，`ServiceName=clb`）。缺失时会报 `ServiceRoleForLoadBalancer.NotFound`。
- **RDS / TOS 服务开通**：账号需已开通并未欠费；否则通过 `enable_rds=false` / `enable_tos=false` 降级。

## 各服务动作依赖

### VPC（vpc_vpc / vpc_subnet / vpc_security_group）

`vpc:CreateVpc`, `vpc:DescribeVpcs`, `vpc:DeleteVpc`,
`vpc:CreateSubnet`, `vpc:DescribeSubnets`, `vpc:DeleteSubnet`,
`vpc:CreateSecurityGroup`, `vpc:DescribeSecurityGroups`, `vpc:AuthorizeSecurityGroupIngress`, `vpc:DescribeSecurityGroupAttributes`, `vpc:DeleteSecurityGroup`

### ECS（ecs_instance）

`ecs:RunInstances` / `ecs:CreateInstance`, `ecs:DescribeInstances`, `ecs:DeleteInstance`, `ecs:StopInstance`,
`ecs:DescribeAvailableResource`（查询规格）, `ecs:DescribeImages`（查询镜像）

### NLB（clb_nlb / clb_nlb_server_group / clb_nlb_listener）

`clb:CreateLoadBalancer`, `clb:DescribeLoadBalancers`, `clb:DeleteLoadBalancer`,
`clb:CreateServerGroup`, `clb:DescribeServerGroups`, `clb:DeleteServerGroup`, `clb:AddServerGroupBackendServers`,
`clb:CreateListener`, `clb:DescribeListeners`, `clb:DeleteListener`

### RDS MySQL（rdsmysql_instance / rdsmysql_database）

`rds:CreateDBInstance`, `rds:DescribeDBInstances`, `rds:DeleteDBInstance`,
`rds:CreateDatabase`, `rds:DescribeDatabases`, `rds:DeleteDatabase`,
`rds:CreateAccount`, `rds:GrantDatabaseAccountPrivilege`（高权限账号随实例下发）,
`rds:CreateAllowList`, `rds:DescribeAllowLists`, `rds:AssociateAllowList`, `rds:DisassociateAllowList`, `rds:DeleteAllowList`（白名单放行 App 层访问 RDS）

### TOS（tos_bucket）

`tos:CreateBucket`, `tos:HeadBucket`, `tos:GetBucketVersioning`, `tos:PutBucketVersioning`, `tos:DeleteBucket`

## 销毁相关

- NLB 启用 `ConsoleProtection` 修改保护，销毁前需在控制台关闭保护。
- TOS 桶若已写入对象，需先清空对象再删除桶。
- 遗留的非工程托管同 VPC 安全组会阻塞 VPC 删除，可用 `vpc:DescribeSecurityGroups` + `vpc:DeleteSecurityGroup` 清理。
- **RDS 白名单首次销毁可能失败（重试即可）**：白名单关联已改由实例侧 `allow_list_ids` 建立，Terraform 会正确地先删实例、后删白名单。但火山服务端对"实例↔白名单"的解绑是异步的，实例刚删完时关联可能尚未释放，导致删白名单报 `OperationDenied.AllowListIdInuse`。等待约 2–3 分钟重跑 `terraform destroy` 即可秒删清空；或销毁前先 `terraform state rm` 白名单、删完实例后手动删除。详见 VALIDATION.md 与 README 销毁说明。
