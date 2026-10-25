output "asset_model_ids" {
  description = "asset model 名稱對應 ID 的 map。"
  value       = local.asset_model_ids
}

output "asset_ids" {
  description = "asset 名稱對應 ID 的 map。KVS edge connector 的 `SiteWiseAssetIdForHub` 用 core device 那個 asset 的 ID。"
  value = merge(
    { for k, a in awscc_iotsitewise_asset.child : k => a.asset_id },
    { for k, a in awscc_iotsitewise_asset.this : k => a.asset_id },
  )
}

output "gateway_ids" {
  description = "gateway 名稱對應 ID 的 map。"
  value       = { for k, g in awscc_iotsitewise_gateway.this : k => g.gateway_id }
}
