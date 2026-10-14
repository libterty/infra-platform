# 只用內建 terraform ruleset，不需要 tflint --init。
plugin "terraform" {
  enabled = true
  preset  = "recommended"
}
