variable "domain_name" {
  description = "這個環境的子網域，例如 `dev.example.com`。上層網域要手動加一筆 NS 委派指到 `name_servers` 輸出，`certificate` 才驗證得過。"
  type        = string
}
