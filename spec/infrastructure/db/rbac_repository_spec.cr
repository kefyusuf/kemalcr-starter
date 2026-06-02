require "spec"
require "../../spec_helper"
require "../../support/db/test_database"

describe KemalcrStarter::Infrastructure::DB::RbacRepository do
  repo = KemalcrStarter::Infrastructure::DB::RbacRepository.new(TestDatabase.database)

  before_each do
    TestDatabase.migrate!
    TestDatabase.truncate_all!
  end

  describe "#assign_permission" do
    it "assigns a permission to a role" do
      repo.assign_permission("owner", KemalcrStarter::Core::Rbac::Permission::OrganizationUpdate)
      repo.role_has_permission?("owner", KemalcrStarter::Core::Rbac::Permission::OrganizationUpdate).should be_true
    end

    it "is idempotent" do
      repo.assign_permission("owner", KemalcrStarter::Core::Rbac::Permission::OrganizationUpdate)
      repo.assign_permission("owner", KemalcrStarter::Core::Rbac::Permission::OrganizationUpdate)
      repo.list_permissions_for_role("owner").size.should eq(1)
    end
  end

  describe "#remove_permission" do
    it "removes a permission from a role" do
      repo.assign_permission("admin", KemalcrStarter::Core::Rbac::Permission::OrganizationInvite)
      repo.remove_permission("admin", KemalcrStarter::Core::Rbac::Permission::OrganizationInvite)
      repo.role_has_permission?("admin", KemalcrStarter::Core::Rbac::Permission::OrganizationInvite).should be_false
    end
  end

  describe "#list_permissions_for_role" do
    it "returns empty list for unknown role" do
      repo.list_permissions_for_role("unknown").should be_empty
    end

    it "lists all permissions for a role" do
      repo.assign_permission("member", KemalcrStarter::Core::Rbac::Permission::OrganizationListMemberships)
      perms = repo.list_permissions_for_role("member")
      perms.should eq(["organization:list_memberships"])
    end
  end

  describe "#seed_role" do
    it "assigns multiple permissions at once" do
      repo.seed_role("admin", [KemalcrStarter::Core::Rbac::Permission::OrganizationUpdate, KemalcrStarter::Core::Rbac::Permission::OrganizationInvite])
      perms = repo.list_permissions_for_role("admin")
      perms.size.should eq(2)
    end

    it "is idempotent with mixed new and existing" do
      repo.assign_permission("admin", KemalcrStarter::Core::Rbac::Permission::OrganizationUpdate)
      repo.seed_role("admin", [KemalcrStarter::Core::Rbac::Permission::OrganizationUpdate, KemalcrStarter::Core::Rbac::Permission::OrganizationInvite])
      perms = repo.list_permissions_for_role("admin")
      perms.size.should eq(2)
    end
  end

  describe "#clear_role" do
    it "removes all permissions from a role" do
      repo.seed_role("admin", [KemalcrStarter::Core::Rbac::Permission::OrganizationUpdate, KemalcrStarter::Core::Rbac::Permission::OrganizationInvite])
      repo.clear_role("admin")
      repo.list_permissions_for_role("admin").should be_empty
    end
  end

  describe "#role_has_permission?" do
    it "returns false for unassigned permission" do
      repo.role_has_permission?("owner", KemalcrStarter::Core::Rbac::Permission::OrganizationUpdate).should be_false
    end

    it "returns false for unknown role" do
      repo.role_has_permission?("nonexistent", KemalcrStarter::Core::Rbac::Permission::OrganizationUpdate).should be_false
    end
  end
end
