module Hipe::InterfaceReflector
  module SubcommandsCli
    def self.extended mod
      mod.class_eval do
        extend  SubcommandCliModuleMethods
        include SubcommandCliInstanceMethods
      end
    end
  end
  module SubcommandModuleMethods
    include ::Hipe::InterfaceReflector::ModuleMethods
    def add_subcommand_definition defn
      @subcommands ||= []
      @subcommands.push defn
    end
    def on name, &b
      add_subcommand_definition(
        CommandDefinition.create_subclass(name, self, &b)
      )
    end
    attr_reader :subcommands
  end
  module SubcommandCliModuleMethods
    include SubcommandModuleMethods
    def build_interface
      ::Hipe::InterfaceReflector::RequestParser.new do |o|
        o.on('-h [<subcommand>]','--help [<subcommand>]', 'show this screen')
        o.arg('<subcommand>')
      end
    end
  end
  module SubcommandCliInstanceMethods
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
    def cli_label;                                  self.class.intern.to_s end
    def default_action;                 @subcommand ? :dispatch : :execute end
    def dispatch
      child = @subcommand.subcommand_execution_instance
      child.execution_context = @c
      child.parent = self
      child.invoked_with = @argv.shift
      child.run @argv
    end
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
    def on_help arg=nil
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
    def program_name
      respond_to?(:parent) ? parent.program_name :
        interface_reflector_program_name
    end
    def render_desc o
      respond_to?(:desc_lines) or return # root node might not?
      if desc_lines.size > 1
        o.separator(em("description:"))
        desc_lines.each { |l| o.separator(l) }
        o.separator ''
      else
        o.separator(em("description: ") << desc_lines.first)
      end
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
    def usage_syntax_string
      [ subcommand_fully_qualified_name,
        options_syntax_string,
        arguments_syntax_string
      ].compact*' '
    end
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
  end
  module DefStructModuleMethods
    def default name
      ancestors.each do |mod|
        if mod.respond_to?(:defaults) && mod.defaults.key?(name)
          return mod.defaults[name]
        end
      end
      nil
    end
    def defaults
      @defaults ||= {}
    end
    def attr_akksessor *names
      require File.dirname(__FILE__) + '/templite' # ick, meh
      mm = class << self; self end
      names.each do |name|
        mm.send(:define_method, name) do |*a|
          a.empty? ? default(name) :
            (defaults[name] = (a.size == 1 ? a.first : a))
        end
        define_method(name) do |*a|
          a.any? ? values[name] = (a.size == 1 ? a.first : a) :
          begin
            v = values.key?(name) ? values[name] : self.class.default(name)
            if v.kind_of?(String) && v.index('{')
              (values[name] = Templite.new(v)).render(self)
            elsif v.kind_of?(Array) && [String] == v.map(&:class).uniq
              v.map { |x| x.index('{') ? Templite.new(x).render(self) : x }
            elsif v.kind_of?(Templite)
              v.render self
            else
              v
            end
          end
        end
      end
    end
  end
  module DefStructInstanceMethods
    def values
      @values ||= {}
    end
  end
  module CommandDefinitionModuleMethods
    include DefStructModuleMethods
    include SubcommandCliModuleMethods
    def constantize name
      # not isomorphic, just whatever you have to do to get it valid
      name.to_s.sub(/^[^a-z]/i, '').gsub(/[^a-z0-9_]/, '').
        sub(/^([a-z])/){ $1.upcase }.intern
    end
    def create_subclass name, namespace_module, &b
      k = constantize name
      namespace_module.const_defined?(k) and fail("already have: #{k}")
      kls = Class.new(self) # make a subclass of whatever class this is
      kls.parent = namespace_module
      kls.name = name
      class << kls; self end.send(:define_method, :inspect) do
        "#{namespace_module.inspect}::#{k}"
      end
      yield kls
      namespace_module.const_set(k, kls)
      kls
    end
    def define_interface &block
      # for now, you are a cli command iff your parent is a cli
      if parent < CliInstanceMethods
        extend SubcommandCliModuleMethods
        include SubcommandCliInstanceMethods
      end
      if @interface_definition_block
        fail("interface merging not supported!")
      else
        @interface_definition_block = block
      end
    end
    def execute &b
      @execution_block = b
    end
    def parent= foo
      respond_to?(:parent) and fail("parent cannot be set twice")
      class << self ; self end.send(:define_method, :parent) { foo }
      @has_parent = true
      foo
    end
    attr_reader :has_parent
    alias_method :parent?, :has_parent
    attr_reader :execution_block
    def interface &b
      block_given? and return define_interface(&b)
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
    alias_method :request_parser, :interface # careful! experimental?
    attr_accessor :name
    def subcommand_documenting_instance; new end
    def subcommand_execution_instance;   new end
    def subcommand_on_help argv, parent
      new.subcommand_on_help argv, parent
    end
  end
  module CommandDefinitionInstanceMethods
    include InstanceMethods # get this here now in the ancestor chain
    include DefStructInstanceMethods
    def as_method_name
      "on_#{intern.to_s.gsub('-','_').gsub(/[^a-z0-9_]/i, '')}"
    end
    def desc_lines
      case d = desc
      when NilClass ; []
      when Array ; d
      else [d]
      end
    end
    def execute
      if b = self.class.execution_block
        b.call
      else
        parent.send as_method_name
      end
    end
    def intern;                                         self.class.intern end
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
  class CommandDefinition
    extend CommandDefinitionModuleMethods
    include CommandDefinitionInstanceMethods
    attr_akksessor :desc
  end
end
