resource "google_storage_bucket" "artifactory_config" {
  project       = "${var.project_id}"
  name          = "${var.project_id}-artifactory-config"
  location      = "${var.region}"
  storage_class = "REGIONAL"
  force_destroy = "true"
}

resource "google_storage_bucket_object" "copy-master-key" {
  bucket = "${google_storage_bucket.artifactory_config.id}"
  name   = "master.key"
  source = "master.key"
}

resource "google_storage_bucket_object" "db-password" {
  bucket = "${google_storage_bucket.artifactory_config.id}"
  name   = "db.password"
  source = "db.password"
}

resource "google_storage_bucket_object" "admin-password" {
  bucket = "${google_storage_bucket.artifactory_config.id}"
  name   = "admin.password"
  source = "admin.password"
}

resource "google_storage_bucket_object" "access-password" {
  bucket = "${google_storage_bucket.artifactory_config.id}"
  name   = "access.password"
  source = "access.password"
}

resource "google_storage_bucket_object" "artifactory-cluster-license" {
  bucket = "${google_storage_bucket.artifactory_config.id}"
  name   = "artifactory-cluster.lic"
  source = "artifactory-cluster.lic"
}

resource "google_storage_bucket_object" "artifactory-edge-license" {
  bucket = "${google_storage_bucket.artifactory_config.id}"
  name   = "artifactory-edge.lic"
  source = "artifactory-edge.lic"
}
