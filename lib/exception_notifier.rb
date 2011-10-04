require 'action_dispatch'
require 'exception_notifier/notifier'
require 'missing_controller'

class ExceptionNotifier
  def self.default_ignore_exceptions
    [].tap do |exceptions|
      exceptions << ::ActiveRecord::RecordNotFound if defined? ::ActiveRecord::RecordNotFound
      exceptions << ::AbstractController::ActionNotFound if defined? ::AbstractController::ActionNotFound
      exceptions << ::ActionController::RoutingError if defined? ::ActionController::RoutingError
    end
  end

  def initialize(app, options = {})
    @app, @options = app, options

    Notifier.default_sender_address       = @options[:sender_address]
    Notifier.default_exception_recipients = @options[:exception_recipients]
    Notifier.default_email_prefix         = @options[:email_prefix]
    Notifier.default_sections             = @options[:sections]
    Notifier.default_timer                = @options[:timer]

    @options[:ignore_exceptions] ||= self.class.default_ignore_exceptions
  end

  def call(env)
    @app.call(env)
  rescue Exception => exception
    options = (env['exception_notifier.options'] ||= Notifier.default_options)
    options.reverse_merge!(@options)
    
    if options[:timer].present?
      kontroller = env['action_controller.instance'] || MissingController.new
      agent = Redis.new
      key = "#{exception.class}@#{kontroller.controller_name}##{kontroller.action_name}"
    
      unless Array.wrap(options[:ignore_exceptions]).include?(exception.class)
        unless (t=agent.hget("exception_timer", key)).present? && Time.at(t.to_i) > Time.now
          send_email(env, exception)
          agent.hset("exception_timer", key, (Time.now + options[:timer]).to_i)
          agent.quit
          
        end
      end
    else
      send_email(env, exception)
    end
    raise exception
  end
  
  def send_email(env, exception)
    Notifier.exception_notification(env, exception).deliver
    env['exception_notifier.delivered'] = true
  end
end
