# iam-oidc-provider

為一個 EKS 叢集的 OIDC issuer 建立 IAM OIDC provider，讓 Pod 用 IRSA（IAM Roles for Service Accounts）取得 AWS 權限。只建一個 `aws_iam_openid_connect_provider`。

**只有在 Fargate 工作負載需要 AWS 權限時才用這個 module。** Fargate 不支援 EKS Pod Identity，所以只能走 IRSA（設計文件 D7）；其他 workload 一律用 Pod Identity，不需要 OIDC provider。IRSA 與 Pod Identity 並存會讓權限審查要看兩個地方（設計文件 R3），所以不要為了方便在 EC2 節點上也用 IRSA。

這個 module 是 `scripts/validate.sh` 的 S4 規則允許宣告 `aws_iam_*` 資源的第三個地方，而且只准 `aws_iam_openid_connect_provider`。

## 用法

```hcl
module "oidc" {
  source = "git::https://github.com/<org>/<repo>.git//modules/iam-oidc-provider?ref=iam-oidc-provider-v0.1.0"

  issuer_url = module.eks_cluster.oidc_issuer_url
}
```

跟 [`iam-role`](../iam-role/README.md) 的 `trust.federated` 搭配（role 要等 provider 建好才有 ARN，所以放在下一個 stack）：

```hcl
module "fargate_app" {
  source = "git::https://github.com/<org>/<repo>.git//modules/iam-role?ref=iam-role-v0.3.0"

  name = "alpha-dev-fargate-app"

  trust = {
    federated = {
      oidc_provider_arn = module.oidc.arn
      subject           = "system:serviceaccount:app:api"
    }
  }

  inline_policies = {
    read-bucket = jsonencode({
      Version = "2012-10-17"
      Statement = [{
        Effect   = "Allow"
        Action   = ["s3:GetObject"]
        Resource = "arn:aws:s3:::alpha-dev-assets/*"
      }]
    })
  }
}
```

`iam-role` 會把 trust policy 的條件鍵組成 `<issuer>:sub`、`<issuer>:aud`，`<issuer>` 就是由 `oidc_provider_arn` 去掉前綴得到的值，跟這個 module 的 `issuer` 輸出相同。

完整範例見 [`examples/basic/`](./examples/basic/main.tf)。

## 行為

- `issuer_url` 只接受 `https://oidc.eks.<region>.amazonaws.com/id/<id>`，結尾不可有 `/`，host 不可有多餘的字尾。
- `client_ids` 預設 `["sts.amazonaws.com"]`（IRSA 的 audience），至少要一個，每個 1–255 字元、不含空白。
- 不設定 `thumbprint_list`。依據：
  - AWS provider 6.x 的 schema 裡 `thumbprint_list` 是 optional + computed，可以省略。
  - AWS IAM 文件說明，IAM 會用自己信任的 root CA 清單驗證 OIDC IdP 的 JWKS endpoint 憑證，只有 IdP 的憑證不是這些 CA 簽的才會用 thumbprint；EKS issuer 的憑證屬於前者。來源：[Create an OpenID Connect (OIDC) identity provider in IAM](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_providers_create_oidc.html)。
- 輸出 `arn` 與 `issuer`（去掉 `https://`）。

## 限制

- 只收 EKS 的 issuer。GitHub Actions 等其他 OIDC IdP 不在這個 module 的範圍。
- 沒有 `Name` tag：provider 沒有名稱屬性，`tags` 原樣傳入。
- 同一個帳號對同一個 issuer URL 只能建一個 provider，重複建會被 AWS 拒絕。

## 輸入

> 之後改由 terraform-docs 產生。

| 名稱 | 型別 | 預設 | 必填 | 說明 |
|---|---|---|---|---|
| `issuer_url` | `string` | 無 | 是 | EKS 的 OIDC issuer，格式 `https://oidc.eks.<region>.amazonaws.com/id/<id>` |
| `client_ids` | `set(string)` | `["sts.amazonaws.com"]` | 否 | provider 接受的 client ID（audience），至少一個 |
| `tags` | `map(string)` | `{}` | 否 | provider 的 tag |

## 輸出

> 之後改由 terraform-docs 產生。

| 名稱 | 型別 | 說明 |
|---|---|---|
| `arn` | `string` | provider ARN，給 `iam-role` 的 `trust.federated.oidc_provider_arn` |
| `issuer` | `string` | issuer URL 去掉 `https://` |

## 測試

```bash
scripts/validate.sh modules/iam-oidc-provider
```
