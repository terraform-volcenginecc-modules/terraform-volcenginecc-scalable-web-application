variable "name_prefix" {
  type        = string
  description = "资源名称前缀"
}

variable "project_name" {
  type        = string
  description = "火山引擎项目名"
}

variable "vpc_id" {
  type        = string
  description = "RDS 所属 VPC ID"
}

variable "subnet_id" {
  type        = string
  description = "RDS 实例所在子网 ID"
}

variable "availability_zones" {
  type        = list(string)
  description = "可用区列表，用于主备节点跨 AZ 部署"
}

variable "db_engine_version" {
  type        = string
  description = "MySQL 引擎版本"
}

variable "node_spec" {
  type        = string
  description = "RDS 节点规格"
}

variable "storage_type" {
  type        = string
  description = "RDS 存储类型"
}

variable "storage_space_gb" {
  type        = number
  description = "RDS 存储空间（GB）"
}

variable "super_account_name" {
  type        = string
  description = "RDS 高权限账号名"
}

variable "super_account_password" {
  type        = string
  description = "RDS 高权限账号密码"
  sensitive   = true
}

variable "database_name" {
  type        = string
  description = "RDS 业务数据库名"
}

variable "character_set" {
  type        = string
  description = "数据库字符集"
}

variable "allow_list_cidrs" {
  type        = list(string)
  description = "RDS 白名单放行的 CIDR 列表，默认放行本 VPC 网段以便 App ECS 访问"
  default     = []
}

variable "tags_list" {
  type = list(object({
    key   = string
    value = string
  }))
  description = "通用标签"
  default     = []
}
