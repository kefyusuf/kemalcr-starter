require "../../spec_helper"
require "../../support/db/test_database"
require "../../support/redis/test_redis"
require "digest/sha256"
require "json"

private def invitation_idempotency_headers(token : String, key : String) : HTTP::Headers
  HTTP::Headers{
    "Content-Type"    => "application/json",
    "Authorization"   => "Bearer #{token}",
    "Idempotency-Key" => key,
  }
end

private def invitation_json_headers : HTTP::Headers
  HTTP::Headers{"Content-Type" => "application/json"}
end

private def seed_idempotent_invitation_fixtures(password : String = "supersecret") : Nil
  settings = KemalcrStarter::App.settings
  user_repository = KemalcrStarter::Infrastructure::DB::UserRepository.new(TestDatabase.database)
  organization_repository = KemalcrStarter::Infrastructure::DB::OrganizationRepository.new(TestDatabase.database)
  membership_repository = KemalcrStarter::Infrastructure::DB::OrganizationMembershipRepository.new(TestDatabase.database)
  hasher = KemalcrStarter::Infrastructure::Crypto::PasswordHasher.new(settings.password_pepper, settings.password_hash_cost)

  user_repository.create("usr_org_001", "orgs@example.com", "Owner", hasher.hash(password))
  user_repository.create("usr_org_002", "invitee@example.com", "Invitee", hasher.hash(password))
  organization_repository.create("org_list_001", "acme", "Acme Inc.", "usr_org_001")
  membership_repository.create("mem_org_001", "org_list_001", "usr_org_001", "owner")
end

private def login_for_idempotent_invitations : JSON::Any
  post "/v1/auth/login", headers: invitation_json_headers, body: {
    email:    "orgs@example.com",
    password: "supersecret",
  }.to_json

  response.status_code.should eq 200
  JSON.parse(response.body)
end

private def invitation_idempotency_scope(actor_id : String) : String
  "#{actor_id}:POST:/v1/organizations/:organization_id/invitations"
end

private def invitation_idempotency_fingerprint(actor_id : String, request_body : String) : String
  normalized_body = JSON.parse(request_body).to_json
  Digest::SHA256.hexdigest(["POST", "/v1/organizations/:organization_id/invitations", actor_id, normalized_body].join(":"))
end

describe "Organization invitation create idempotency" do
  before_each do
    TestDatabase.migrate!
    TestDatabase.truncate_all!
    TestRedis.clear!
    seed_idempotent_invitation_fixtures
  end

  it "replays the previous invitation response for the same key and payload" do
    login_response = login_for_idempotent_invitations
    access_token = login_response["access_token"].as_s
    request_body = {email: "invitee@example.com", role: "member"}.to_json

    post "/v1/organizations/org_list_001/invitations", headers: invitation_idempotency_headers(access_token, "invite-create-1"), body: request_body

    response.status_code.should eq 201
    first = JSON.parse(response.body)

    post "/v1/organizations/org_list_001/invitations", headers: invitation_idempotency_headers(access_token, "invite-create-1"), body: request_body

    response.status_code.should eq 201
    replay = JSON.parse(response.body)
    replay["id"].as_s.should eq first["id"].as_s

    invitations = KemalcrStarter::Infrastructure::DB::OrganizationMembershipRepository
      .new(TestDatabase.database)
      .list_pending_for_organization("org_list_001")

    invitations.size.should eq 1
  end

  it "returns conflict for the same invitation key with a different payload" do
    login_response = login_for_idempotent_invitations
    access_token = login_response["access_token"].as_s

    post "/v1/organizations/org_list_001/invitations", headers: invitation_idempotency_headers(access_token, "invite-create-2"), body: {
      email: "invitee@example.com",
      role:  "member",
    }.to_json

    response.status_code.should eq 201

    post "/v1/organizations/org_list_001/invitations", headers: invitation_idempotency_headers(access_token, "invite-create-2"), body: {
      email: "invitee@example.com",
      role:  "admin",
    }.to_json

    response.status_code.should eq 409
  end

  it "returns conflict while the invitation request is already in progress" do
    login_response = login_for_idempotent_invitations
    access_token = login_response["access_token"].as_s
    request_body = {email: "invitee@example.com", role: "member"}.to_json

    KemalcrStarter::Infrastructure::DB::IdempotencyKeyRepository
      .new(TestDatabase.database)
      .create(
        "idem_inflight_invite_001",
        invitation_idempotency_scope("usr_org_001"),
        "invite-create-3",
        invitation_idempotency_fingerprint("usr_org_001", request_body),
        Time.utc + 30.seconds
      )

    post "/v1/organizations/org_list_001/invitations", headers: invitation_idempotency_headers(access_token, "invite-create-3"), body: request_body

    response.status_code.should eq 409
  end
end
