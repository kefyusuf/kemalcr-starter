require "../../spec_helper"
require "../../support/db/test_database"

private def atomic_product_service(with_repository : Bool = true) : KemalcrStarter::Modules::Products::ProductService
  outbox = with_repository ? KemalcrStarter::Infrastructure::DB::OutboxEventRepository.new(TestDatabase.database) : nil
  KemalcrStarter::Modules::Products::ProductService.new(KemalcrStarter::App.settings, TestDatabase.database, outbox)
end

private def seed_atomic_product : KemalcrStarter::Infrastructure::DB::ProductRecord
  KemalcrStarter::Infrastructure::DB::ProductRepository.new(TestDatabase.database).create(
    "prd_atomic", "org_atomic", "SKU-ATOMIC", "Original", "Original description", 100, "USD", "usr_atomic"
  )
end

private def reject_product_events! : Nil
  TestDatabase.database.exec <<-SQL
    ALTER TABLE outbox_events ADD CONSTRAINT spec_reject_product_events
    CHECK (event_type NOT IN ('product.created', 'product.updated', 'product.deleted'))
  SQL
end

private def product_event_count : Int64
  TestDatabase.database.scalar("SELECT COUNT(*) FROM outbox_events WHERE aggregate_type = 'product'").as(Int64)
end

