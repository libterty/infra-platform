mock_provider "aws" {
  mock_resource "aws_db_instance" {
    defaults = {
      address  = "app-db.abc123.ap-northeast-1.rds.amazonaws.com"
      endpoint = "app-db.abc123.ap-northeast-1.rds.amazonaws.com:5432"
      master_user_secret = [{
        secret_arn    = "arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:rds!db-x"
        kms_key_id    = "k"
        secret_status = "active"
      }]
    }
  }

  mock_resource "aws_rds_cluster" {
    defaults = {
      endpoint        = "app-db.cluster-abc123.ap-northeast-1.rds.amazonaws.com"
      reader_endpoint = "app-db.cluster-ro-abc123.ap-northeast-1.rds.amazonaws.com"
      master_user_secret = [{
        secret_arn    = "arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:rds!cluster-x"
        kms_key_id    = "k"
        secret_status = "active"
      }]
    }
  }
}

mock_provider "random" {}

# Computed values are unknown at plan; override_during = plan lets plan-time runs read them.
override_resource {
  target          = aws_db_instance.this[0]
  override_during = plan
  values = {
    address     = "app-db.abc123.ap-northeast-1.rds.amazonaws.com"
    endpoint    = "app-db.abc123.ap-northeast-1.rds.amazonaws.com:5432"
    arn         = "arn:aws:rds:ap-northeast-1:111111111111:db:app-db"
    resource_id = "db-ABCDEFG"
    master_user_secret = [{
      secret_arn    = "arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:rds!db-x"
      kms_key_id    = "k"
      secret_status = "active"
    }]
  }
}

override_resource {
  target          = aws_rds_cluster.this[0]
  override_during = plan
  values = {
    id                  = "app-db"
    endpoint            = "app-db.cluster-abc123.ap-northeast-1.rds.amazonaws.com"
    reader_endpoint     = "app-db.cluster-ro-abc123.ap-northeast-1.rds.amazonaws.com"
    arn                 = "arn:aws:rds:ap-northeast-1:111111111111:cluster:app-db"
    cluster_resource_id = "cluster-ABCDEFG"
    master_user_secret = [{
      secret_arn    = "arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:rds!cluster-x"
      kms_key_id    = "k"
      secret_status = "active"
    }]
  }
}

override_resource {
  target          = aws_db_proxy.this[0]
  override_during = plan
  values = {
    endpoint = "app-db.proxy-abc123.ap-northeast-1.rds.amazonaws.com"
  }
}

override_resource {
  target          = aws_db_proxy_endpoint.read_only[0]
  override_during = plan
  values = {
    endpoint = "app-db-ro.endpoint.proxy-abc123.ap-northeast-1.rds.amazonaws.com"
  }
}

override_resource {
  target          = random_id.final_snapshot
  override_during = plan
  values          = { hex = "0a1b2c3d" }
}

variables {
  name           = "app-db"
  deployment     = "rds"
  engine_version = "16.4"
  database_name  = "app"
  rds            = { instance_class = "db.t4g.small" }
  subnet_ids     = ["subnet-aaa", "subnet-bbb"]

  security_group_ids = ["sg-0123456789abcdef0"]
  sns_topic_arns     = ["arn:aws:sns:ap-northeast-1:111111111111:alarms"]
  alarm_config       = { connections_threshold = 100 }
}

run "rds_proxy_off" {
  command = plan

  assert {
    condition     = length(aws_db_proxy.this) == 0 && length(aws_db_proxy_default_target_group.this) == 0 && length(aws_db_proxy_target.this) == 0 && length(aws_db_proxy_endpoint.read_only) == 0 && length(aws_cloudwatch_log_group.proxy) == 0
    error_message = "without proxy nothing Proxy-related is created"
  }

  assert {
    condition     = output.proxy_endpoint == null && output.app_endpoint == output.writer_endpoint && output.app_reader_endpoint == output.reader_endpoint
    error_message = "without proxy the app endpoints equal the DB endpoints"
  }
}

run "aurora_proxy_off" {
  command = plan

  variables {
    deployment = "aurora"
    rds        = null
    aurora     = { instance_class = "db.r7g.large" }
  }

  assert {
    condition     = length(aws_db_proxy.this) == 0 && length(aws_db_proxy_default_target_group.this) == 0 && length(aws_db_proxy_target.this) == 0 && length(aws_db_proxy_endpoint.read_only) == 0 && length(aws_cloudwatch_log_group.proxy) == 0
    error_message = "without proxy nothing Proxy-related is created"
  }

  assert {
    condition     = output.proxy_endpoint == null && output.app_endpoint == output.writer_endpoint && output.app_reader_endpoint == output.reader_endpoint
    error_message = "without proxy the app endpoints equal the cluster endpoints"
  }
}

