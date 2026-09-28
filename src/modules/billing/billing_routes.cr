module KemalcrStarter
  module Modules
    module Billing
      module BillingRoutes
        extend self

        struct CheckoutRequest
          include JSON::Serializable

          @[JSON::Field(key: "price_id")]
          getter price_id : String
          @[JSON::Field(key: "success_url")]
          getter success_url : String
          @[JSON::Field(key: "cancel_url")]
          getter cancel_url : String
        end

        def draw : Nil
          post "/v1/billing/webhooks/stripe" do |env|
            raw_body = env.request.body.try(&.gets_to_end).to_s
            signature = env.request.headers["Stripe-Signature"]?
            KemalcrStarter::App.billing_service.handle_stripe_webhook(raw_body, signature)
            env.status(200).json({received: true})
          end

          post "/v1/organizations/:organization_id/billing/checkout" do |env|
            actor_id = KemalcrStarter::App.request_context(env).actor_id
            raise Core::Errors::UnauthorizedError.new unless actor_id

            organization_id = env.params.url["organization_id"]
            request = parse_json_body(env, CheckoutRequest)
            session = KemalcrStarter::App.billing_service.create_checkout(
              actor_id,
              organization_id,
              request.price_id,
              request.success_url,
              request.cancel_url
            )

            env.status(201).json({
              id:       session.id,
              url:      session.url,
              provider: session.provider,
            })
          end

          get "/v1/billing/provider" do |env|
            actor_id = KemalcrStarter::App.request_context(env).actor_id
            raise Core::Errors::UnauthorizedError.new unless actor_id

            env.status(200).json({
              provider:   KemalcrStarter::App.billing_service.adapter_provider,
              request_id: KemalcrStarter::App.request_context(env).request_id,
            })
          end
        end

        private def read_request_body(env : HTTP::Server::Context) : String
          body = env.request.body.try(&.gets_to_end)
          raise Core::Errors::ValidationError.new("Request body is required.") if body.nil? || body.blank?

          body
        end

        private def parse_json_body(body : String, type : T.class) : T forall T
          T.from_json(body)
        rescue JSON::ParseException | JSON::SerializableError
          raise Core::Errors::ValidationError.new
        end

        private def parse_json_body(env : HTTP::Server::Context, type : T.class) : T forall T
          parse_json_body(read_request_body(env), type)
        end
      end
    end
  end
end
