output "log_group_names" { value = { for name, group in aws_cloudwatch_log_group.host : name => group.name } }
output "budget_topic_arn" { value = aws_sns_topic.budget.arn }

