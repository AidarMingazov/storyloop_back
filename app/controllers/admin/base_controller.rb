module Admin
  class BaseController < ApplicationController
    include ActionView::RecordIdentifier # dom_id for redirect anchors

    layout "admin"
    before_action :require_admin

    private
      # Non-admins get a 404 so the admin area does not reveal itself.
      def require_admin
        raise ActionController::RoutingError, "Not Found" unless Current.user&.admin?
      end

      # Admin forms edit JSON columns (box, layout) as text.
      def parse_json_field(value)
        return nil if value.blank?
        JSON.parse(value)
      rescue JSON::ParserError
        :invalid
      end
  end
end
