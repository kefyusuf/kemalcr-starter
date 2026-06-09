require "../../spec_helper"
require "../../support/db/test_database"
require "../../support/redis/test_redis"
require "json"

private def organizations_json_headers(token : String? = nil) : HTTP::Headers
  headers = HTTP::Headers{"Content-Type" => "application/json"}
  headers["Authorization"] = "Bearer #{token}" if token
  headers
end

private def seed_organization_fixtures(password : String = "supersecret") : Nil
  settings = KemalcrStarter::App.settings
  user_repository = KemalcrStarter::Infrastructure::DB::UserRepository.new(TestDatabase.database)
  organization_repository = KemalcrStarter::Infrastructure::DB::OrganizationRepository.new(TestDatabase.database)
  membership_repository = KemalcrStarter::Infrastructure::DB::OrganizationMembershipRepository.new(TestDatabase.database)
  hasher = KemalcrStarter::Infrastructure::Crypto::PasswordHasher.new(settings.password_pepper, settings.password_hash_cost)

  user_repository.create("usr_org_001", "orgs@example.com", "Owner", hasher.hash(password))
  user_repository.create("usr_org_002", "other@example.com", "Other", hasher.hash(password))
  user_repository.create("usr_org_003", "pending@example.com", "Pending", hasher.hash(password))
  user_repository.create("usr_org_004", "invitee@example.com", "Invitee", hasher.hash(password))
  organization_repository.create("org_list_001", "acme", "Acme Inc.", "usr_org_001")
  organization_repository.create("org_list_002", "globex", "Globex", "usr_org_002")
  membership_repository.create("mem_org_001", "org_list_001", "usr_org_001", "owner")
  membership_repository.create("mem_org_002", "org_list_002", "usr_org_001", "member")
  membership_repository.create("mem_org_003", "org_list_001", "usr_org_003", "member", status: "pending", invited_by_user_id: "usr_org_001")
end

private def login_for_organizations : JSON::Any
  post "/v1/auth/login", headers: organizations_json_headers, body: {
    email:    "orgs@example.com",
    password: "supersecret",
  }.to_json

  response.status_code.should eq 200
  JSON.parse(response.body)
end

private def login_for_organization_user(email : String, password : String = "supersecret") : JSON::Any
  post "/v1/auth/login", headers: organizations_json_headers, body: {
    email:    email,
    password: password,
  }.to_json

  response.status_code.should eq 200
  JSON.parse(response.body)
end

