module "zonal-private-cluster" {
  source     = "../../.."
  project_id = "${var.project_id}"
  zone       = "${var.zone}"
  region     = "${var.region}"
}
