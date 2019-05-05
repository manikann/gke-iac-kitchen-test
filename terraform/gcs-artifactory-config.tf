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

resource "google_storage_bucket_object" "access-password" {
  bucket = "${google_storage_bucket.artifactory_config.id}"
  name   = "access.password"
  source = "access.password"
}

resource "google_storage_bucket_object" "artifactory-license" {
  bucket = "${google_storage_bucket.artifactory_config.id}"
  name   = "artifactory-license.lic"
  source = "artifactory-license.lic"
}
