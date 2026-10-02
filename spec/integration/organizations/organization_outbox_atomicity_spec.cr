require "../../spec_helper"
require "../../support/db/test_database"

private def atomic_organization_service(with_repository : Bool = true)
  outbox = with_repository ? KemalcrStarter::Infrastructure::DB::OutboxEventRepository.new(TestDatabase.database) : nil
  rbac = KemalcrStarter::Core::Rbac::AuthorizationService.new(KemalcrStarter::Infrastructure::DB::RbacRepository.new(TestDatabase.database))
  KemalcrStarter::Modules::Organizations::OrganizationService.new(TestDatabase.database, outbox, rbac)
end

private def seed_atomic_organization : Nil
  KemalcrStarter::Infrastructure::DB::OrganizationRepository.new(TestDatabase.database)
    .create("org_atomic", "atomic", "Original", "usr_owner")
  KemalcrStarter::Infrastructure::DB::OrganizationMembershipRepository.new(TestDatabase.database)
    .create("mem_owner", "org_atomic", "usr_owner", "owner", joined_at: Time.utc)
end

private def seed_atomic_invitation : Nil
  seed_atomic_organization
  KemalcrStarter::Infrastructure::DB::OrganizationMembershipRepository.new(TestDatabase.database)
    .create("mem_invited", "org_atomic", "usr_invitee", "member", status: "pending", invited_by_user_id: "usr_owner")
end

private def reject_organization_events! : Nil
  TestDatabase.database.exec <<-SQL
    ALTER TABLE outbox_events ADD CONSTRAINT spec_reject_organization_events
    CHECK (event_type NOT LIKE 'organization.%')
  SQL
end

private def organization_event_count : Int64
  TestDatabase.database.scalar("SELECT COUNT(*) FROM outbox_events").as(Int64)
end

