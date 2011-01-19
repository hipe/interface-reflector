require 'rubygems'; require 'ruby-debug'

module Hipe; module Resizum; end  end

module Hipe::Resizum::InterfaceReflector
  class << self
    def extended cls
      cls.extend ClassMethods
      cls.send(:include, InstanceMethods)
    end
  end
  class GenericContext < Hash
    def initialize
      @out = $stdout
      @err = $stderr
    end
    attr_reader :out, :err
  end
  module InstanceMethods
    def build_cli_option_parser
      require 'optparse'
      OptionParser.new do |o|
        o.banner = usage
        a = self.class.interface.parameters.select{ |p| p.cli? and p.option? }
        if a.any?
          o.separator(em("options:"))
          a.each do |p|
            o.on( * p.cli_definition_array ){ |v| dispatch_option(p, v) }
          end
        end
      end
    end
    def build_context # hrm
      GenericContext.new
    end
    def dispatch_option parameter, value
      args = parameter.takes_argument? ? [value] : []
      send("on_#{parameter.intern}", *args) or
        handle_failed_option(parameter, value)
    end
    # file utils convenience smell begin
    class << self
      def file_utils_adapter
        const_defined?(:FileUtilsAdapter) ? const_get(:FileUtilsAdapter) :
          const_set(:FileUtilsAdapter, begin
            require 'fileutils'
            c = Class.new
            c.class_eval do
              include FileUtils
              def initialize outs
                @fileutils_output = outs
              end
              ::FileUtils::METHODS.each { |m| public m }
            end
            c
          end)
      end
    end
    def file_utils
      @file_utils ||= InstanceMethods.file_utils_adapter.new(@c.err)
    end
    # file utils convenince smell end
    def handle_failed_option param, value
      @options_ok = false
    end
    def oxford_comma items, last_glue = ' and ', rest_glue = ', '
      items.zip( items.size < 2 ? [] :
          ( [last_glue] + Array.new(items.size - 2, rest_glue) ).reverse
      ).flatten.join
    end
  end
  module ClassMethods
    def interface
      @interface ||= build_interface
    end
  end
  class ParameterDefinitionSet < Array
    def initialize
      @parsed = false
    end
    def each &b;        @parsed or parse!;         super(&b)     end
    def select &b;      @parsed or parse!;         super(&b)     end
  private
    def parse!
      each_index do |idx|
        self[idx] = self[idx].parse
      end
      @parsed = true
    end
  end
  class Parameter
    def initialize intern
      @intern = intern
      block_given? and yield self
    end
    def cli?                ;   instance_variable_defined?('@is_cli')      end
    def cli!                ;   @is_cli = true;                            end
    def glob!               ;   @glob = true;                              end
    def noable!             ;   @noable = true;                            end
    def argument_required!  ;   @argument = :required                      end
    def argument_optional!  ;   @argument = :optional                      end
    def takes_argument?     ;   instance_variable_defined?('@argument')    end
    def option!             ;   @option   = true                           end
    def required!           ;   @required = true                           end
    def optional?           ;  !required?                                  end
    def argument?           ;  !option?                                    end
    def default= foo
      @has_default = true
      @default = foo
      (class << self; self end).send(:attr_reader, :default)
    end
    attr_reader   :glob
    alias_method  :glob?, :glob
    attr_reader   :has_default
    alias_method  :has_default?, :has_default
    attr_reader   :intern
    attr_accessor :cli_definition_array, :cli_syntax_label, :cli_label
    attr_reader   :argument
    attr_reader   :option
    alias_method  :option?, :option
    attr_reader   :required
    alias_method  :required?, :required
    attr_accessor :desc
  end
  class RequestParser
    # an adapter to make it look like an option parser, but it's more
    def initialize
      @parameters = ParameterDefinitionSet.new
      yield self
    end
    attr_reader :parameters
    def on *a
      @parameters.push UnparsedOptionDefinition.new(a)
    end
    def arg *a
      @parameters.push UnparsedArgumentDefinition.new(a)
    end
  end
  class RequestParser
    class UnparsedParameterDefinition
      def initialize(arr)
        @arr = arr
      end
    end
    class UnparsedOptionDefinition < UnparsedParameterDefinition
      def parse
        found = @arr.detect{ |x| x.kind_of?(String) && 0 == x.index('--') }
        found or fail("Must have --long option name in: #{@arr.inspect}")
        md = %r{\A--(\[no-\])?([^=\[ ]+)
          (?:  \[[ =](<?[^ >]+>?)?\]
            |   [ =] (<?[^ >]+>?)?
          )?
        \Z}x.match(found)
        md or fail("regexp match failure with: #{@arr.inspect}")
        intern = md[2].gsub('-','_').intern
        Parameter.new(intern) do |p|
          p.cli!; p.option!
          p.cli_syntax_label = @arr.first
          md[1].nil? or p.noable!
          md[3].nil? or p.argument_optional!
          md[4].nil? or p.argument_required!
          if @arr.last.kind_of?(Hash)
            h = @arr.pop
            h.key?(:default) and go_default(p, h.delete(:default))
            h.any? and fail("unsupported opts: #{h.keys.join(', ')}")
          end
          p.cli_definition_array = @arr
        end
      end
      def go_default p, default
        p.default = default
        a = b = ''
        if @arr.last.kind_of?(String) && @arr.last[0,1] != '-'
          if @arr.last.length > 0
            @arr.last.concat(' ')
            a = '('; b = ')'
          end
        else
          @arr.push ''
        end
        @arr.last.concat "#{a}default: #{default.inspect}#{b}"
      end
    end
    class UnparsedArgumentDefinition < UnparsedParameterDefinition
      def parse
        md = %r{\A (
            \[  ( <? ([a-z0-9][-_a-z0-9]*) >?  ) \]
          |     ( <? ([a-z0-9][-_a-z0-9]*) >?  )
          | \[  ( <? ([a-z0-9][-_a-z0-9]*) >?  ) [ ]*
              \[
                [ ]* \6 [ ]* \[\.\.\.?\] [ ]*
              \] [ ]*
            \]
          | ( <? ([a-z0-9][-_a-z0-9]*) >? ) [ ]*
            \[
              [ ]* \8 [ ]* \[\.\.\.?\] [ ]*
            \] [ ]*
        ) \Z}ix.match(@arr.first)
        md or fail("expecting \"foo\" or \"[foo]\" or \"foo[foo[...]]\" "<<
          " or \"[foo[foo[...]]]\", not #{@arr.first.inspect}")
        intern = (md[3] || md[5] || md[7] || md[9]).gsub('-','_').intern
        Parameter.new(intern) do |p|
          p.cli!; p.cli_syntax_label = md[1]
          p.cli_label = (md[2] || md[4] || md[6] || md[8])
          p.argument_required! # always true for arguments
          (md[4] || md[8]) and p.required!
          (md[6] || md[8]) and p.glob!
          p.desc = @arr[1..-1] if @arr.size > 1
        end
      end
    end
  end
  class Fatal < ::RuntimeError; end
  module Colorizer
    Codes = {:bold=>1,:dark_red=>31,:green=>32,:yellow=>33,:blue=>34,
      :purple=>35,:cyan=>36,:white=>37,:red=>38}
    def color(s, *a); "\e[#{a.map{|x|Codes[x]}.compact*';'}m#{s}\e[0m" end
  end
  module CliInstanceMethods
    include Colorizer
    def run argv
      @argv = argv
      @c = build_context
      @exit_ok = nil
      @queue = []
      if ! (parse_opts and parse_args)
        @c.err.puts usage
        @c.err.puts invite
        return
      end
      @queue.push default_action
      # catch(:early_exit){ while(m = @queue.pop); send(m) end }
      begin
        while(m = @queue.pop); send(m) end
      rescue Fatal => e
        handle_fatal e
      end
    end
    attr_accessor :c
    alias_method :execution_context, :c
  protected
    Styles = { :error => [:bold, :red], :em => [:bold, :green] }
    def style(s, style); color(s, *Styles[style]) end
    def em(s); style(s, :em) end
    def error msg
      @c.err.puts msg
      false
    end
    def cli_option_parser
      @cli_option_parser ||= build_cli_option_parser
    end
    def fatal msg
      raise Fatal.new msg
    end
    def handle_fatal e
      @c.err.puts e.message
    end
    def parse_opts
      @options_ok = true
      begin
        cli_option_parser.parse!(@argv)
      rescue OptionParser::ParseError => e
        return error(e.message)
      end
      self.class.interface.parameters.select do |p|
        p.has_default? && p.cli? && ! @c.key?(p.intern)
      end.each do |p|
        @c[p.intern] = p.default
      end
      @options_ok
    end
    def parse_args
      unexpected = missing = glob = nil
      ps = self.class.interface.parameters.select{|p| p.cli? and p.argument? }
      while @argv.any?
        if ps.any? and ps.first.glob? and glob.nil?
          glob = ps.shift
          @c[glob.intern] ||= []
        end
        if glob
          @c[glob.intern].push @argv.shift
        elsif ps.empty?
          unexpected = @argv
          break
        else
          dir = ( ps.first.required? || ps.last.optional? ) ? :shift : :pop
          @c[ps.send(dir).intern] = @argv.send(dir)
        end
      end
      (missing = ps.select(&:required?)).any? or missing = nil
      unexpected || missing and @exit_ok and return false
      unexpected and return error("unexpected arg#{'s' if @argv.size > 1}:" <<
        oxford_comma(@argv.map(&:inspect)))
      missing and return error("expecting: "<<
        oxford_comma(missing.map(&:cli_label)))
      true
    end
    def invite
      em("#{program_name} -h") << " for help"
    end
    def on_help
      args = self.class.interface.parameters.select{|p| p.cli? && p.argument?}
      if args.empty? ; ophack = cli_option_parser else
        ophack = cli_option_parser.dup
        ophack.separator(em("arguments:"))
        args.each do |p|
          ophack.on('--'+p.intern.to_s, * (p.desc || []))
          sw = ophack.instance_variable_get('@stack').last.list.last
          sw.short[0] = p.cli_label
          sw.long.clear
        end
      end
      @c.err.puts ophack.to_s
      @exit_ok = true
    end
    def on_version
      @c.err.puts "#{program_name} #{version_string}"
      @exit_ok = true
    end
    def program_name
      File.basename($PROGRAM_NAME)
    end
    def usage_syntax_string
      [program_name,options_syntax_string,arguments_syntax_string].compact*' '
    end
    def options_syntax_string
      s = self.class.interface.parameters.select{ |p| p.cli? && p.option? }.
      map{ |p| "[#{p.cli_syntax_label}]" }.join(' ')
      s unless s.empty?
    end
    def arguments_syntax_string
      s = self.class.interface.parameters.select{ |p| p.cli? && p.argument? }.
      map(&:cli_syntax_label).join(' ')
      s unless s.empty?
    end
    def usage
      "#{em('usage:')} #{usage_syntax_string}"
    end
  end
end
