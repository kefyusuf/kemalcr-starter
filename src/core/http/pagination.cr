module KemalcrStarter
  module Core
    module Http
      record PageParams,
        page : Int32,
        per_page : Int32 do
        DEFAULT_PER_PAGE =  20
        MAX_PER_PAGE     = 100

        def self.from_env(env : HTTP::Server::Context) : PageParams
          page = (env.params.query["page"]?.try(&.to_i?) || 1).clamp(1, Int32::MAX)
          per_page = (env.params.query["per_page"]?.try(&.to_i?) || DEFAULT_PER_PAGE).clamp(1, MAX_PER_PAGE)
          new(page: page, per_page: per_page)
        end

        def offset : Int32
          (page - 1) * per_page
        end
      end

      record PaginatedResponse,
        data : Array(JSON::Serializable),
        pagination : NamedTuple(page: Int32, per_page: Int32, total: Int64, total_pages: Int32)

      def self.paginated_list(env : HTTP::Server::Context, total : Int64, items : Array(JSON::Serializable)) : String
        page_params = PageParams.from_env(env)
        total_pages = (total.to_f / page_params.per_page).ceil.to_i
        JSON.build do |json|
          json.object do
            json.field "data" do
              json.array do
                items.each { |item| json.raw item.to_json }
              end
            end
            json.field "pagination" do
              json.object do
                json.field "page", page_params.page
                json.field "per_page", page_params.per_page
                json.field "total", total
                json.field "total_pages", total_pages
              end
            end
          end
        end
      end
    end
  end
end