describe "Organization mutation and outbox atomicity" do
  before_each do
    TestDatabase.migrate!
    TestDatabase.truncate_all!
    users = KemalcrStarter::Infrastructure::DB::UserRepository.new(TestDatabase.database)
    users.create("usr_owner", "owner@example.com", "Owner", "unused")
    users.create("usr_invitee", "invitee@example.com", "Invitee", "unused")
    users.create("usr_other", "other@example.com", "Other", "unused")
  end

  after_each do
    TestDatabase.database.exec "ALTER TABLE outbox_events DROP CONSTRAINT IF EXISTS spec_reject_organization_events"
  end

  it "rolls back the organization and owner membership when its event is rejected" do
    reject_organization_events!
    expect_raises(::PQ::PQError, /spec_reject_organization_events/) do
      atomic_organization_service.create_for_actor("usr_owner", "new", "New")
    end
    TestDatabase.database.scalar("SELECT COUNT(*) FROM organizations").as(Int64).should eq 0
    TestDatabase.database.scalar("SELECT COUNT(*) FROM organization_memberships").as(Int64).should eq 0
    organization_event_count.should eq 0
  end

  it "restores organization fields and timestamp when its update event is rejected" do
    seed_atomic_organization
    timestamp = TestDatabase.database.scalar("SELECT updated_at FROM organizations WHERE id = 'org_atomic'").as(Time)
    reject_organization_events!
    expect_raises(::PQ::PQError, /spec_reject_organization_events/) do
      atomic_organization_service.update_for_actor("usr_owner", "org_atomic", "changed", "Changed")
    end
    stored = KemalcrStarter::Infrastructure::DB::OrganizationRepository.new(TestDatabase.database).find("org_atomic").not_nil!
    stored.slug.should eq "atomic"
    stored.name.should eq "Original"
    TestDatabase.database.scalar("SELECT updated_at FROM organizations WHERE id = 'org_atomic'").as(Time).should eq timestamp
    organization_event_count.should eq 0
  end

  it "rolls back a pending invitation when its event is rejected" do
    seed_atomic_organization
    reject_organization_events!
    expect_raises(::PQ::PQError, /spec_reject_organization_events/) do
      atomic_organization_service.invite_user_for_actor("usr_owner", "org_atomic", "invitee@example.com", "member")
    end
    TestDatabase.database.scalar("SELECT COUNT(*) FROM organization_memberships WHERE user_id = 'usr_invitee'").as(Int64).should eq 0
    organization_event_count.should eq 0
  end

  it "restores pending status and a null joined_at when acceptance event is rejected" do
    seed_atomic_invitation
    timestamp = TestDatabase.database.scalar("SELECT updated_at FROM organization_memberships WHERE id = 'mem_invited'").as(Time)
    reject_organization_events!
    expect_raises(::PQ::PQError, /spec_reject_organization_events/) do
      atomic_organization_service.accept_invitation_for_actor("usr_invitee", "org_atomic", "mem_invited")
    end
    TestDatabase.database.scalar("SELECT status FROM organization_memberships WHERE id = 'mem_invited'").as(String).should eq "pending"
    TestDatabase.database.scalar("SELECT joined_at IS NULL FROM organization_memberships WHERE id = 'mem_invited'").as(Bool).should be_true
    TestDatabase.database.scalar("SELECT updated_at FROM organization_memberships WHERE id = 'mem_invited'").as(Time).should eq timestamp
    organization_event_count.should eq 0
  end

  it "restores a pending invitation when revocation event is rejected" do
    seed_atomic_invitation
    timestamp = TestDatabase.database.scalar("SELECT updated_at FROM organization_memberships WHERE id = 'mem_invited'").as(Time)
    reject_organization_events!
    expect_raises(::PQ::PQError, /spec_reject_organization_events/) do
      atomic_organization_service.revoke_invitation_for_actor("usr_owner", "org_atomic", "mem_invited")
    end
    TestDatabase.database.scalar("SELECT status FROM organization_memberships WHERE id = 'mem_invited'").as(String).should eq "pending"
    TestDatabase.database.scalar("SELECT updated_at FROM organization_memberships WHERE id = 'mem_invited'").as(Time).should eq timestamp
    organization_event_count.should eq 0
  end

  it "commits all five event types without explicitly injecting an outbox repository" do
    service = atomic_organization_service(with_repository: false)
    organization = service.create_for_actor("usr_owner", "  NEW Org  ", "  New  ")
    organization[:slug].should eq "new-org"
    organization[:name].should eq "New"
    org_id = organization[:id]
    service.update_for_actor("usr_owner", org_id, nil, "Changed")[:name].should eq "Changed"
    invited = service.invite_user_for_actor("usr_owner", org_id, " INVITEE@example.com ", " MEMBER ")
    accepted = service.accept_invitation_for_actor("usr_invitee", org_id, invited[:id])
    accepted[:status].should eq "active"
    TestDatabase.database.scalar("SELECT joined_at IS NOT NULL FROM organization_memberships WHERE id = $1", invited[:id]).as(Bool).should be_true
    revoked = service.invite_user_for_actor("usr_owner", org_id, "other@example.com", "admin")
    service.revoke_invitation_for_actor("usr_owner", org_id, revoked[:id])
    TestDatabase.database.scalar("SELECT status FROM organization_memberships WHERE id = $1", revoked[:id]).as(String).should eq "revoked"

    events = TestDatabase.database.query_all("SELECT event_type, aggregate_type, aggregate_id, event_data::text, status FROM outbox_events") do |rs|
      {event_type: rs.read(String), aggregate_type: rs.read(String), aggregate_id: rs.read(String), event_data: rs.read(String), status: rs.read(String)}
    end
    events.size.should eq 6
    expected_ids = {
      "organization.created"             => org_id,
      "organization.updated"             => org_id,
      "organization.membership.accepted" => invited[:id],
      "organization.membership.revoked"  => revoked[:id],
    }
    expected_ids.each do |type, id|
      event = events.find { |entry| entry[:event_type] == type }.not_nil!
      event[:aggregate_id].should eq id
    end
    created = events.find { |entry| entry[:event_type] == "organization.created" }.not_nil!
    JSON.parse(created[:event_data])["name"].as_s.should eq "New"
    JSON.parse(created[:event_data])["owner_id"].as_s.should eq "usr_owner"
    invitations = events.select { |entry| entry[:event_type] == "organization.membership.invited" }
    invitations.size.should eq 2
    invitation = invitations.find { |entry| entry[:aggregate_id] == invited[:id] }.not_nil!
    JSON.parse(invitation[:event_data])["invited_email"].as_s.should eq "invitee@example.com"
    JSON.parse(invitation[:event_data])["role"].as_s.should eq "member"
    events.each do |event|
      event[:status].should eq "pending"
      if event[:aggregate_type] == "membership"
        JSON.parse(event[:event_data])["organization_id"].as_s.should eq org_id
      end
    end
  end

  it "leaves state and outbox unchanged for forbidden actors and mismatched invitations" do
    seed_atomic_invitation
    service = atomic_organization_service
    expect_raises(KemalcrStarter::Core::Errors::ForbiddenError) { service.update_for_actor("usr_other", "org_atomic", nil, "Changed") }
    expect_raises(KemalcrStarter::Core::Errors::ForbiddenError) { service.invite_user_for_actor("usr_other", "org_atomic", "other@example.com", "member") }
    expect_raises(KemalcrStarter::Core::Errors::ForbiddenError) { service.accept_invitation_for_actor("usr_other", "org_atomic", "mem_invited") }
    expect_raises(KemalcrStarter::Core::Errors::ForbiddenError) { service.accept_invitation_for_actor("usr_invitee", "org_other", "mem_invited") }
    expect_raises(KemalcrStarter::Core::Errors::ForbiddenError) { service.revoke_invitation_for_actor("usr_owner", "org_atomic", "missing") }
    expect_raises(KemalcrStarter::Core::Errors::ForbiddenError) { service.revoke_invitation_for_actor("usr_other", "org_atomic", "mem_invited") }
    TestDatabase.database.scalar("SELECT name FROM organizations WHERE id = 'org_atomic'").as(String).should eq "Original"
    TestDatabase.database.scalar("SELECT status FROM organization_memberships WHERE id = 'mem_invited'").as(String).should eq "pending"
    organization_event_count.should eq 0
  end

  it "does not emit events for invalid input or an already accepted invitation" do
    seed_atomic_invitation
    service = atomic_organization_service
    expect_raises(KemalcrStarter::Core::Errors::ValidationError) { service.create_for_actor("usr_owner", "---", "Invalid") }
    expect_raises(KemalcrStarter::Core::Errors::ValidationError) { service.update_for_actor("usr_owner", "org_atomic", nil, " ") }
    expect_raises(KemalcrStarter::Core::Errors::ValidationError) { service.invite_user_for_actor("usr_owner", "org_atomic", "other@example.com", "owner") }
    expect_raises(KemalcrStarter::Core::Errors::ValidationError) { service.invite_user_for_actor("usr_owner", "org_atomic", "missing@example.com", "member") }
    KemalcrStarter::Infrastructure::DB::OrganizationMembershipRepository.new(TestDatabase.database).update_status("mem_invited", "active", Time.utc)
    expect_raises(KemalcrStarter::Core::Errors::ForbiddenError) { service.accept_invitation_for_actor("usr_invitee", "org_atomic", "mem_invited") }
    expect_raises(KemalcrStarter::Core::Errors::ForbiddenError) { service.revoke_invitation_for_actor("usr_owner", "org_atomic", "mem_invited") }
    organization_event_count.should eq 0
  end

  it "does not emit orphan events for duplicate organization or invitation writes" do
    seed_atomic_invitation
    service = atomic_organization_service
    expect_raises(::PQ::PQError) { service.create_for_actor("usr_owner", "atomic", "Duplicate") }
    expect_raises(::PQ::PQError) { service.invite_user_for_actor("usr_owner", "org_atomic", "invitee@example.com", "member") }
    TestDatabase.database.scalar("SELECT COUNT(*) FROM organizations").as(Int64).should eq 1
    TestDatabase.database.scalar("SELECT COUNT(*) FROM organization_memberships").as(Int64).should eq 2
    organization_event_count.should eq 0
  end
end
