require "spec"
require "../../spec_helper"
require "../../support/db/test_database"

PERM = KemalcrStarter::Core::Rbac::Permission

repo = KemalcrStarter::Infrastructure::DB::RbacRepository.new(TestDatabase.database)
authz = KemalcrStarter::Core::Rbac::AuthorizationService.new(repo)

describe KemalcrStarter::Core::Rbac::AuthorizationService do
  before_each do
    TestDatabase.migrate!
    TestDatabase.truncate_all!
    authz.seed_default_roles!
  end

  describe "hierarchy invariants" do
    it "owner has all permissions" do
      KemalcrStarter::Core::Rbac::Permission.values.each do |p|
        authz.has_permission?("owner", p).should be_true
      end
    end

    it "admin cannot delete organizations" do
      authz.has_permission?("admin", KemalcrStarter::Core::Rbac::Permission::OrganizationDelete).should be_false
    end

    it "member can only list memberships" do
      authz.has_permission?("member", KemalcrStarter::Core::Rbac::Permission::OrganizationListMemberships).should be_true
      authz.has_permission?("member", KemalcrStarter::Core::Rbac::Permission::OrganizationUpdate).should be_false
      authz.has_permission?("member", KemalcrStarter::Core::Rbac::Permission::OrganizationInvite).should be_false
      authz.has_permission?("member", KemalcrStarter::Core::Rbac::Permission::ApiKeyCreate).should be_false
    end
  end

  describe "#has_permission?" do
    it "returns false for unknown role" do
      authz.has_permission?("unknown_role", KemalcrStarter::Core::Rbac::Permission::OrganizationUpdate).should be_false
    end

    it "returns true for allowed permission" do
      authz.has_permission?("owner", KemalcrStarter::Core::Rbac::Permission::OrganizationUpdate).should be_true
    end
  end

  describe "#roles_for_permission" do
    it "returns all roles that have the permission" do
      roles = authz.roles_for_permission(KemalcrStarter::Core::Rbac::Permission::OrganizationListMemberships)
      roles.should contain("owner")
      roles.should contain("admin")
      roles.should contain("member")
    end

    it "returns only owner+admin for management permissions" do
      roles = authz.roles_for_permission(KemalcrStarter::Core::Rbac::Permission::OrganizationInvite)
      roles.should contain("owner")
      roles.should contain("admin")
      roles.should_not contain("member")
    end
  end

  describe "#authorize!" do
    it "raises ForbiddenError when permission denied" do
      expect_raises(KemalcrStarter::Core::Errors::ForbiddenError) do
        authz.authorize!("any_id", "any_org", KemalcrStarter::Core::Rbac::Permission::OrganizationUpdate, role: "member")
      end
    end

    it "succeeds when permission granted" do
      authz.authorize!("any_id", "any_org", KemalcrStarter::Core::Rbac::Permission::OrganizationUpdate, role: "owner")
    end
  end

  describe "#seed_default_roles!" do
    it "populates rbac_role_permissions for all 3 roles" do
      owner_perms = repo.list_permissions_for_role("owner")
      admin_perms = repo.list_permissions_for_role("admin")
      member_perms = repo.list_permissions_for_role("member")

      owner_perms.size.should eq(8)
      admin_perms.size.should eq(7)
      member_perms.size.should eq(1)
    end
  end
end
