output "stream_names" {
  description = "stream 名稱，由小到大排序。"
  value       = sort(keys(aws_kinesis_video_stream.this))
}

output "stream_arns" {
  description = "stream 名稱對應 ARN 的 map。給寫入端（KVS edge connector）與讀取端的 IAM policy 當 Resource 用。"
  value       = { for name, s in aws_kinesis_video_stream.this : name => s.arn }
}
