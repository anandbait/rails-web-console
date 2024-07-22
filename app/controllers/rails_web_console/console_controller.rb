require 'stringio'

module RailsWebConsole

  class Context
    def initialize
      @block = Proc.new {}
      @binding = binding
    end

    def run command
      eval command, @binding
    end

    def routes match = nil
      require 'terminal-table'
      rows = Rails.application.routes.routes.map do |r|
        constraints = r.constraints.dup
        method = constraints.delete(:request_method).to_s.gsub(/[^A-Z\|]/, '').split('|').reverse.join(', ')
        # When TJ (maintainer of terminal-table) makes a new release, use the following line:
        #[r.name.to_s, {:value => method, :alignment => :right}, r.path.spec, constraints.inspect]
        [
          r.name.to_s,
          method.rjust(12),
          r.path.spec,
          constraints == {} ? '' : constraints.inspect
        ]
      end

      if match
        rows.select! { |route|
          route.any? { |r| r.include?(match) }
        }
      end

      puts Terminal::Table.new(
        # arain, these are already implemented in terminal-table, but gem is not released
        #:border_x => "",
        #:border_y => "",
        #:border_i => "",
        :rows => rows
      )
    end

    def help
      puts <<-HELP

Hi there! This is a pure web console
------------------------------------
  - you can run ruby as usual
  - you can run rake tasks just as you would in terminal "rake ..."
  - try up and down arrows to navigate past commands
  - variables work as wel (set a = 1, read a -> 1)

      HELP
    end
  end

  $rails_web_console_context ||= Context.new

  class ConsoleController < ::ActionController::Base
    if _process_action_callbacks.any?{|a| a.filter == :verify_authenticity_token}
      # ActionController::Base no longer protects from forgery in Rails 5
      skip_before_filter :verify_authenticity_token
    end
    layout false

    def index
      $rails_web_console_context = Context.new
    end

    SCRIPT_LIMIT = defined?(::WEB_CONSOLE_SCRIPT_LIMIT) ? ::WEB_CONSOLE_SCRIPT_LIMIT : 1000
    WARNING_LIMIT_MSG = "WARNING: stored script in session was limited to the first " +
      "#{SCRIPT_LIMIT} chars to avoid issues with cookie overflow\n"
    def run
# <<<<<<< HEAD
#       # we limit up to 1k to avoid ActionDispatch::Cookies::CookieOverflow (4k) which we
#       # can't rescue since it happens in a middleware
#       script = params[:script]
#       # we allow users to ignore the limit if they are using another session storage mechanism
#       script = script[0...SCRIPT_LIMIT] unless defined?(::WEB_CONSOLE_IGNORE_SCRIPT_LIMIT)
#       session[:script] = script
#       stdout_orig = $stdout
#       $stdout = StringIO.new
#       begin
#         puts WARNING_LIMIT_MSG if params[:script].size > SCRIPT_LIMIT &&
#           !defined?(::WEB_CONSOLE_IGNORE_SCRIPT_LIMIT)
#         result_eval = eval params[:script], binding
#         $stdout.rewind
#         result = %Q{<div class="stdout">#{escape $stdout.read}</div>
#           <div class="return">#{escape result_eval.inspect}</div>}
#       rescue Exception => e
#         result = e.to_s
# =======
      command = params[:script]

      stdout = ''
      stdout_orig = $stdout
      $stdout = StringIO.new
      begin
        if command[0, 5] == 'rake '
          result = rake(command[5, command.length])
        else
          result = $rails_web_console_context.run command
        end
        $stdout.rewind
        stdout = 'error during stdout rewing'
        stdout = escape $stdout.read

        render(json: {
          stdout: stdout,
          value: escape(result.inspect),
          type: get_type(result)
        })
      rescue SecurityError => e
        result = e
        stdout = escape(e.message) + "\n", e.backtrace[0..10].join("\n")
      rescue NoMemoryError => e
        result = e
        stdout = escape(e.message) + "\n", e.backtrace[0..10].join("\n")
      rescue ScriptError => e
        result = e
        stdout = escape(e.message) + "\n", e.backtrace[0..10].join("\n")
      rescue StandardError => e
        result = e
        stdout = escape(e.message) + "\n", e.backtrace[0..10].join("\n")
      ensure
        $stdout = stdout_orig
      end
      if e
        render(json: {
          stdout: stdout,
          value: escape(result.inspect),
          type: get_type(result)
        })
      end
    end

    protected

      # invoke rake task from here
      def rake task
        unless @tasks_loaded
          require 'rake'
          Rails.application.load_tasks
          @tasks_loaded = true
        end
        Rake::Task[task].execute
        nil
      end

    private

    TYPES = [
      Exception, Numeric, String
    ]

    def get_type(result)
      for type in TYPES
        if result.is_a? type
          return type.name
        end
      end
      result.class.name
    end

    def escape(content)
      view_context.escape_once content
    end
  end
end
