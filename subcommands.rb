module Hipe::InterfaceReflector
  module DispatcherModuleMethods
    include ::Hipe::InterfaceReflector::ModuleMethods
    def build_interface
      ::Hipe::InterfaceReflector::RequestParser.new do |o|
        o.on('-h [<subcommand>]','--help [<subcommand>]', 'show this screen')
        o.arg('<subcommand>')
      end
    end
    def add_subcommand_definition defn
      @subcommands ||= []
      @subcommands.push defn
    end
    attr_reader :subcommands
  end
  module DispatcherCliInstanceMethods
    include ::Hipe::InterfaceReflector::InstanceMethods
    include ::Hipe::InterfaceReflector::CliInstanceMethods
    def default_action; :dispatch end
    def arguments_syntax_string
      respond_to?(:subcommands) or
        return interface_reflector_arguments_syntax_string
      '[ ' << self.class.subcommands.map(&:name).join(' | ') <<
        ' ] [opts] [args]'
    end
    def build_documenting_option_parser
      if ! self.class.respond_to?(:subcommands)
        return interface_reflector_build_documenting_option_parser
      end
      # overrides 'parent', assumes exactly one argument! see overridden
      ophack = cli_option_parser.dup
      ophack.separator(em("subcommands:"))
      self.class.subcommands.each do |c|
        hack_add_argument_to_optparse(ophack, c)
      end
      ophack
    end
    def find_subcommand attempt
      subs = self.class.subcommands
      found = subs.detect { |s| s.name == attempt }
      if subcommand_soft_match? && ! found
        re = %r{\A#{Regexp.escape(attempt)}}
        founds = subs.select { |c| re =~ c.name.to_s }
        case founds.size
        when 0 ;
        when 1 ; found = founds.first
        else
          return [nil, "Invalid subcommand \"#{attempt}\". did you mean " <<
            oxford_comma(subs.map{|c| color(c.name, :green)},' or ') << "?"]
        end
      end
      found or return [nil, "Invalid subcommand \"#{attempt}\"." <<
      " expecting: " <<
        oxford_comma(subs.map{|c| color(c.name, :green)},' or ') << '.'
      ]
      return [found, nil]
    end
    def on_help arg
      arg.nil? and return interface_reflector_on_help
      found, msg = find_subcommand(arg)
      found or return error(msg)
      # this is terrible smell that can be fixed later
      if found.respond_to? :show_help
        found.show_help self, @argv.dup
        @exit_ok = true
        false
      else
        found.on_help @argv.first
      end
    end
    def on_parse_failure
      # overrides 'parent', don't surreptitously display help (todo)
      @exit_ok and return false
      @c.err.puts usage
      @c.err.puts invite
      false
    end
    def parse_opts
      if @argv.any? && @argv.first[0,1] == '-'
        return interface_reflector_parse_opts
      end
      true # no parsing of opts, deferred
    end
    def subcommand_soft_match?; true end
    def parse_args
      self.class.respond_to?(:subcommands) or
        return interface_reflector_parse_args
      @argv.empty? and return error("expecting subcommand: " <<
        oxford_comma(
          self.class.subcommands.map{ |c| color(c.name, :green)},' or '))
      attempt = @argv.first
      found, msg = find_subcommand attempt
      found or return error(msg)
      @subcommand = found
      true
    end
    def dispatch
      @subcommand.execution_context = @c
      @subcommand.parent = self
      @subcommand.invoked_with = @argv.shift
      @subcommand.run @argv
    end
  end
  module CommandDefinition
    def self.extended mod
      mod.class_eval do
        # for now it's as if we are just including, not extending but this is
        # preserved in case we add more DSL-like features to the Command class
        include CommandDefinitionInstanceMethods
      end
    end
    module CommandDefinitionInstanceMethods
      include Hipe::InterfaceReflector::InstanceMethods

      def cli_label; name end
      def intern;    name end
      attr_reader   :name
      attr_accessor :invoked_with # just in case you need to know
      def option_parser &block
        if ! block_given?
          interface
        elsif @interface_definition_block
          fail("implement  merging")
        else
          @interface_definition_block = block
        end
      end
      def parent= p
        class << self ; self end.send(:define_method, :parent) { p }
      end
      def show_help parent, argv
        self.parent = parent
        @c = parent.execution_context
        @argv = argv
        on_help argv.shift
      end
      def interface
        @interface ||= begin
          if @interface_definition_block.nil?
            TheEmptyInterface
          else
            b = @interface_definition_block;
            @interface_definition_block = nil
            ::Hipe::InterfaceReflector::RequestParser.new(&b)
          end
        end
      end
    end
  end
  module CliInstanceMethods
    def parent_usage
      if respond_to?(:parent)
        "#{parent.parent_usage} #{name.to_s}"
      else
        "#{em('usage:')} #{program_name}"
      end
    end
  end
end
