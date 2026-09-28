module KemalcrStarter
  module Modules
    module Products
      module ProductRoutes
        extend self

        struct CreateProductRequest
          include JSON::Serializable

          getter sku : String
          getter name : String
          getter description : String?
          @[JSON::Field(key: "price_cents")]
          getter price_cents : Int32
          getter currency : String?
        end

        struct UpdateProductRequest
          include JSON::Serializable

          getter name : String?
          getter description : String?
          @[JSON::Field(key: "price_cents")]
          getter price_cents : Int32?
          getter status : String?
        end

        def draw : Nil
          post "/v1/organizations/:organization_id/products" do |env|
            actor_id = KemalcrStarter::App.request_context(env).actor_id
            raise Core::Errors::UnauthorizedError.new unless actor_id

            organization_id = env.params.url["organization_id"]
            request = parse_json_body(env, CreateProductRequest)
            product = KemalcrStarter::App.product_service.create_product(
              actor_id,
              organization_id,
              request.sku,
              request.name,
              request.description,
              request.price_cents,
              request.currency || "USD"
            )

            env.response.status_code = 201
            env.response.content_type = "application/json"
            product.to_json
          end

          get "/v1/organizations/:organization_id/products" do |env|
            actor_id = KemalcrStarter::App.request_context(env).actor_id
            raise Core::Errors::UnauthorizedError.new unless actor_id

            organization_id = env.params.url["organization_id"]
            status = env.params.query["status"]?
            limit = (env.params.query["limit"]? || "50").to_i
            offset = (env.params.query["offset"]? || "0").to_i
            products = KemalcrStarter::App.product_service.list_products(actor_id, organization_id, status, limit, offset)

            env.response.status_code = 200
            env.response.content_type = "application/json"
            {
              products:   products,
              count:      products.size,
              request_id: KemalcrStarter::App.request_context(env).request_id,
            }.to_json
          end

          get "/v1/organizations/:organization_id/products/:product_id" do |env|
            actor_id = KemalcrStarter::App.request_context(env).actor_id
            raise Core::Errors::UnauthorizedError.new unless actor_id

            organization_id = env.params.url["organization_id"]
            product_id = env.params.url["product_id"]
            product = KemalcrStarter::App.product_service.get_product(actor_id, organization_id, product_id)

            if product
              env.status(200).json(product)
            else
              env.status(404).json({status: "not_found", request_id: KemalcrStarter::App.request_context(env).request_id})
            end
          end

          patch "/v1/organizations/:organization_id/products/:product_id" do |env|
            actor_id = KemalcrStarter::App.request_context(env).actor_id
            raise Core::Errors::UnauthorizedError.new unless actor_id

            organization_id = env.params.url["organization_id"]
            product_id = env.params.url["product_id"]
            request = parse_json_body(env, UpdateProductRequest)
            product = KemalcrStarter::App.product_service.update_product(
              actor_id,
              organization_id,
              product_id,
              request.name,
              request.description,
              request.price_cents,
              request.status
            )

            if product
              env.status(200).json(product)
            else
              env.status(404).json({status: "not_found", request_id: KemalcrStarter::App.request_context(env).request_id})
            end
          end

          delete "/v1/organizations/:organization_id/products/:product_id" do |env|
            actor_id = KemalcrStarter::App.request_context(env).actor_id
            raise Core::Errors::UnauthorizedError.new unless actor_id

            organization_id = env.params.url["organization_id"]
            product_id = env.params.url["product_id"]
            deleted = KemalcrStarter::App.product_service.delete_product(actor_id, organization_id, product_id)

            if deleted
              env.status(200).json({status: "deleted", request_id: KemalcrStarter::App.request_context(env).request_id})
            else
              env.status(404).json({status: "not_found", request_id: KemalcrStarter::App.request_context(env).request_id})
            end
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
