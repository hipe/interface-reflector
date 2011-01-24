module Hipe::InterfaceReflector
  module SubcommandModuleMethods
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
  module SubcommandCliInstanceMethods
    # alot of these aren't just for dispatchers but for children
    include ::Hipe::InterfaceReflector::InstanceMethods
    include ::Hipe::InterfaceReflector::CliInstanceMethods
    def arguments_syntax_string
      subs = subcommands
      subs or return interface_reflector_arguments_syntax_string
      '[ ' << subs.map(&:name).join(' | ') << ' ] [opts] [args]'
    end
    def build_documenting_option_parser
      subs = self.class.respond_to?(:subcommands) ?
        self.class.subcommands : nil
      subs.nil? and return interface_reflector_build_documenting_option_parser
      ophack = cli_option_parser.dup
      ophack.separator(em("subcommands:"))
      self.class.subcommands.each do |c|
        hack_add_argument_to_optparse(ophack,
          c.subcommand_documenting_instance)
      end
      ophack
    end
    def default_action; :dispatch end
    alias_method :execution_context=, :c=
    def find_subcommand attempt
      subs = subcommands
      if subs.nil?
        return [nil, "#{color(subcommand_fully_qualified_name, :green)} "<<
          "has no subcommands.  Does not respond to #{attempt.inspect}"]
      end
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
    attr_accessor :invoked_with
    def on_help arg
      @options_ok = false # pretend there was a parse failure
      ['-h', '--help'].include?(arg) and arg = nil
      if arg && arg[0,1] == '-'
        @c.err.puts "ignoring: #{arg.inspect}"
        arg = nil
      end
      arg.nil? and return interface_reflector_on_help
      found, msg = find_subcommand(arg)
      found or return error(msg)
      @exit_ok = true # supress self parse error message!
      found.subcommand_on_help @argv, self
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
    def subcommands
      self.class.respond_to?(:subcommands) ? self.class.subcommands : nil
    end
    def subcommand_fully_qualified_name
      if respond_to? :parent
        "#{parent.subcommand_fully_qualified_name} #{cli_label}"
      else
        program_name
      end
    end
    def subcommand_soft_match?; true end
    def parse_args
      (subs = subcommands) or return interface_reflector_parse_args
      @argv.empty? and return error("expecting subcommand: " <<
        oxford_comma(subs.map{ |c| color(c.name, :green)},' or '))
      attempt = @argv.first
      found, msg = find_subcommand attempt
      found or return error(msg)
      @subcommand = found
      true
    end
    def dispatch
      child = @subcommand.subcommand_execution_instance
      child.execution_context = @c
      child.parent = self
      child.invoked_with = @argv.shift
      child.run @argv
    end
  end
  module CommandDefinitionClass
    def self.extended cls
      cls.class_eval do
        extend  CommandDefinitionModuleMethods
        include CommandDefinitionInstanceMethods
      end
    end
    module CommandDefinitionModuleMethods
      include Hipe::InterfaceReflector::InstanceMethods
      include Hipe::InterfaceReflector::SubcommandModuleMethods
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
      def intern; name end
      def option_parser &block
        if ! block_given?
          interface
        elsif @interface_definition_block
          fail("interface merging not supported!")
        else
          @interface_definition_block = block
        end
      end
      def subcommand_documenting_instance; new end
      def subcommand_execution_instance;   new end
      def subcommand_on_help argv, parent
        new.subcommand_on_help argv, parent
      end
    end
    module CommandDefinitionInstanceMethods
      def cli_label; self.class.intern.to_s end
      def intern;    self.class.intern      end
      def parent= p
        class << self ; self end.send(:define_method, :parent) { p }
      end
      def subcommand_on_help argv, parent
        self.parent = parent
        @c = parent.execution_context
        @argv = argv
        on_help argv.shift
      end
    end
  end
end
