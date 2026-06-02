require "spec"
require "../../spec_helper"

describe KemalcrStarter::Core::Rbac::Permission do
  describe "enum values" do
    it "has OrganizationUpdate" do
      KemalcrStarter::Core::Rbac::Permission::OrganizationUpdate.to_s.should eq("organization:update")
    end

    it "has OrganizationInvite" do
      KemalcrStarter::Core::Rbac::Permission::OrganizationInvite.to_s.should eq("organization:invite")
    end

    it "has OrganizationRevoke" do
      KemalcrStarter::Core::Rbac::Permission::OrganizationRevoke.to_s.should eq("organization:revoke_invitation")
    end

    it "has OrganizationDelete" do
      KemalcrStarter::Core::Rbac::Permission::OrganizationDelete.to_s.should eq("organization:delete")
    end

    it "has OrganizationListMemberships" do
      KemalcrStarter::Core::Rbac::Permission::OrganizationListMemberships.to_s.should eq("organization:list_memberships")
    end

    it "has OrganizationListInvitations" do
      KemalcrStarter::Core::Rbac::Permission::OrganizationListInvitations.to_s.should eq("organization:list_invitations")
    end

    it "has ApiKeyCreate" do
      KemalcrStarter::Core::Rbac::Permission::ApiKeyCreate.to_s.should eq("api_key:create")
    end

    it "has ApiKeyRevoke" do
      KemalcrStarter::Core::Rbac::Permission::ApiKeyRevoke.to_s.should eq("api_key:revoke")
    end
  end

  describe "from_s" do
    it "parses valid permission string" do
      p = KemalcrStarter::Core::Rbac::Permission.from_s("organization:update")
      p.should eq(KemalcrStarter::Core::Rbac::Permission::OrganizationUpdate)
    end

    it "raises on invalid permission string" do
      expect_raises(Exception) do
        KemalcrStarter::Core::Rbac::Permission.from_s("invalid:permission")
      end
    end
  end
end
