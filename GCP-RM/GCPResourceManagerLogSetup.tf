terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "3.73.0"
    }
  }

  required_version = ">= 0.15.0"
}

variable "project-id" {
  type        = string
  description = "Enter your project ID"
}

variable "topic-name" {
  type        = string
  default     = "sentinelgcprm-audit-topic"
  description = "Name of existing topic"
}

variable "organization-id" {
  type        = string
  default     = ""
  description = "Organization ID (leave empty to use project-level sink)"
}

data "google_project" "project" {
  project_id = var.project-id
}

# Enable Logging API
resource "google_project_service" "enable-logging-api" {
  service = "logging.googleapis.com"
  project = data.google_project.project.project_id
}

# Create Pub/Sub Topic
resource "google_pubsub_topic" "sentinelgcprm-audit-topic" {
  count   = var.topic-name != "sentinelgcprm-audit-topic" ? 0 : 1
  name    = var.topic-name
  project = data.google_project.project.project_id
}

# Create Pub/Sub Subscription
resource "google_pubsub_subscription" "sentinel-subscription" {
  project = data.google_project.project.project_id
  name    = "sentinel-subscription-gcprm-auditlogs"
  topic   = var.topic-name
  depends_on = [google_pubsub_topic.sentinelgcprm-audit-topic]
}

# Create Logging Bucket
resource "google_logging_project_bucket_config" "rm_log_bucket" {
  project        = data.google_project.project.project_id
  location       = "global"
  bucket_id      = "gcprm-audit-log-bucket"
  retention_days = 30
  description    = "Stores GCP Resource Manager logs before forwarding to Sentinel"
}

# Org-level Sink → Log Bucket
resource "google_logging_organization_sink" "rm_logs_to_bucket" {
  count = var.organization-id == "" ? 0 : 1
  name   = "org-gcprm-audit-to-logbucket"
  org_id = var.organization-id
  destination = "logging.googleapis.com/projects/${data.google_project.project.project_id}/locations/global/buckets/${google_logging_project_bucket_config.rm_log_bucket.bucket_id}"

  filter = "protoPayload.serviceName=cloudresourcemanager.googleapis.com"
  include_children = true
  unique_writer_identity = true
}

# Project-level Sink → Log Bucket
resource "google_logging_project_sink" "rm_logs_to_bucket" {
  count      = var.organization-id == "" ? 1 : 0
  name       = "project-gcprm-audit-to-logbucket"
  project    = data.google_project.project.project_id
  destination = "logging.googleapis.com/projects/${data.google_project.project.project_id}/locations/global/buckets/${google_logging_project_bucket_config.rm_log_bucket.bucket_id}"

  filter = "protoPayload.serviceName=cloudresourcemanager.googleapis.com"
  unique_writer_identity = true
}

# IAM binding for org/project sink to write to log bucket
resource "google_project_iam_binding" "log_bucket_writer_project" {
  count   = var.organization-id == "" ? 1 : 0
  project = data.google_project.project.project_id
  role    = "roles/logging.bucketWriter"

  members = [
    google_logging_project_sink.rm_logs_to_bucket[0].writer_identity
  ]
}

resource "google_project_iam_binding" "log_bucket_writer_org" {
  count   = var.organization-id == "" ? 1 : 0
  project = data.google_project.project.project_id
  role    = "roles/logging.bucketWriter"

  members = [
    google_logging_organization_sink.rm_logs_to_bucket[0].writer_identity
  ]
}

# Log Bucket → Pub/Sub Sink
resource "google_logging_project_sink" "logbucket_to_pubsub_sink" {
  name        = "rm-logbucket-to-pubsub"
  project     = data.google_project.project.project_id
  destination = "pubsub.googleapis.com/projects/${data.google_project.project.project_id}/topics/${var.topic-name}"
  filter = "protoPayload.serviceName=cloudresourcemanager.googleapis.com"
  log_bucket  = google_logging_project_bucket_config.rm_log_bucket.name
  unique_writer_identity = true
}

# IAM: Pub/Sub Publisher from bucket sink
resource "google_project_iam_binding" "logbucket_pubsub_publisher" {
  project = data.google_project.project.project_id
  role    = "roles/pubsub.publisher"

  members = [
    google_logging_project_sink.logbucket_to_pubsub_sink.writer_identity
  ]
}

# Outputs
output "An_output_message" {
  value = "Please copy the following values to Sentinel"
}

output "GCP_project_id" {
  value = data.google_project.project.project_id
}

output "GCP_project_number" {
  value = data.google_project.project.number
}

output "GCP_subscription_name" {
  value = google_pubsub_subscription.sentinel-subscription.name
}
