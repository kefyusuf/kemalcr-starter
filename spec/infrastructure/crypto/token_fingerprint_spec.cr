require "../../spec_helper"

describe KemalcrStarter::Infrastructure::Crypto::TokenFingerprint do
  hasher = KemalcrStarter::Infrastructure::Crypto::TokenFingerprint.new("test-pepper")

  it "produces a digest" do
    fingerprint = hasher.digest("some-token-value")
    fingerprint.should_not be_nil
    fingerprint.size.should be > 0
  end

  it "is deterministic" do
    f1 = hasher.digest("token-123")
    f2 = hasher.digest("token-123")
    f1.should eq f2
  end

  it "produces different digests for different tokens" do
    f1 = hasher.digest("token-abc")
    f2 = hasher.digest("token-xyz")
    f1.should_not eq f2
  end

  it "handles empty token" do
    fingerprint = hasher.digest("")
    fingerprint.should_not be_nil
  end
end
