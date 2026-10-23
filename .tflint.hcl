# 內建 terraform ruleset 加上 aws ruleset。aws 是 plugin，scripts/validate.sh 會先跑 tflint --init；不開 deep_check，不需要 AWS 憑證。
plugin "terraform" {
  enabled = true
  preset  = "recommended"
}

plugin "aws" {
  enabled = true
  version = "0.49.0"
  source  = "github.com/terraform-linters/tflint-ruleset-aws"
}
