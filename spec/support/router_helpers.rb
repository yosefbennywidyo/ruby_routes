module RouterHelpers
  def build_router(&block)
    RubyRoutes::Router.build(&block)
  end
end
