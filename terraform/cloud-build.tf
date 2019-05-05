resource "google_project_iam_member" "cloudbuild-access-to-gke" {
  project = "${var.project_id}"
  role    = "roles/container.admin"
  member  = "serviceAccount:${data.google_project.project.number}@cloudbuild.gserviceaccount.com"
}

resource "google_project_iam_member" "cloudbuild-access-to-compute" {
  project = "${var.project_id}"
  role    = "roles/compute.networkViewer"
  member  = "serviceAccount:${data.google_project.project.number}@cloudbuild.gserviceaccount.com"
}
