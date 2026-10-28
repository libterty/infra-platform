variable "domain_prefix" {
  description = "hosted UI 的 prefix domain（`https://<domain_prefix>.auth.<region>.amazoncognito.com`）。同一個 region 內必須唯一，不能含 `aws`、`amazon`、`cognito`。"
  type        = string
}

variable "local_dev_origins" {
  description = "本機開發用的前端網址（例如 `http://localhost:5173`），會加進 SPA client 的 callback（`<網址>/callback`）與 logout（`<網址>/`）。只有 `http://localhost` 可以不是 HTTPS。"
  type        = list(string)
  default     = []
}

variable "deletion_protection" {
  description = "user pool 的刪除保護。destroy 之前要先改成 `false` 並 apply。"
  type        = bool
}
