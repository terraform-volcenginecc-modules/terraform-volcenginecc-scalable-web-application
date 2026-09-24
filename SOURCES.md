# Provider 与能力依据

本文档说明本工程使用的 Terraform Provider、资源类型和关键字段依据。为便于发布，文档不包含内部验证路径、Schema 摘要哈希、真实账号信息或测试资源标识。

## Provider

| 项目 | 说明 |
| --- | --- |
| Provider | `volcengine/volcenginecc` |
| 版本 | `0.0.70` |
| 锁定方式 | 通过 `.terraform.lock.hcl` 固定 Provider 版本 |
| 校验方式 | 基于 Provider Schema、官方文档和 Terraform 校验命令确认 |

## 官方资源文档

- [ecs_instance](https://registry.terraform.io/providers/volcengine/volcenginecc/0.0.70/docs/resources/ecs_instance)
- [vpc_vpc](https://registry.terraform.io/providers/volcengine/volcenginecc/0.0.70/docs/resources/vpc_vpc)
- [vpc_subnet](https://registry.terraform.io/providers/volcengine/volcenginecc/0.0.70/docs/resources/vpc_subnet)
- [vpc_security_group](https://registry.terraform.io/providers/volcengine/volcenginecc/0.0.70/docs/resources/vpc_security_group)
- [clb_nlb](https://registry.terraform.io/providers/volcengine/volcenginecc/0.0.70/docs/resources/clb_nlb)
- [clb_nlb_server_group](https://registry.terraform.io/providers/volcengine/volcenginecc/0.0.70/docs/resources/clb_nlb_server_group)
- [clb_nlb_listener](https://registry.terraform.io/providers/volcengine/volcenginecc/0.0.70/docs/resources/clb_nlb_listener)
- [rdsmysql_instance](https://registry.terraform.io/providers/volcengine/volcenginecc/0.0.70/docs/resources/rdsmysql_instance)
- [rdsmysql_database](https://registry.terraform.io/providers/volcengine/volcenginecc/0.0.70/docs/resources/rdsmysql_database)
- [rdsmysql_allow_list](https://registry.terraform.io/providers/volcengine/volcenginecc/0.0.70/docs/resources/rdsmysql_allow_list)
- [tos_bucket](https://registry.terraform.io/providers/volcengine/volcenginecc/0.0.70/docs/resources/tos_bucket)

## 资源字段依据

| 资源 | 本工程使用的关键字段或行为 |
| --- | --- |
| `vpc_vpc` | `vpc_name`、`cidr_block`、`project_name`、`tags` |
| `vpc_subnet` | `vpc_id`、`zone_id`、`subnet_name`、`cidr_block`；子网与可用区一一对应 |
| `vpc_security_group` | `ingress_permissions`；出站规则沿用系统默认策略 |
| `ecs_instance` | `instance_name`、`instance_type`、`zone_id`、`password`、`image.image_id`、`primary_network_interface`、`system_volume`、`tags` |
| `clb_nlb` | `load_balancer_name`、`ipv_4_network_type`、`ip_address_version`、`vpc_id`、`security_group_ids`、`cross_zone_enabled`、`zone_mappings`、`modification_protection_status`、`project_name`、`tags` |
| `clb_nlb_server_group` | `vpc_id`、`server_group_name`、`type`、`protocol`、`health_check`、`session_persistence_*`、`servers` |
| `clb_nlb_listener` | `load_balancer_id`、`server_group_id`、`listener_name`、`protocol`、`port`、`enabled`、`connection_timeout` |
| `rdsmysql_instance` | `instance_name`、`db_engine_version`、`instance_type`、`storage_type`、`storage_space`、`vpc_id`、`subnet_id`、`nodes`、`super_account_name`、`super_account_password`、`charge_detail`、`allow_list_ids` |
| `rdsmysql_database` | `instance_id`、`name`、`character_set_name`、`database_privileges` |
| `rdsmysql_allow_list` | `allow_list_name`、`allow_list_desc`、`allow_list_type`、`user_allow_list` |
| `tos_bucket` | `name`、`enable_version_status`、`storage_class`、`bucket_type`、`project_name`、`tags` |

## 设计边界

- `volcenginecc` Provider 当前不提供与原 `volcengine` Provider 完全等价的镜像数据源，本工程要求用户显式填写 `image_id`。
- RDS 白名单只声明放行 CIDR，实例关联由 `rdsmysql_instance.allow_list_ids` 建立，避免销毁顺序反向。
- ECS 和 RDS 数据库部分字段会在创建后由 Provider 回写，本工程通过 `lifecycle.ignore_changes` 避免非业务变更导致的持续 drift。
- TOS 桶名不使用普通运行时间戳，避免每次 plan 产生不必要的资源替换。
- 同版本官方示例可能包含只读或服务端回写字段，实际工程以 Provider Schema 和 `terraform validate` 为准。
