# Example: the Client VPN on. Use it with `stacks.sh dev vpn plan -- -var-file=envs/examples/vpn.tfvars` after replacing
# the placeholders; the file has no tfbackend because it is not an environment. Every ARN below is a placeholder.
project             = "example"
env                 = "dev"
expected_account_id = "111111111111"

# Client VPN with mutual TLS: the ACM certificates are issued outside Terraform. One subnet association (each one is
# billed per hour); the authorization rules are derived from the data subnets, so clients reach only the data tier.
client_vpn = {
  server_certificate_arn = "arn:aws:acm:ap-northeast-1:111111111111:certificate/11111111-2222-3333-4444-555555555555"
  authentication = {
    mutual_tls_root_certificate_arn = "arn:aws:acm:ap-northeast-1:111111111111:certificate/66666666-7777-8888-9999-000000000000"
  }
  client_cidr_block       = "10.250.0.0/22"
  associated_subnet_count = 1
}
