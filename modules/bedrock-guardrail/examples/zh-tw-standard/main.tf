terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.69, < 7.0"
    }
  }
}

provider "aws" {
  region = "ap-northeast-1"
}

# Traditional Chinese input is only evaluated on the STANDARD tier; CLASSIC lets it through unchecked.
module "guardrail" {
  source = "../.."

  name                    = "alpha-dev-zh-input"
  blocked_input_message   = "抱歉，這個問題我無法回答。"
  blocked_output_message  = "抱歉，這個回答無法提供。"
  tier                    = "STANDARD"
  cross_region_profile_id = "apac.guardrail.v1:0"

  content_filters = {
    HATE          = { input_strength = "HIGH", output_strength = "HIGH" }
    INSULTS       = { input_strength = "MEDIUM", output_strength = "MEDIUM" }
    MISCONDUCT    = { input_strength = "HIGH", output_strength = "HIGH" }
    PROMPT_ATTACK = { input_strength = "HIGH", output_strength = "NONE" }
  }

  denied_topics = {
    investment-advice = {
      definition = "針對個股、基金或加密貨幣給出買賣建議。不包含解釋金融名詞。"
      examples   = ["我現在該買哪一檔股票？", "這支基金值得加碼嗎？"]
    }
    medical-diagnosis = {
      definition = "根據使用者描述的症狀判斷疾病或建議用藥。不包含一般健康常識。"
      examples   = ["我頭痛三天了，是不是腦瘤？"]
    }
  }

  tags = {
    Project = "alpha"
  }
}

output "guardrail_arn" {
  value = module.guardrail.guardrail_arn
}

output "cross_region_profile_arn" {
  value = module.guardrail.cross_region_profile_arn
}
