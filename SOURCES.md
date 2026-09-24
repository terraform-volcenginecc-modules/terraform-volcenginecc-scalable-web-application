# Provider 与能力依据

生成时间：2026-09-18。固定 Provider：`volcengine/volcenginecc` `0.0.70`（当前 Registry 最新稳定版，工程 `.terraform.lock.hcl` 已锁定该版本）。Terraform Schema 来自实际 `terraform providers schema -json`（311 个资源类型，SHA256 `62b09057035c66f074779c73b40d6b5c998e1d2807058508b9f57bc19dcb593b`）。

> 版本升级说明：本工程原锁定 `0.0.47`，本轮按用户需求升级到最新稳定版 `0.0.70`。已用 0.0.70 Schema 逐一核对本工程使用的 10 类资源全部字段，均存在且无新增 required 顶层字段（0 破坏性差异），并通过真实 `init/fmt/validate/plan` 复验。

## 采用的资源与官方文档

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

## 采用的具体字段与边界

| 资源 | 已核实的字段或行为 |
| --- | --- |
| vpc_vpc | `vpc_name` / `cidr_block` / `project_name` / `tags`；未使用 `support_ipv_4_gateway`（曾触发 force-replace，改由控制台默认兜底） |
| vpc_subnet | `vpc_id` / `zone_id` / `subnet_name` / `cidr_block`；子网与可用区一一对应实现跨 AZ |
| vpc_security_group | `ingress_permissions` 逐条对象（description/policy/port_start/port_end/protocol/priority/cidr_ip 等）；不声明 `egress_permissions`，沿用系统默认全通避免冲突告警 |
| ecs_instance | `instance_name` / `instance_type` / `zone_id` / `password`(sensitive) / `image.image_id` / `primary_network_interface`(subnet_id, security_group_ids) / `system_volume`(size, volume_type, delete_with_instance) / `tags`；`image` / `primary_network_interface` / `system_volume` 含创建后由 Provider 回写的 read-only 字段，通过 `lifecycle.ignore_changes` 屏蔽持续 drift |
| clb_nlb | `load_balancer_name` / `ipv_4_network_type`(internet\|intranet) / `ip_address_version` / `vpc_id` / `security_group_ids` / `cross_zone_enabled` / `zone_mappings`(subnet_id, zone_id) / `modification_protection_status`(ConsoleProtection) / `project_name` / `tags` |
| clb_nlb_server_group | `vpc_id` / `server_group_name` / `type`(instance) / `protocol`(TCP) / `health_check`(enabled, type=HTTP, port, uri) / `session_persistence_*` / `servers`(instance_id, type=ecs, ip, port, weight) |
| clb_nlb_listener | `load_balancer_id` / `server_group_id` / `listener_name` / `protocol`(TCP) / `port` / `enabled` / `connection_timeout` |
| rdsmysql_instance | `instance_name` / `db_engine_version` / `instance_type`(DoubleNode) / `storage_type` / `storage_space` / `vpc_id` / `subnet_id` / `lower_case_table_names` / `nodes`(Primary/Secondary 各绑不同 zone_id) / `super_account_name` / `super_account_password`(sensitive) / `charge_detail.charge_type`(PostPaid) |
| rdsmysql_database | `instance_id` / `name` / `character_set_name` / `database_privileges`(account_name, account_privilege, host)；`database_privileges` 创建后回写 read-only 字段，通过 `lifecycle.ignore_changes` 屏蔽 drift |
| rdsmysql_allow_list | `allow_list_name` / `allow_list_desc` / `allow_list_type`(IPv4) / `user_allow_list`(放行 CIDR，官方用户字段；`allow_list` 为 computed 聚合视图)；仅定义放行 CIDR，不声明 `associated_instances`。关联由实例侧 `rdsmysql_instance.allow_list_ids` 引用本白名单 `allow_list_id` 建立（依赖方向为「实例依赖白名单」，保证销毁时先删实例、后删白名单）。用于放行 App 层等 VPC 内来源访问 RDS 3306。注意：因服务端异步解绑延迟，首次 destroy 删白名单可能报 `AllowListIdInuse`，等待片刻重跑即可（见 VALIDATION.md 与 README 销毁说明） |
| tos_bucket | `name` / `enable_version_status`(Enabled) / `storage_class`(STANDARD) / `bucket_type`(fns) / `project_name` / `tags`；桶名由 `plantimestamp()` 生成（非 `timestamp()`），避免每次 plan 触发桶名变更 |

以上字段均在 `0.0.70` Schema 中核实存在，并通过真实 `terraform validate` 检查。同版本 Registry 示例可能包含非可配置字段，本工程按实际 Schema 选取。
