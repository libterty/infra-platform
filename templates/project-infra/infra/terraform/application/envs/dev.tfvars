project             = "alpha"
env                 = "dev"
expected_account_id = "111111111111"

# The tags are placeholders. Replace them with the tag your CI pushed (a unique value such as the git SHA).
services = {
  api = {
    image_tag      = "0000000"
    container_port = 8080
    desired_count  = 1
    alb = {
      priority      = 100
      path_patterns = ["/api/*"]
    }
  }
  worker = {
    image_tag      = "0000000"
    container_port = 9000
    desired_count  = 1
  }
}

# Needed only once iam-app traces a service (its tracing list). The tag is explicit, never latest. Use source = "mirror"
# when network has no NAT (nat mode none); see infra/README.md.
# adot_collector = { tag = "v0.43.1", source = "public" }
