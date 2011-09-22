require 'action_dispatch'
require 'exception_notifier/notifier'

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
    kontroller = env['action_controller.instance'] || ::ExceptionNotifier::MissingController.new
    
    agent = Redis.new
    key = "#{exception.class}@#{kontroller.controller_name}##{kontroller.action_name}"
    
    unless Array.wrap(options[:ignore_exceptions]).include?(exception.class)
      unless (t=agent.hget("exception_timer", key)).present? && Time.at(t.to_i) > Time.now
        Notifier.exception_notification(env, exception).deliver
        agent.hset("exception_timer", key, (Time.now + options[:timer]).to_i)
        agent.quit
        env['exception_notifier.delivered'] = true
      end
    end

    raise exception
  end
end
