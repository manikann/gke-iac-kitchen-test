# encoding: utf-8
# copyright: 2018, The Authors

project_id = attribute('project_id')

control "active-project" do
  describe google_project(project: project_id) do
    it {should exist}
    its('lifecycle_state') {should eq "ACTIVE"}
  end
end