// StreamAlert CloudTrail, also sending to CloudWatch Logs group
resource "aws_cloudtrail" "streamalert" {
  count                         = "${var.send_to_cloudwatch && !var.existing_trail ? 1 : 0}"
  name                          = "${var.prefix}.${var.cluster}.streamalert.cloudtrail"
  s3_bucket_name                = "${aws_s3_bucket.cloudtrail_bucket.id}"
  cloud_watch_logs_role_arn     = "${aws_iam_role.cloudtrail_to_cloudwatch_role.arn}"
  cloud_watch_logs_group_arn    = "${aws_cloudwatch_log_group.cloudtrail_logging.arn}"
  enable_log_file_validation    = true
  enable_logging                = "${var.enable_logging}"
  include_global_service_events = true
  is_multi_region_trail         = "${var.is_global_trail}"

  event_selector {
    read_write_type           = "All"
    include_management_events = true

    data_resource {
      type = "AWS::S3::Object"

      values = [
        "arn:aws:s3",
      ]
    }
  }
}

// StreamAlert CloudTrail, not sending to CloudWatch
resource "aws_cloudtrail" "streamalert_no_cloudwatch" {
  count                         = "${!var.send_to_cloudwatch && !var.existing_trail ? 1 : 0}"
  name                          = "${var.prefix}.${var.cluster}.streamalert.cloudtrail"
  s3_bucket_name                = "${aws_s3_bucket.cloudtrail_bucket.id}"
  enable_log_file_validation    = true
  enable_logging                = "${var.enable_logging}"
  include_global_service_events = true
  is_multi_region_trail         = "${var.is_global_trail}"

  event_selector {
    read_write_type           = "All"
    include_management_events = true

    data_resource {
      type = "AWS::S3::Object"

      values = [
        "arn:aws:s3",
      ]
    }
  }
}

// CloudWatch Log group to send all CloudTrail logs to
resource "aws_cloudwatch_log_group" "cloudtrail_logging" {
  count             = "${var.send_to_cloudwatch ? 1 : 0}"
  name              = "CloudTrail/DefaultLogGroup"
  retention_in_days = 1
}

// IAM Role: Allow CloudTrail logs to send logs to CloudWatch Logs
resource "aws_iam_role" "cloudtrail_to_cloudwatch_role" {
  count = "${var.send_to_cloudwatch ? 1 : 0}"
  name  = "cloudtrail_to_cloudwatch_role"

  assume_role_policy = "${data.aws_iam_policy_document.cloudtrail_to_cloudwatch_assume_role_policy.json}"
}

// IAM Policy Document: Allow CloudTrail to AssumeRole
data "aws_iam_policy_document" "cloudtrail_to_cloudwatch_assume_role_policy" {
  count = "${var.send_to_cloudwatch ? 1 : 0}"

  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
  }
}

// IAM Role Policy: Allow CloudTrail logs to create log streams and put logs to CloudWatch Logs
resource "aws_iam_role_policy" "cloudtrail_to_cloudwatch_create_logs" {
  count  = "${var.send_to_cloudwatch ? 1 : 0}"
  name   = "CloudTrailToCloudWatchCreateLogs"
  role   = "${aws_iam_role.cloudtrail_to_cloudwatch_role.id}"
  policy = "${data.aws_iam_policy_document.cloudtrail_to_cloudwatch_create_logs.json}"
}

// IAM Policy Document: Allow CloudTrail logs to create log streams and put logs to CloudWatch Logs
data "aws_iam_policy_document" "cloudtrail_to_cloudwatch_create_logs" {
  count = "${var.send_to_cloudwatch ? 1 : 0}"

  statement {
    sid    = "AWSCloudTrailCreateLogStream"
    effect = "Allow"

    actions = [
      "logs:CreateLogStream",
    ]

    resources = ["${aws_cloudwatch_log_group.cloudtrail_logging.arn}"]
  }

  statement {
    sid    = "AWSCloudTrailPutLogEvents"
    effect = "Allow"

    actions = [
      "logs:PutLogEvents",
    ]

    resources = ["${aws_cloudwatch_log_group.cloudtrail_logging.arn}"]
  }
}

locals {
  apply_filter_string = "{ $$.awsRegion != \"${var.region}\" }"
}

// CloudWatch Log Subscription Filter
//   If we are collecting CloudTrail logs in the 'home region' another way, this allows
//   for suppression of logs that originated in this region.
resource "aws_cloudwatch_log_subscription_filter" "cloudtrail_via_cloudwatch" {
  count           = "${var.send_to_cloudwatch ? 1 : 0}"
  name            = "cloudtrail_delivery"
  log_group_name  = "${aws_cloudwatch_log_group.cloudtrail_logging.name}"
  filter_pattern  = "${var.exclude_home_region_events ? local.apply_filter_string : ""}"
  destination_arn = "${var.cloudwatch_destination_arn}"
  distribution    = "Random"
}

// S3 bucket for CloudTrail output
resource "aws_s3_bucket" "cloudtrail_bucket" {
  count         = "${var.existing_trail ? 0 : 1}"
  bucket        = "${var.prefix}.${var.cluster}.streamalert.cloudtrail"
  force_destroy = false

  versioning {
    enabled = true
  }

  logging {
    target_bucket = "${var.s3_logging_bucket}"
    target_prefix = "${var.prefix}.${var.cluster}.streamalert.cloudtrail/"
  }

  policy = "${data.aws_iam_policy_document.cloudtrail_bucket.json}"

  tags {
    Name    = "${var.prefix}.${var.cluster}.streamalert.cloudtrail"
    Cluster = "${var.cluster}"
  }
}

data "aws_iam_policy_document" "cloudtrail_bucket" {
  count = "${var.existing_trail ? 0 : 1}"

  statement {
    sid = "AWSCloudTrailAclCheck"

    actions = [
      "s3:GetBucketAcl",
    ]

    resources = [
      "arn:aws:s3:::${var.prefix}.${var.cluster}.streamalert.cloudtrail",
    ]

    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
  }

  statement {
    sid = "AWSCloudTrailWrite"

    actions = [
      "s3:PutObject",
    ]

    resources = [
      "${formatlist("arn:aws:s3:::${var.prefix}.${var.cluster}.streamalert.cloudtrail/AWSLogs/%s/*", var.account_ids)}",
    ]

    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"

      values = [
        "bucket-owner-full-control",
      ]
    }
  }
}
