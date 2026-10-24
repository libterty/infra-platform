project             = "example"
env                 = "dev"
expected_account_id = "111111111111"

# Design section 7.5: dev and sit both run the full hot, UltraWarm and cold layout (design D6).
# The master user's name and password are not here: they come from the secret that foundation creates (design section 4.1).
engine_version = "OpenSearch_2.19"

hot = {
  instance_type  = "m7g.large.search"
  instance_count = 2
  ebs            = { volume_size = 20, volume_type = "gp3" }
}

# Three dedicated masters, never a T2 or T3 type: UltraWarm needs dedicated masters and T3 is not supported for it.
dedicated_master = { instance_type = "m7g.large.search", count = 3 }

# The service does not document a minimum warm node count, so 2 is a conservative choice (design K17); check it in the cloud.
warm         = { instance_type = "ultrawarm1.medium.search", count = 2 }
cold_storage = true

availability_zone_count = 2
