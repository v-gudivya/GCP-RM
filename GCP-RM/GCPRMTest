provider "google" {
  project = var.log_sink_project_id
}

variable "org_id" {
  description = "Your GCP Organization ID"
  type        = string
}

variable "log_sink_project_id" {
  description = "Project ID where Pub/Sub topic exists"
  type        = string
}

variable "pubsub_topic_name" {
  description = "Name of the Pub/Sub topic to send logs to"
  type        = string
}

resource "google_pubsub_topic" "log_topic" {
  name     = var.pubsub_topic_name
  project  = var.log_sink_project_id
}

resource "google_logging_organization_sink" "resource_manager_sink" {
  name             = "resource-manager-aggregated-sink"
  org_id           = var.org_id
  destination      = "pubsub.googleapis.com/projects/${var.log_sink_project_id}/topics/${google_pubsub_topic.log_topic.name}"
  include_children = true
  filter           = "protoPayload.serviceName=\"cloudresourcemanager.googleapis.com\""

  # This allows Cloud Logging to publish to Pub/Sub
  unique_writer_identity = true
}

# Grant writer identity permission to publish to Pub/Sub
resource "google_pubsub_topic_iam_binding" "sink_writer" {
  topic = google_pubsub_topic.log_topic.name
  role  = "roles/pubsub.publisher"

  members = [
    google_logging_organization_sink.resource_manager_sink.writer_identity,
  ]
}
