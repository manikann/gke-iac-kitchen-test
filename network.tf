module "network" {
  source  = "terraform-google-modules/network/google"
  version = "0.6.0"

  project_id   = "${var.project_id}"
  network_name = "${local.network_name}"

  subnets = [
    {
      subnet_name           = "${local.subnet_name}"
      subnet_ip             = "${local.subnet_ip_cidr}"
      subnet_region         = "${local.region}"
      subnet_private_access = "true"
      subnet_flow_logs      = "true"
    },
  ]

  secondary_ranges = {
    "${local.subnet_name}" = [
      {
        range_name    = "${local.pods_ip_range_name}"
        ip_cidr_range = "${local.pods_ip_cidr}"
      },
      {
        range_name    = "${local.services_ip_range_name}"
        ip_cidr_range = "${local.services_ip_cidr}"
      },
    ]
  }
}

resource "google_compute_router" "router" {
  project = "${var.project_id}"
  name    = "router-${var.region}"
  region  = "${var.region}"
  network = "${module.network.network_self_link}"
}

resource "google_compute_address" "address" {
  project = "${var.project_id}"
  count   = 1
  name    = "nat-external-address-${count.index}"
  region  = "${var.region}"
}

resource "google_compute_router_nat" "nat-gw" {
  name                               = "nat-gw-${var.region}"
  project                            = "${var.project_id}"
  region                             = "${var.region}"
  router                             = "${google_compute_router.router.name}"
  nat_ip_allocate_option             = "MANUAL_ONLY"
  nat_ips                            = ["${google_compute_address.address.*.self_link}"]
  source_subnetwork_ip_ranges_to_nat = "LIST_OF_SUBNETWORKS"

  subnetwork {
    name                    = "${module.network.subnets_self_links[0]}"
    source_ip_ranges_to_nat = ["ALL_IP_RANGES"]
  }
}
