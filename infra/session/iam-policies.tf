resource "aws_iam_role_policy" "model_s3_read" {
  name = "${var.project_name}-${var.session_id}-model-s3-read"
  role = aws_iam_role.model.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["s3:GetObject"]
      Resource = "arn:aws:s3:::${local.model_artifact_bucket}/${var.model_artifact_key}"
    }]
  })
}
