require "http/client"
require "uri"
require "json"

module KemalcrStarter
  module Infrastructure
    module Billing
      # Minimal Stripe REST adapter (form-encoded API).
      # Replace via App.install_billing_adapter for richer providers.
      class StripeBillingAdapter < BillingAdapter
        API_BASE = "https://api.stripe.com"

        def initialize(@api_key : String)
        end

        def provider : String
          "stripe"
        end

        def create_customer(*, email : String, name : String?, organization_id : String) : BillingCustomer
          form = HTTP::Params.new
          form["email"] = email
          form["name"] = name if name
          form["metadata[organization_id]"] = organization_id

          body = post("/v1/customers", form)
          id = body["id"].as_s
          BillingCustomer.new(id: id, email: email, provider: provider)
        end

        def create_checkout_session(*, customer_id : String, price_id : String, success_url : String, cancel_url : String) : CheckoutSession
          form = HTTP::Params.new
          form["mode"] = "subscription"
          form["customer"] = customer_id
          form["line_items[0][price]"] = price_id
          form["line_items[0][quantity]"] = "1"
          form["success_url"] = success_url
          form["cancel_url"] = cancel_url

          body = post("/v1/checkout/sessions", form)
          CheckoutSession.new(id: body["id"].as_s, url: body["url"].as_s, provider: provider)
        end

        def cancel_subscription(subscription_id : String) : Bool
          response = request("POST", "/v1/subscriptions/#{subscription_id}/cancel", nil)
          (200...300).includes?(response.status_code)
        end

        private def post(path : String, form : HTTP::Params) : JSON::Any
          response = request("POST", path, form.to_s)
          parsed = JSON.parse(response.body)
          unless (200...300).includes?(response.status_code)
            message = parsed["error"]?.try(&.["message"]?.try(&.as_s)) || "stripe_error"
            raise IO::Error.new("Stripe API error: #{message}")
          end
          parsed
        end

        private def request(method : String, path : String, body : String?) : HTTP::Client::Response
          client = HTTP::Client.new(URI.parse(API_BASE))
          client.connect_timeout = 10.seconds
          client.read_timeout = 15.seconds
          headers = HTTP::Headers{
            "Authorization" => "Bearer #{@api_key}",
            "Content-Type"  => "application/x-www-form-urlencoded",
          }
          begin
            case method
            when "POST"
              client.post(path, headers: headers, body: body || "")
            else
              client.exec(method, path, headers: headers, body: body)
            end
          ensure
            client.close rescue nil
          end
        end
      end
    end
  end
end
