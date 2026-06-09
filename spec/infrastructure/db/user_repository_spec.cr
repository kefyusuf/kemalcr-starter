require "../../spec_helper"
require "../../support/db/test_database"
require "../../support/redis/test_redis"

describe KemalcrStarter::Infrastructure::DB::UserRepository do
  repository = KemalcrStarter::Infrastructure::DB::UserRepository.new(TestDatabase.database)

  before_each do
    TestDatabase.migrate!
    TestDatabase.truncate_all!
    TestRedis.clear!
  end

  it "creates and reads back a user through parameterized SQL" do
    created = repository.create("usr_test_001", "repo@example.com", "Test User", "digest")

    created.id.should eq "usr_test_001"
    created.email.should eq "repo@example.com"
    created.name.should eq "Test User"
    created.status.should eq "active"

    found = repository.find("usr_test_001")
    found.should_not be_nil
    found.not_nil!.email.should eq "repo@example.com"
  end
end