run "serverless_proxy_off" {
  command = plan

  variables {
    deployment   = "aurora_serverless"
    rds          = null
    serverless   = { min_capacity = 0.5, max_capacity = 4 }
    alarm_config = {}
  }

  assert {
    condition     = length(aws_db_proxy.this) == 0 && length(aws_db_proxy_default_target_group.this) == 0 && length(aws_db_proxy_target.this) == 0 && length(aws_db_proxy_endpoint.read_only) == 0 && length(aws_cloudwatch_log_group.proxy) == 0
    error_message = "without proxy nothing Proxy-related is created"
  }

  assert {
    condition     = output.proxy_endpoint == null && output.app_endpoint == output.writer_endpoint && output.app_reader_endpoint == output.reader_endpoint
    error_message = "without proxy the app endpoints equal the cluster endpoints"
  }
}

run "rds_proxy_on" {
  command = plan

  variables {
    proxy = {
      security_group_ids = ["sg-0aaaaaaaaaaaaaaaa"]
      role_arn           = "arn:aws:iam::111111111111:role/app-db-proxy"
    }
  }

  assert {
    condition     = length(aws_db_proxy.this) == 1 && length(aws_db_proxy_default_target_group.this) == 1 && length(aws_db_proxy_target.this) == 1 && length(aws_cloudwatch_log_group.proxy) == 1
    error_message = "proxy creates one proxy, target group, target and log group"
  }

  assert {
    condition     = aws_db_proxy.this[0].engine_family == "POSTGRESQL" && aws_db_proxy.this[0].require_tls == true && aws_db_proxy.this[0].idle_client_timeout == 1800 && aws_db_proxy.this[0].debug_logging == false
    error_message = "proxy defaults: PostgreSQL, TLS required, 1800 s idle timeout, no debug logging"
  }

  assert {
    condition     = aws_db_proxy.this[0].vpc_subnet_ids == toset(var.subnet_ids)
    error_message = "proxy sits in the data tier subnets"
  }

  assert {
    condition     = one(aws_db_proxy_default_target_group.this[0].connection_pool_config).max_connections_percent == 50 && one(aws_db_proxy_default_target_group.this[0].connection_pool_config).max_idle_connections_percent == 25
    error_message = "connection pool defaults: 50% and 25%"
  }

  assert {
    condition     = aws_db_proxy_target.this[0].db_instance_identifier == "app-db" && aws_db_proxy_target.this[0].db_cluster_identifier == null
    error_message = "rds registers the instance as the Proxy target"
  }

  assert {
    condition     = aws_cloudwatch_log_group.proxy[0].name == "/aws/rds/proxy/app-db"
    error_message = "proxy log group is /aws/rds/proxy/<name>"
  }

  assert {
    condition     = output.app_endpoint == output.proxy_endpoint && output.proxy_endpoint == "app-db.proxy-abc123.ap-northeast-1.rds.amazonaws.com"
    error_message = "app_endpoint is the Proxy endpoint"
  }
}

run "aurora_proxy_on" {
  command = plan

  variables {
    deployment = "aurora"
    rds        = null
    aurora     = { instance_class = "db.r7g.large" }
    proxy = {
      security_group_ids = ["sg-0aaaaaaaaaaaaaaaa"]
      role_arn           = "arn:aws:iam::111111111111:role/app-db-proxy"
    }
  }

  assert {
    condition     = length(aws_db_proxy.this) == 1 && length(aws_db_proxy_default_target_group.this) == 1 && length(aws_db_proxy_target.this) == 1 && length(aws_cloudwatch_log_group.proxy) == 1
    error_message = "proxy creates one proxy, target group, target and log group"
  }

  assert {
    condition     = aws_db_proxy_target.this[0].db_cluster_identifier == "app-db" && aws_db_proxy_target.this[0].db_instance_identifier == null
    error_message = "aurora registers the cluster as the Proxy target"
  }

  assert {
    condition     = output.app_endpoint == output.proxy_endpoint
    error_message = "app_endpoint is the Proxy endpoint"
  }
}

run "serverless_proxy_on" {
  command = plan

  variables {
    deployment   = "aurora_serverless"
    rds          = null
    serverless   = { min_capacity = 0.5, max_capacity = 4 }
    alarm_config = {}
    proxy = {
      security_group_ids = ["sg-0aaaaaaaaaaaaaaaa"]
      role_arn           = "arn:aws:iam::111111111111:role/app-db-proxy"
    }
  }

  assert {
    condition     = length(aws_db_proxy.this) == 1 && length(aws_db_proxy_target.this) == 1 && aws_db_proxy_target.this[0].db_cluster_identifier == "app-db"
    error_message = "serverless registers the cluster as the Proxy target"
  }

  assert {
    condition     = length(aws_db_proxy_endpoint.read_only) == 0
    error_message = "serverless without readers has no read-only endpoint"
  }

  assert {
    condition     = output.app_endpoint == output.proxy_endpoint && output.app_reader_endpoint == output.proxy_endpoint
    error_message = "without a read-only endpoint the reader traffic also goes to the Proxy endpoint"
  }
}

