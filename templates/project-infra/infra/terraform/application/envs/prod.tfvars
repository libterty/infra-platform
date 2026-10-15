project             = "alpha"
env                 = "prod"
expected_account_id = "222222222222"

# The tags are placeholders. Replace them with the tag your CI pushed (a unique value such as the git SHA).
services = {
  api = {
    image_tag      = "0000000"
    container_port = 8080
    desired_count  = 2
    max_capacity   = 10
    alb = {
      priority            = 100
      path_patterns       = ["/api/*"]
      requests_per_target = 300
    }
  }
  worker = {
    image_tag      = "0000000"
    container_port = 9000
    desired_count  = 2
    max_capacity   = 4
  }
}

# Needed only once iam-app traces a service (its tracing list). The tag is explicit, never latest. Use source = "mirror"
# when network has no NAT (nat mode none); see infra/README.md.
# adot_collector = { tag = "v0.43.1", source = "public" }