describe "Organizations endpoints" do
  before_each do
    TestDatabase.migrate!
    TestDatabase.truncate_all!
    TestRedis.clear!
    seed_organization_fixtures
  end

  it "lists organizations visible to the authenticated actor" do
    login_response = login_for_organizations
    access_token = login_response["access_token"].as_s

    get "/v1/organizations", headers: organizations_json_headers(access_token)

    response.status_code.should eq 200

    body = JSON.parse(response.body)
    organizations = body["data"].as_a
    organizations.size.should eq 2
    organizations.map(&.["id"].as_s).should contain "org_list_001"
    organizations.map(&.["id"].as_s).should contain "org_list_002"
  end

  it "creates an organization and owner membership in one request" do
    login_response = login_for_organizations
    access_token = login_response["access_token"].as_s

    post "/v1/organizations", headers: organizations_json_headers(access_token), body: {
      slug: "initech",
      name: "Initech",
    }.to_json

    response.status_code.should eq 201

    created = JSON.parse(response.body)
    created["slug"].as_s.should eq "initech"
    created_id = created["id"].as_s

    membership = KemalcrStarter::Infrastructure::DB::OrganizationMembershipRepository
      .new(TestDatabase.database)
      .find_active_for_user_and_organization("usr_org_001", created_id)

    membership.should_not be_nil
    membership.not_nil!.role.should eq "owner"
  end

  it "returns organization detail when the actor has membership" do
    login_response = login_for_organizations
    access_token = login_response["access_token"].as_s

    get "/v1/organizations/org_list_002", headers: organizations_json_headers(access_token)

    response.status_code.should eq 200

    body = JSON.parse(response.body)
    body["id"].as_s.should eq "org_list_002"
    body["slug"].as_s.should eq "globex"
  end

  it "updates organization detail when the actor is owner" do
    login_response = login_for_organizations
    access_token = login_response["access_token"].as_s

    patch "/v1/organizations/org_list_001", headers: organizations_json_headers(access_token), body: {
      slug: "acme-platform",
      name: "Acme Platform",
    }.to_json

    response.status_code.should eq 200

    body = JSON.parse(response.body)
    body["slug"].as_s.should eq "acme-platform"
    body["name"].as_s.should eq "Acme Platform"
  end

  it "rejects organization updates for non-admin members" do
    login_response = login_for_organizations
    access_token = login_response["access_token"].as_s

    patch "/v1/organizations/org_list_002", headers: organizations_json_headers(access_token), body: {
      name: "Globex Updated",
    }.to_json

    response.status_code.should eq 403
  end

  it "lists memberships for an organization the actor belongs to" do
    login_response = login_for_organizations
    access_token = login_response["access_token"].as_s

    get "/v1/organizations/org_list_002/memberships", headers: organizations_json_headers(access_token)

    response.status_code.should eq 200

    body = JSON.parse(response.body)
    memberships = body["data"].as_a
    memberships.size.should eq 1
    memberships.first["organization_id"].as_s.should eq "org_list_002"
    memberships.first["user_id"].as_s.should eq "usr_org_001"
  end

  it "rejects membership listing for organizations outside the actor scope" do
    login_response = login_for_organizations
    access_token = login_response["access_token"].as_s

    get "/v1/organizations/does_not_exist/memberships", headers: organizations_json_headers(access_token)

    response.status_code.should eq 403
  end

  it "lists pending invitations for an organization the actor manages" do
    login_response = login_for_organizations
    access_token = login_response["access_token"].as_s

    get "/v1/organizations/org_list_001/invitations", headers: organizations_json_headers(access_token)

    response.status_code.should eq 200

    body = JSON.parse(response.body)
    invitations = body["data"].as_a
    invitations.size.should eq 1
    invitations.first["email"].as_s.should eq "pending@example.com"
    invitations.first["status"].as_s.should eq "pending"
  end

  it "creates a pending invitation when the actor can manage the organization" do
    login_response = login_for_organizations
    access_token = login_response["access_token"].as_s

    post "/v1/organizations/org_list_001/invitations", headers: organizations_json_headers(access_token), body: {
      email: "invitee@example.com",
      role:  "admin",
    }.to_json

    response.status_code.should eq 201

    body = JSON.parse(response.body)
    body["email"].as_s.should eq "invitee@example.com"
    body["role"].as_s.should eq "admin"
    body["status"].as_s.should eq "pending"
  end

  it "rejects invitation creation for actors who cannot manage the organization" do
    login_response = login_for_organizations
    access_token = login_response["access_token"].as_s

    post "/v1/organizations/org_list_002/invitations", headers: organizations_json_headers(access_token), body: {
      email: "invitee@example.com",
      role:  "member",
    }.to_json

    response.status_code.should eq 403
  end

  it "accepts a pending invitation for the invited actor" do
    login_response = login_for_organization_user("pending@example.com")
    access_token = login_response["access_token"].as_s

    post "/v1/organizations/org_list_001/invitations/mem_org_003/accept", headers: organizations_json_headers(access_token)

    response.status_code.should eq 200

    body = JSON.parse(response.body)
    body["status"].as_s.should eq "active"
    body["organization_id"].as_s.should eq "org_list_001"

    get "/v1/organizations", headers: organizations_json_headers(access_token)

    response.status_code.should eq 200
    organizations = JSON.parse(response.body)["data"].as_a
    organizations.map(&.["id"].as_s).should contain "org_list_001"
  end

  it "rejects invitation acceptance for a different actor" do
    login_response = login_for_organizations
    access_token = login_response["access_token"].as_s

    post "/v1/organizations/org_list_001/invitations/mem_org_003/accept", headers: organizations_json_headers(access_token)

    response.status_code.should eq 403
  end

  it "revokes a pending invitation when the actor can manage the organization" do
    login_response = login_for_organizations
    access_token = login_response["access_token"].as_s

    delete "/v1/organizations/org_list_001/invitations/mem_org_003", headers: organizations_json_headers(access_token)

    response.status_code.should eq 204

    get "/v1/organizations/org_list_001/invitations", headers: organizations_json_headers(access_token)

    response.status_code.should eq 200
    JSON.parse(response.body)["data"].as_a.size.should eq 0
  end
end