run "aurora_proxy_ro" {
  command = plan

  variables {
    deployment = "aurora"
    rds        = null
    aurora     = { instance_class = "db.r7g.large", reader_count = 1 }
    proxy = {
      security_group_ids = ["sg-0aaaaaaaaaaaaaaaa"]
      role_arn           = "arn:aws:iam::111111111111:role/app-db-proxy"
    }
  }

  assert {
    condition     = length(aws_db_proxy_endpoint.read_only) == 1 && aws_db_proxy_endpoint.read_only[0].target_role == "READ_ONLY"
    error_message = "aurora with readers and Proxy creates one READ_ONLY endpoint"
  }

  assert {
    condition     = output.app_reader_endpoint == "app-db-ro.endpoint.proxy-abc123.ap-northeast-1.rds.amazonaws.com"
    error_message = "app_reader_endpoint is the Proxy read-only endpoint"
  }
}

run "aurora_proxy_zero_readers_has_no_ro" {
  command = plan

  variables {
    deployment = "aurora"
    rds        = null
    aurora     = { instance_class = "db.r7g.large", reader_count = 0 }
    proxy = {
      security_group_ids = ["sg-0aaaaaaaaaaaaaaaa"]
      role_arn           = "arn:aws:iam::111111111111:role/app-db-proxy"
    }
  }

  assert {
    condition     = length(aws_db_proxy_endpoint.read_only) == 0 && output.app_reader_endpoint == output.proxy_endpoint
    error_message = "reader_count = 0 creates no read-only endpoint"
  }
}

run "rds_proxy_no_ro" {
  command = plan

  variables {
    proxy = {
      security_group_ids = ["sg-0aaaaaaaaaaaaaaaa"]
      role_arn           = "arn:aws:iam::111111111111:role/app-db-proxy"
    }
  }

  assert {
    condition     = length(aws_db_proxy_endpoint.read_only) == 0 && output.has_reader == false && output.app_reader_endpoint == output.proxy_endpoint
    error_message = "rds never gets a read-only endpoint"
  }
}

run "proxy_role_passed_through" {
  command = plan

  variables {
    proxy = {
      security_group_ids = ["sg-0aaaaaaaaaaaaaaaa", "sg-0bbbbbbbbbbbbbbbb"]
      role_arn           = "arn:aws:iam::111111111111:role/custom-proxy-role"
    }
  }

  assert {
    condition     = aws_db_proxy.this[0].role_arn == "arn:aws:iam::111111111111:role/custom-proxy-role"
    error_message = "the Proxy must use the role ARN passed in; the module creates no role"
  }

  assert {
    condition     = one(aws_db_proxy.this[0].auth).auth_scheme == "SECRETS" && one(aws_db_proxy.this[0].auth).iam_auth == "DISABLED"
    error_message = "Proxy authenticates with SECRETS and IAM auth disabled"
  }

  assert {
    condition     = one(aws_db_proxy.this[0].auth).secret_arn == "arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:rds!db-x"
    error_message = "Proxy auth uses the master user secret"
  }

  assert {
    condition     = aws_db_proxy.this[0].vpc_security_group_ids == toset(["sg-0aaaaaaaaaaaaaaaa", "sg-0bbbbbbbbbbbbbbbb"])
    error_message = "Proxy SGs come from proxy.security_group_ids"
  }
}

run "proxy_overrides" {
  command = plan

  variables {
    proxy = {
      security_group_ids           = ["sg-0aaaaaaaaaaaaaaaa"]
      role_arn                     = "arn:aws:iam::111111111111:role/app-db-proxy"
      require_tls                  = false
      idle_client_timeout          = 600
      max_connections_percent      = 80
      max_idle_connections_percent = 10
      debug_logging                = true
    }
  }

  assert {
    condition     = aws_db_proxy.this[0].require_tls == false && aws_db_proxy.this[0].idle_client_timeout == 600 && aws_db_proxy.this[0].debug_logging == true
    error_message = "proxy settings follow the inputs"
  }

  assert {
    condition     = one(aws_db_proxy_default_target_group.this[0].connection_pool_config).max_connections_percent == 80 && one(aws_db_proxy_default_target_group.this[0].connection_pool_config).max_idle_connections_percent == 10
    error_message = "connection pool settings follow the inputs"
  }
}

run "monitoring_role_passed_through_rds" {
  command = plan

  variables {
    monitoring = { role_arn = "arn:aws:iam::111111111111:role/app-db-monitoring" }
  }

  assert {
    condition     = aws_db_instance.this[0].monitoring_interval == 60 && aws_db_instance.this[0].monitoring_role_arn == "arn:aws:iam::111111111111:role/app-db-monitoring"
    error_message = "rds uses monitoring.role_arn with the default 60 s interval"
  }
}

run "monitoring_role_passed_through_aurora" {
  command = plan

  variables {
    deployment = "aurora"
    rds        = null
    aurora     = { instance_class = "db.r7g.large" }
    monitoring = { interval = 30, role_arn = "arn:aws:iam::111111111111:role/app-db-monitoring" }
  }

  assert {
    condition     = alltrue([for i in aws_rds_cluster_instance.this : i.monitoring_interval == 30 && i.monitoring_role_arn == "arn:aws:iam::111111111111:role/app-db-monitoring"])
    error_message = "every aurora instance uses the monitoring role and interval"
  }
}

run "monitoring_off" {
  command = plan

  assert {
    condition     = aws_db_instance.this[0].monitoring_interval == 0
    error_message = "monitoring = null turns Enhanced Monitoring off"
  }

}
