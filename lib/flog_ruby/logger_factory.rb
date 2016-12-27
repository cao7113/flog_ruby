require 'logger'
require 'pathname'
require 'fileutils'
require 'syslog/logger'

module FlogRuby
  module Floggable
    extend ActiveSupport::Concern

    included do
      attr_accessor :group

      ::Logger::Severity.constants.map(&:downcase).each do |level|
        alias_method "raw_#{level}", level

        define_method level do |tag, opts = {}|
          flog(level, tag, opts)
        end
      end

      def flog(level, tag, opts = {})
        attrs = (opts || {}).with_indifferent_access
        extra = attrs.delete(:extra) || {}

        opt_tag = attrs.delete(:tag)
        if opt_tag
          extra[:msg] ||= tag
          tag = opt_tag
        end

        # resource
        resource = attrs.delete :resource
        if resource
          attrs[:resource_type] ||= resource.class.name
          attrs[:resource_id] ||= resource&.id
        end

        # distinct_id
        if attrs[:distinct_id].nil?
          attrs[:distinct_id] = attrs[:user_id] ? attrs[:user_id] : attrs[:client_ip]
        end

        # role
        uid = attrs[:user_id]
        attrs[:role] = Flog.user_klass.find_by(id: uid)&.role if attrs[:role].nil? && uid

        # error
        err = extra.delete :error
        extra[:backtrace] = err.backtrace.first(10).join('; ') if err && err.is_a?(Exception)

        # 添加来源信息origin
        origin = ENV.fetch('SYSLOG_ORIGIN', group)

        body = {origin: origin, properties: attrs, extra: extra}.to_json.to_s
        blk = lambda { body }
        clevel = ::Logger.const_get(level.upcase)
        stag = [group, tag].compact.join('_')
        add(clevel, nil, stag, &blk)
        #send "raw_#{level}", nil, &blk
      end
    end
  end

  # 写文件方式
  class Flogger < Logger
    include Floggable

    attr_accessor :log_path

    def initialize(logpath, shift_age = 0, shift_size = 1_048_576)
      if logpath
        if logpath.is_a?(Pathname)
          logpath.dirname.mkpath
          @log_path = logpath
        elsif logpath.is_a?(IO)
          @log_path = nil
        else
          raise "Invalid flog! #{logpath.inspect}"
        end
      else
        raise "Invalid flog! #{logpath.inspect}"
      end
      super(logpath, shift_age, shift_size)
    end

    def logdev
      instance_variable_get('@logdev')
    end

    def logdev2
      logdev.try(:dev)
    end

    # Deprecated!
    def method_missing(mthd, *margs, &_blk)
      self.class.class_eval do
        define_method mthd do |*args|
          opts = args.extract_options! || {}
          level = opts.delete(:level) || :info
          send(level, mthd, opts)
        end
      end
      send(mthd, *margs)
    end

    class Formatter < ::Logger::Formatter
      def call(severity, time, progname, msg)
        format = "%s, [%s] %s: %s\n".freeze
        format % [severity[0..0], format_datetime(time), progname, msg2str(msg)]
      end

      private

      def format_datetime(time)
        #raw: time.strftime(@datetime_format || "%Y-%m-%dT%H:%M:%S.%6N ".freeze)
        #Time.zone.now.iso8601(3) #=> "2016-12-06T13:04:01.703+08:00"
        (time || Time.zone.now).iso8601(3) # 需要毫秒
      end
    end
  end

  # 走Syslog转发机制
  class Syslogger < Syslog::Logger
    include Floggable

    def initialize(program_name = nil, facility = nil)
      program_name = program_name.to_s

      fac = (ENV['SYSLOG_FACILITY'] || 'local0').upcase
      log_fac = "LOG_#{fac}"
      facility ||= Syslog.const_get(log_fac)

      super(program_name, facility)
    end

    def add(severity, message = nil, progname = nil, &block)
      severity ||= ::Logger::UNKNOWN
      progname ||= group
      @level <= severity and
        @@syslog.log((LEVEL_MAP[severity] | @facility), '%s', formatter.call(severity, Time.zone.now, progname, (message || block.call)))
      true
    end

    class Formatter < ::Syslog::Logger::Formatter
      def call(severity, time, progname, msg)
        format = "%s, [%s] %s: %s\n".freeze
        sev_str = format_severity(severity)
        format % [sev_str[0..0], format_datetime(time), progname, clean(msg)]
      end

      private

      # Clean up messages so they're nice and pretty.
      def clean(message)
        message = message.to_s.strip
        message.gsub!(/\e\[[0-9;]*m/, '') # remove useless ansi color codes
        message
      end

      # Severity label for logging (max 5 chars).
      SEV_LABEL = %w(DEBUG INFO WARN ERROR FATAL ANY).each(&:freeze).freeze
      
      def format_severity(severity)
        SEV_LABEL[severity] || 'ANY'
      end

      def format_datetime(time)
        #(time || Time.zone.now).to_s(:iso8601)
        #Time.zone.now.iso8601(3) #=> "2016-12-06T13:04:01.703+08:00"
        (time || Time.zone.now).iso8601(3) # 需要毫秒
      end
    end
  end

  class LoggerFactory
    cattr_accessor :root, :loggers, :mloggers, :user_klass
    self.root = Pathname.new('log').join('flog')
    self.loggers = {}
    self.mloggers = {}

    class << self
      def user_klass
        @user_klass ||= ::User
      end

      # e.g. api, core, default: to STDOUT
      def get(biz_name = :stdout, level = nil)
        return Flogger.new(STDOUT) if biz_name.nil? || biz_name == :stdout

        biz_name = biz_name.to_sym
        findit = loggers[biz_name]
        return findit if findit

        level ||= default_level
        if syslog?
          logger = Syslogger.new(biz_name)
          logger.formatter = Syslogger::Formatter.new
          logger.level = level
        else
          log_path = root.join("#{biz_name}.log")
          logger = Flogger.new(log_path, 3, 10_240_000) #10M
          logger.formatter = Flogger::Formatter.new
          logger.level = level
          logger.logdev2.sync = true
        end

        logger.group = biz_name
        loggers[biz_name] = logger
      end

      def default_level
        if ENV['FLOG_LEVEL']
          l = ENV['FLOG_LEVEL'].upcase
          return Logger::Severity.const_get(l)
        end
        Logger::DEBUG
      end

      # just temp monitor log in: log/xx.log
      def mget(biz_name = :stdout, level = Logger::DEBUG)
        return Flogger.new(STDOUT) if biz_name.nil? || biz_name == :stdout

        biz_name = biz_name.to_sym
        findit = mloggers[biz_name]
        return findit if findit

        # different path!!!
        log_path = Pathname.new('log').join("#{biz_name}.log")
        logger = Flogger.new(log_path, 3, 10_240_000) #10M

        logger.formatter = Flogger::Formatter.new
        logger.level = level
        logger.logdev2.sync = true
        mloggers[biz_name] = logger
      end

      # 获取有轮滚的logger
      def lget(filepath, opts = {})
        ::Logger.new(filepath, 3, 10_240_000)
      end

      def syslog?
        return false if ENV['FLOG_NOT_SYSLOG']
        Rails.env.production? || Rails.env.staging? ||
          File.exist?('tmp/flog_using_syslog')
      end

      def tail(log_file, lines = nil)
        return [] if log_file.blank?
        lines = lines.to_i
        lines = 10 if lines < 10
        `tail -n #{lines} #{log_file}`.to_s.split("\n").reverse
      end
    end
  end
end
