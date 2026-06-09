require "../../../src/kemalcr_starter"

module TestRedis
  extend self

  def clear! : Nil
    redis_url = ENV["TEST_REDIS_URL"]? || ENV["REDIS_URL"]? || "redis://redis:6379/0"
    client = KemalcrStarter::Infrastructure::Redis::ClientManager.client(redis_url)
    client.flushdb
  end
end
