module KemalcrStarter
  module Core
    module Rbac
      enum Permission : UInt32
        OrganizationUpdate
        OrganizationInvite
        OrganizationRevoke
        OrganizationDelete
        OrganizationListMemberships
        OrganizationListInvitations
        ApiKeyCreate
        ApiKeyRevoke
        WebhookManage
        ProductManage
        ProductList

        def to_s : String
          case self
          when OrganizationUpdate          then "organization:update"
          when OrganizationInvite          then "organization:invite"
          when OrganizationRevoke          then "organization:revoke_invitation"
          when OrganizationDelete          then "organization:delete"
          when OrganizationListMemberships then "organization:list_memberships"
          when OrganizationListInvitations then "organization:list_invitations"
          when ApiKeyCreate                then "api_key:create"
          when ApiKeyRevoke                then "api_key:revoke"
          when WebhookManage               then "webhook:manage"
          when ProductManage               then "product:manage"
          when ProductList                 then "product:list"
          else                                  "unknown"
          end
        end

        def self.from_s(value : String) : Permission
          case value
          when "organization:update"            then OrganizationUpdate
          when "organization:invite"            then OrganizationInvite
          when "organization:revoke_invitation" then OrganizationRevoke
          when "organization:delete"            then OrganizationDelete
          when "organization:list_memberships"  then OrganizationListMemberships
          when "organization:list_invitations"  then OrganizationListInvitations
          when "api_key:create"                 then ApiKeyCreate
          when "api_key:revoke"                 then ApiKeyRevoke
          when "webhook:manage"                 then WebhookManage
          when "product:manage"                 then ProductManage
          when "product:list"                   then ProductList
          else                                       raise "Unknown permission: #{value}"
          end
        end
      end
    end
  end
end
