

resource "aws_iam_role" "vantage_cross_account_connection_without_bucket" {
  count              = var.cur_bucket_name != "" ? 0 : 1
  name               = "vantage_cross_account_connection"
  assume_role_policy = data.aws_iam_policy_document.vantage_assume_role.json
}

resource "aws_iam_policy" "vantage_cross_account_connection_without_bucket" {
  for_each = local.policies_without_bucket

  name   = each.key
  policy = each.value
}

resource "aws_iam_role_policy_attachment" "vantage_cross_account_connection_without_bucket" {
  for_each = local.policies_without_bucket

  role       = aws_iam_role.vantage_cross_account_connection_without_bucket[0].name
  policy_arn = aws_iam_policy.vantage_cross_account_connection_without_bucket[each.key].arn
}

resource "aws_iam_role_policy_attachment" "vantage_cross_account_connection_without_bucket_viewonly" {
  count      = var.cur_bucket_name != "" ? 0 : 1
  role       = aws_iam_role.vantage_cross_account_connection_without_bucket[0].name
  policy_arn = "arn:aws:iam::aws:policy/job-function/ViewOnlyAccess"
}

resource "vantage_aws_provider" "without_bucket" {
  count = var.cur_bucket_name != "" ? 0 : 1

  cross_account_arn = aws_iam_role.vantage_cross_account_connection_without_bucket[0].arn
}
