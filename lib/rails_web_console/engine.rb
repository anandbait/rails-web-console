module RailsWebConsole
  class Engine < ::Rails::Engine
    isolate_namespace RailsWebConsole


    config.to_prepare do
      Rails.application.config.assets.precompile += %w(
        console.js
      )
    end
  end
end
