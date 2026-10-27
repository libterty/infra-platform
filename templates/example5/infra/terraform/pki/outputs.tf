# For people running terraform output. Downstream stacks never read these; cross-stack values go through SSM only.
output "ca" {
  description = "CA 的狀態、ARN 與憑證（JSON）；沒開時是 `{\"enabled\":false}`。"
  value       = local.published_strings["ca"]
}

output "ca_csr" {
  description = "CA 的 CSR（PEM），`SUBORDINATE` 時拿去給上層 CA 簽；沒開時是 `null`。"
  value       = one(module.ca[*].csr)
}
