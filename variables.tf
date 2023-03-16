variable "cur_bucket_name" {
  type    = string
  default = ""
}

variable "vantage_sns_topic_arn" {
  type    = string
  default = "arn:aws:sns:us-east-1:630399649041:cost-and-usage-report-uploaded"
}
