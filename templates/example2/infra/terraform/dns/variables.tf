variable "zone_name" {
  description = "Public hosted zone of this env, a subdomain of the parent domain, such as dev.example.com. The parent zone delegates it with an NS record by hand after the first apply."
  type        = string
}
