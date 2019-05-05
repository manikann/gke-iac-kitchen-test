output "project_id" {
  value = "${data.google_project.project.project_id}"
}

output "location" {
  value = "${module.kubernetes-engine.location}"
}

output "region" {
  value = "${module.kubernetes-engine.region}"
}

output "cluster_name" {
  value = "${module.kubernetes-engine.name}"
}