describe "Product mutation and outbox atomicity" do
  before_each do
    TestDatabase.migrate!
    TestDatabase.truncate_all!
    users = KemalcrStarter::Infrastructure::DB::UserRepository.new(TestDatabase.database)
    users.create("usr_atomic", "atomic@example.com", "Owner", "unused")
    KemalcrStarter::Infrastructure::DB::OrganizationRepository.new(TestDatabase.database)
      .create("org_atomic", "atomic", "Atomic", "usr_atomic")
    KemalcrStarter::Infrastructure::DB::OrganizationMembershipRepository.new(TestDatabase.database)
      .create("mem_atomic", "org_atomic", "usr_atomic", "owner", joined_at: Time.utc)
  end

  after_each do
    TestDatabase.database.exec "ALTER TABLE outbox_events DROP CONSTRAINT IF EXISTS spec_reject_product_events"
  end

  it "rolls back product creation when PostgreSQL rejects the outbox insert" do
    reject_product_events!
    expect_raises(::PQ::PQError, /spec_reject_product_events/) do
      atomic_product_service.create_product("usr_atomic", "org_atomic", "SKU-NEW", "New", nil, 100, "USD")
    end
    TestDatabase.database.scalar("SELECT COUNT(*) FROM products").as(Int64).should eq 0
    product_event_count.should eq 0
  end

  it "rolls back every updated field when PostgreSQL rejects the outbox insert" do
    original = seed_atomic_product
    reject_product_events!
    expect_raises(::PQ::PQError, /spec_reject_product_events/) do
      atomic_product_service.update_product("usr_atomic", "org_atomic", original.id, "Changed", "Changed description", 200, "inactive")
    end
    stored = KemalcrStarter::Infrastructure::DB::ProductRepository.new(TestDatabase.database).find(original.id).not_nil!
    stored.name.should eq "Original"
    stored.description.should eq "Original description"
    stored.price_cents.should eq 100
    stored.status.should eq "active"
    stored.updated_at.should eq original.updated_at
    product_event_count.should eq 0
  end

  it "restores a deleted product when PostgreSQL rejects the outbox insert" do
    original = seed_atomic_product
    reject_product_events!
    expect_raises(::PQ::PQError, /spec_reject_product_events/) do
      atomic_product_service.delete_product("usr_atomic", "org_atomic", original.id)
    end
    stored = KemalcrStarter::Infrastructure::DB::ProductRepository.new(TestDatabase.database).find(original.id)
    stored.should_not be_nil
    stored.not_nil!.sku.should eq "SKU-ATOMIC"
    product_event_count.should eq 0
  end

  it "persists all three product events even when no repository is explicitly injected" do
    service = atomic_product_service(with_repository: false)
    created = service.create_product("usr_atomic", "org_atomic", "  SKU-NEW  ", "  New  ", nil, 100, "usd")
    updated = service.update_product("usr_atomic", "org_atomic", created.id, "Changed", nil, 200, nil)
    updated.not_nil!.name.should eq "Changed"
    service.delete_product("usr_atomic", "org_atomic", created.id).should be_true
    event_types = TestDatabase.database.query_all("SELECT event_type FROM outbox_events ORDER BY event_type", as: String)
    event_types.should eq ["product.created", "product.deleted", "product.updated"]
    events = TestDatabase.database.query_all("SELECT aggregate_id, event_data::text FROM outbox_events WHERE event_type = 'product.created'", as: {String, String})
    events.size.should eq 1
    events.first[0].should eq created.id
    payload = JSON.parse(events.first[1])
    payload["sku"].as_s.should eq "SKU-NEW"
    payload["name"].as_s.should eq "New"
    payload["organization_id"].as_s.should eq "org_atomic"
    all_events = TestDatabase.database.query_all("SELECT event_type, aggregate_id, event_data::text, status FROM outbox_events", as: {String, String, String, String})
    all_events.each do |event|
      event[1].should eq created.id
      event[3].should eq "pending"
      JSON.parse(event[2])["organization_id"].as_s.should eq "org_atomic"
      JSON.parse(event[2])["name"].as_s.should eq "Changed" if event[0] == "product.updated"
    end
  end

  it "commits the product and matching pending event on success" do
    created = atomic_product_service.create_product("usr_atomic", "org_atomic", "SKU-NEW", "New", nil, 100, "USD")
    KemalcrStarter::Infrastructure::DB::ProductRepository.new(TestDatabase.database).find(created.id).should_not be_nil
    event = TestDatabase.database.query_one("SELECT event_type, aggregate_id, status FROM outbox_events", as: {String, String, String})
    event.should eq({"product.created", created.id, "pending"})
  end

  it "does not leave an orphan event when the product insert violates its uniqueness constraint" do
    seed_atomic_product
    expect_raises(::PQ::PQError, /products_organization_id_sku_key/) do
      atomic_product_service.create_product("usr_atomic", "org_atomic", "SKU-ATOMIC", "Duplicate", nil, 100, "USD")
    end
    TestDatabase.database.scalar("SELECT COUNT(*) FROM products").as(Int64).should eq 1
    product_event_count.should eq 0
  end

  it "does not emit update or deletion events for a missing product" do
    service = atomic_product_service
    service.update_product("usr_atomic", "org_atomic", "prd_missing", "Changed", nil, nil, nil).should be_nil
    service.delete_product("usr_atomic", "org_atomic", "prd_missing").should be_false
    product_event_count.should eq 0
  end

  it "does not mutate or emit events for a product owned by another organization" do
    users = KemalcrStarter::Infrastructure::DB::UserRepository.new(TestDatabase.database)
    users.create("usr_other_atomic", "other-atomic@example.com", "Other", "unused")
    KemalcrStarter::Infrastructure::DB::OrganizationRepository.new(TestDatabase.database)
      .create("org_other_atomic", "other-atomic", "Other", "usr_other_atomic")
    KemalcrStarter::Infrastructure::DB::ProductRepository.new(TestDatabase.database)
      .create("prd_other_atomic", "org_other_atomic", "OTHER", "Other", nil, 100, "USD", "usr_other_atomic")
    service = atomic_product_service
    service.update_product("usr_atomic", "org_atomic", "prd_other_atomic", "Changed", nil, nil, nil).should be_nil
    service.delete_product("usr_atomic", "org_atomic", "prd_other_atomic").should be_false
    TestDatabase.database.scalar("SELECT name FROM products WHERE id = 'prd_other_atomic'").as(String).should eq "Other"
    product_event_count.should eq 0
  end
end
