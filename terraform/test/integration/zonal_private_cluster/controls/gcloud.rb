# encoding: utf-8
# copyright: 2018, The Authors

require 'rubygems'
require 'ipaddress'

project_id = attribute('project_id')
location = attribute('location')
cluster_name = attribute('cluster_name')

allowed_ipcidrs = [
    IPAddress('58.182.144.0/22'),
    IPAddress('10.0.0.0/16')
]

control "gcloud" do
  title "Google Compute Engine GKE configuration"

  gcloudcli = command("gcloud --project=#{project_id} container clusters --zone=#{location} describe #{cluster_name} --format=json")
  gke = gcloudcli.exit_status == 0 ? JSON.parse(gcloudcli.stdout) : {}

  # Using inspec style 'should'
  # describe-context-it-should
  describe gcloudcli do
    its('exit_status') { should eq 0 }
  end

  describe json(content: gcloudcli.stdout) do
    its(['status']) { should cmp "RUNNING" }
  end

  # Using rspec style 'expect'
  describe 'gke-cluster' do
    it 'able to describe using gcloud CLI' do
      expect(gcloudcli.exit_status).to eq 0
    end

    it 'status should be running' do
      expect(gke['status']).to eq 'RUNNING'
    end

    it 'http load balancing addon should be disabled' do
      expect(gke['addonsConfig']['httpLoadBalancing']['disabled']).to eq true
    end

    it 'kubernetes dashboard addon should be disabled' do
      expect(gke['addonsConfig']['kubernetesDashboard']['disabled']).to eq true
    end

    it 'network policy addon should be enabled' do
      expect(gke['addonsConfig']['networkPolicyConfig']).to include("disabled" => false) | be_empty
    end

    it 'pod ip range should be configured' do
      expect(gke['ipAllocationPolicy']['clusterSecondaryRangeName']).not_to be_empty
    end

    it 'services ip range should be configured' do
      expect(gke['ipAllocationPolicy']['servicesSecondaryRangeName']).not_to be_empty
    end

    it 'uses ip alias' do
      expect(gke['ipAllocationPolicy']['useIpAliases']).to eq true
    end

    it 'legacy ABAC should be disabled' do
      expect(gke['legacyAbac']).to be_empty
    end

    it 'legacy Master auth (username/password or client certificate) should be disabled' do
      expect(gke['masterAuth'].reject { |p| p == 'clusterCaCertificate' }).to be_empty
    end

    it 'master authorized network list should be allowed' do
      expect( gke['masterAuthorizedNetworksConfig']['cidrBlocks'].reject { |c|
            !allowed_ipcidrs.select { |wip| wip.include_all?(IPAddress(c['cidrBlock'])) }.empty? }).to be_empty
    end
  end

end