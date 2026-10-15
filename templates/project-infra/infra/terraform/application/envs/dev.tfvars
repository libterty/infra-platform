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
