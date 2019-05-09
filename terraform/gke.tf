resource "random_string" "suffix" {
  length  = 4
  special = false
  upper   = false
}

locals {
  region       = "${var.region}"
  zones        = ["${var.zone}"]
  cluster_name = "artifactory-gke"

  network_name           = "my-private-network"
  subnet_name            = "my-private-subnet"
  subnet_ip_cidr         = "10.0.0.0/17"
  pods_ip_range_name     = "my-private-pods"
  pods_ip_cidr           = "192.168.0.0/18"
  services_ip_range_name = "my-private-services"
  services_ip_cidr       = "192.168.64.0/18"
  gke_master_ip_cidr     = "172.16.0.0/28"
}

module "kubernetes-engine" {
  source = "modules/private-cluster"

  project_id               = "${var.project_id}"
  name                     = "${local.cluster_name}"
  region                   = "${local.region}"
  zones                    = "${local.zones}"
  network                  = "${module.network.network_name}"
  subnetwork               = "${module.network.subnets_names[0]}"
  ip_range_pods            = "${local.pods_ip_range_name}"
  ip_range_services        = "${local.services_ip_range_name}"
  service_account          = "create"
  kubernetes_version       = "latest"
  node_version             = "latest"
  kubernetes_dashboard     = "false"
  monitoring_service       = "monitoring.googleapis.com/kubernetes"
  logging_service          = "logging.googleapis.com/kubernetes"
  network_policy           = true
  enable_istio             = true
  regional                 = false
  http_load_balancing      = false
  enable_private_endpoint  = false
  enable_private_nodes     = true
  remove_default_node_pool = true
  master_ipv4_cidr_block   = "${local.gke_master_ip_cidr}"

  master_authorized_networks_config = [{
    cidr_blocks = [
      {
        cidr_block   = "${local.subnet_ip_cidr}"
        display_name = "VPC"
      },
      {
        cidr_block   = "58.182.144.0/21"
        display_name = "StarHub Broadband"
      },
      {
        cidr_block   = "156.13.70.0/23"
        display_name = "ANZ Mobility Wifi"
      },
      {
        cidr_block   = "35.0.0.0/8"
        display_name = "GCP Public Cloudbuild"
      },
      {
        cidr_block   = "34.0.0.0/8"
        display_name = "GCP Public Cloudbuild"
      },
      {
        cidr_block   = "104.154.0.0/16"
        display_name = "GCP Public Cloudbuild"
      },
    ]
  }]

  node_pools = [
    {
      name               = "gke-node-pool"
      machine_type       = "n1-standard-2"
      min_count          = 1
      max_count          = 6
      disk_size_gb       = 100
      disk_type          = "pd-standard"
      image_type         = "COS"
      auto_repair        = true
      auto_upgrade       = true
      preemptible        = true
      initial_node_count = 1
    },
  ]

  node_pools_oauth_scopes = {
    all = []

    gke-node-pool = [
      "https://www.googleapis.com/auth/cloud-platform",
    ]
  }

  node_pools_labels = {
    all = {}

    gke-node-pool = {
      gke-node-pool = "true"
    }
  }

  node_pools_metadata = {
    all = {}

    gke-node-pool = {
      node-pool-metadata-custom-value = "my-node-pool"
    }
  }

  node_pools_taints = {
    all = []

    gke-node-pool = [
      {
        key    = "gke-node-pool"
        value  = "true"
        effect = "PREFER_NO_SCHEDULE"
      },
    ]
  }

  node_pools_tags = {
    all = []

    gke-node-pool = [
      "gke-node-pool",
    ]
  }
}
