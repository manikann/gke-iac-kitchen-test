# encoding: utf-8
# copyright: 2018, The Authors

project_id = attribute('project_id')
location = attribute('location')
cluster_name = attribute('cluster_name')

control "gke" do
  describe google_container_cluster(project: project_id, zone: location, name: cluster_name) do
    it { should exist }
    its('zone') { should cmp location }
    its('location') { should cmp location }
    its('addons_config.http_load_balancing.disabled') { should eq true }
    its('addons_config.kubernetes_dashboard.disabled') { should eq true }
  end
end