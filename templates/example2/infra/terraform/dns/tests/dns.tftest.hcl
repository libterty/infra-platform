mock_provider "aws" {}

variables {
  project             = "example"
  env                 = "dev"
  expected_account_id = "111111111111"
  zone_name           = "dev.example.com"
}

run "zone_is_named_from_tfvars" {
  command = plan

  assert {
    condition     = module.zone.name == "dev.example.com"
    error_message = "The zone is the one named by zone_name"
  }
}

run "publishes_zone_id_name_and_name_servers" {
  command = plan

  override_module {
    target = module.zone
    outputs = {
      zone_id      = "Z0123456789ABCDEFGHIJ"
      name         = "dev.example.com"
      name_servers = ["ns-1.awsdns-01.org", "ns-2.awsdns-02.co.uk", "ns-3.awsdns-03.com", "ns-4.awsdns-04.net"]
      arn          = "arn:aws:route53:::hostedzone/Z0123456789ABCDEFGHIJ"
    }
  }

  assert {
    condition = local.published_strings == {
      zone_id   = "Z0123456789ABCDEFGHIJ"
      zone_name = "dev.example.com"
    }
    error_message = "zone_id and zone_name come from the zone module"
  }

  assert {
    condition     = jsonencode(local.published_lists) == jsonencode({ name_servers = ["ns-1.awsdns-01.org", "ns-2.awsdns-02.co.uk", "ns-3.awsdns-03.com", "ns-4.awsdns-04.net"] })
    error_message = "name_servers is published as a StringList"
  }

  assert {
    condition = module.ssm_publish.names == {
      zone_id      = "/example/dev/dns/zone_id"
      zone_name    = "/example/dev/dns/zone_name"
      name_servers = "/example/dev/dns/name_servers"
    }
    error_message = "ssm-publish must write exactly the three dns keys under the dns path"
  }

  assert {
    condition     = jsonencode(output.name_servers) == jsonencode(module.zone.name_servers)
    error_message = "terraform output name_servers gives the values for the NS record in the parent zone"
  }
}

