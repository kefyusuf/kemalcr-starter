require "../../spec_helper"

describe KemalcrStarter::Infrastructure::Crypto::PasswordHasher do
  hasher = KemalcrStarter::Infrastructure::Crypto::PasswordHasher.new("test-pepper", 4)

  it "hashes and verifies a password" do
    digest = hasher.hash("mySecret123")
    hasher.verify("mySecret123", digest).should be_true
  end

  it "rejects wrong password" do
    digest = hasher.hash("correctPassword1")
    hasher.verify("wrongPassword1", digest).should be_false
  end

  it "produces different digests for same password" do
    digest1 = hasher.hash("samePass1")
    digest2 = hasher.hash("samePass1")
    digest1.should_not eq digest2
  end

  it "handles empty password" do
    digest = hasher.hash("")
    hasher.verify("", digest).should be_true
  end

  it "handles special characters" do
    digest = hasher.hash("P@$$w0rd!ğüş")
    hasher.verify("P@$$w0rd!ğüş", digest).should be_true
  end

  it "returns false for malformed digest" do
    hasher.verify("password1", "invalid-digest").should be_false
  end
end
