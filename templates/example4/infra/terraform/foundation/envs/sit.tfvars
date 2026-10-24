project             = "example"
env                 = "sit"
expected_account_id = "222222222222"

alarm_emails = ["platform-alerts@example.com"]

# Account-level Glue Data Catalog encryption: only ONE place per account and region may set it, and every identity that
# reads or writes the catalog (other projects included) then needs kms:Decrypt and kms:GenerateDataKey on the key.
# {} encrypts with this stack's shared key; { kms_key_arn = "..." } uses another key. A second project in the same
# account must set null.
glue_catalog_encryption = {}
