# For people running terraform output. Downstream stacks never read these; cross-stack values go through SSM only.
output "edge_connector_asset_ids" {
  description = "攝影機 id 與 core device 對應的 SiteWise asset ID（JSON）；沒有攝影機時是 `{}`。"
  value       = local.published_strings["edge_connector_asset_ids"]
}

output "gateway_ids" {
  description = "SiteWise gateway 名稱對應 ID；沒有 gateway 時是空 map。"
  value       = length(module.sitewise) == 0 ? {} : module.sitewise[0].gateway_ids
}
