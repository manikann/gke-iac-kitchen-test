provider "google" {
  version = "~> 2.5"
  region  = "${var.region}"
  zone    = "${var.zone}"
}

provider "google-beta" {
  version = "~> 2.5"
  region  = "${var.region}"
  zone    = "${var.zone}"
}

data "google_client_config" "client" {}

data "google_project" "project" {
  project_id = "${var.project_id}"
}
