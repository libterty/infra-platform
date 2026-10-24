resource "aws_glue_catalog_database" "this" {
  for_each = var.databases

  name         = each.key
  description  = each.value.description
  location_uri = each.value.location_uri

  tags = merge(var.tags, { Name = each.key })
}
