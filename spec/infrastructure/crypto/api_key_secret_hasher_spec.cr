require "../../spec_helper"

describe KemalcrStarter::Infrastructure::Crypto::ApiKeySecretHasher do
  hasher = KemalcrStarter::Infrastructure::Crypto::ApiKeySecretHasher.new("test-pepper")

  it "generates a secret" do
    secret = hasher.generate_secret
    secret.should_not be_nil
    secret.size.should be > 0
  end

  it "extracts prefix from secret" do
    secret = hasher.generate_secret
    prefix = hasher.prefix(secret)
    prefix.size.should eq 12
    secret.starts_with?(prefix).should be_true
  end

  it "hashes and verifies a secret" do
    secret = hasher.generate_secret
    hash = hasher.hash(secret)
    hasher.verify(secret, hash).should be_true
  end

  it "rejects wrong secret" do
    secret = hasher.generate_secret
    hash = hasher.hash(secret)
    hasher.verify("wrong-secret-value", hash).should be_false
  end

  it "produces deterministic hashes for same secret" do
    secret = hasher.generate_secret
    hash1 = hasher.hash(secret)
    hash2 = hasher.hash(secret)
    hash1.should eq hash2
  end
end
