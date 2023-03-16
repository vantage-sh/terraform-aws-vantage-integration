module "aws_provider" {
  source = "./modules/aws_provider"

  cur_bucket_name       = var.cur_bucket_name
  vantage_sns_topic_arn = var.vantage_sns_topic_arn
}
