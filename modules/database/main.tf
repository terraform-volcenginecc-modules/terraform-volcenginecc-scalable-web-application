###############################################################################
# database 模块
# 封装资源：
#   - RDS MySQL 主备实例（DoubleNode 架构，主备跨 AZ）
#   - RDS 业务数据库（含读写权限授权给高权限账号）
# 设计：
#   - 高权限账号（super_account）随实例创建一并下发
#   - Primary / Secondary 节点分别绑定不同可用区，实现数据层高可用
###############################################################################

locals {
  primary_zone   = var.availability_zones[0]
  secondary_zone = length(var.availability_zones) > 1 ? var.availability_zones[1] : var.availability_zones[0]
}

# RDS MySQL 主备实例
resource "volcenginecc_rdsmysql_instance" "main" {
  instance_name          = "${var.name_prefix}-rds"
  db_engine_version      = var.db_engine_version
  instance_type          = "DoubleNode"
  storage_type           = var.storage_type
  storage_space          = var.storage_space_gb
  vpc_id                 = var.vpc_id
  subnet_id              = var.subnet_id
  lower_case_table_names = "1"
  project_name           = var.project_name

  # 主备节点跨 AZ 部署，提升数据层可用性
  nodes = [
    {
      node_type = "Primary"
      node_spec = var.node_spec
      zone_id   = local.primary_zone
    },
    {
      node_type = "Secondary"
      node_spec = var.node_spec
      zone_id   = local.secondary_zone
    }
  ]

  super_account_name     = var.super_account_name
  super_account_password = var.super_account_password

  charge_detail = {
    charge_type = "PostPaid"
  }

  # 从实例侧绑定白名单：实例引用白名单 ID，使依赖图为「实例依赖白名单」。
  # 这样销毁时会先删实例、后删白名单，白名单删除时已无实例关联，
  # 从而避免服务端报 OperationDenied.AllowListIdInuse 的销毁死锁。
  allow_list_ids = length(var.allow_list_cidrs) > 0 ? [volcenginecc_rdsmysql_allow_list.main[0].allow_list_id] : null

  tags = var.tags_list
}

# RDS 白名单：仅定义放行的 CIDR（默认本 VPC 网段），不在此声明实例关联。
# - user_allow_list：用户配置的放行 IP/CIDR（官方字段，allow_list 为 computed 聚合视图）
# - 关联关系由实例侧 allow_list_ids 建立，实现「实例依赖白名单」的正确销毁顺序。
#   切勿在此设置 associated_instances / depends_on 反向引用实例，否则会让 Terraform
#   在销毁时先删白名单，触发 OperationDenied.AllowListIdInuse 死锁。
resource "volcenginecc_rdsmysql_allow_list" "main" {
  count = length(var.allow_list_cidrs) > 0 ? 1 : 0

  allow_list_name = "${var.name_prefix}-rds-allowlist"
  allow_list_desc = "Allow VPC internal access to RDS, managed by Terraform"
  allow_list_type = "IPv4"
  user_allow_list = var.allow_list_cidrs
}

# 业务数据库：默认授予高权限账号读写权限
resource "volcenginecc_rdsmysql_database" "main" {
  instance_id        = volcenginecc_rdsmysql_instance.main.instance_id
  name               = var.database_name
  character_set_name = var.character_set
  description        = "Business database created by Terraform"

  database_privileges = [
    {
      account_name      = var.super_account_name
      account_privilege = "ReadWrite"
      host              = "%"
    }
  ]

  depends_on = [volcenginecc_rdsmysql_instance.main]

  # database_privileges 由 Provider 在创建后回写额外 read-only 字段，会持续 drift
  lifecycle {
    ignore_changes = [database_privileges]
  }
}
