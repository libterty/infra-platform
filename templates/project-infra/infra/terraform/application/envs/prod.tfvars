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
