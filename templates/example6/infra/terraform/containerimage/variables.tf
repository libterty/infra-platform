variable "lifecycle_rules" {
  description = "映像的保留規則：未加 tag 的映像 `untagged_expire_days` 天後刪除，最多保留 `keep_count` 個映像。依部署頻率調整，留夠可以回滾的 tag。"
  type = object({
    untagged_expire_days = optional(number, 7)
    keep_count           = optional(number, 50)
  })
  default = {}
}
